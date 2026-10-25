import AppKit
import TileCore

/// Keeps one layout tree per (native Space, display) and reconciles it with what macOS shows.
///
/// macOS stays in charge of Spaces, fullscreen and which display a window is on; we only
/// observe those and arrange the windows of whatever Space each display is currently showing.
/// Trees for Spaces that are not visible are left untouched, so switching back restores them.
@MainActor
final class WindowManager {
    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/tilemymac/config.json")

    private(set) var config = Config.default
    private(set) var configErrors: [String] = []
    private(set) var isEnabled = true
    private(set) var stageManagerActive = false
    private(set) var displays: [Display] = []
    var onChange: (() -> Void)?

    private var trees: [SpaceKey: LayoutTree] = [:]
    private var modes: [SpaceKey: LayoutMode] = [:]
    private var zoomed: [SpaceKey: WindowID] = [:]
    private var windows: [WindowID: Window] = [:]
    /// Floating toggled by the user, overriding rules and heuristics, and vice versa.
    private var userFloating: Set<WindowID> = []
    private var userTiled: Set<WindowID> = []
    /// The frame we last asked each window to take and how many times in a row we asked.
    private var applied: [WindowID: (frame: CGRect, attempts: Int)] = [:]
    /// Where a window that left a tree (minimized, hidden, fullscreened) should come back.
    private var reinsertNear: [WindowID: WindowID] = [:]
    /// Moves we initiated that macOS may not have reflected in the window's Space yet.
    private var pendingMoves: [WindowID: (key: SpaceKey, until: Date)] = [:]
    private var lastFocused: WindowID?
    private var observers: [pid_t: AppObserver] = [:]
    private var draggedWindow: WindowID?
    private var movedDuringMouseDown = false
    private var refreshPending = false
    private let hotkeys = HotkeyCenter()
    private var tokens: [NSObjectProtocol] = []
    private var mouseMonitor: Any?

    // MARK: - Lifecycle

    func start() {
        loadConfig()
        subscribe()
        refresh()
    }

    private func subscribe() {
        let workspace = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.workspaceEvent(note) }
            })
        }
        tokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(after: 0.5) }
        })
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
    }

    private func workspaceEvent(_ note: Notification) {
        switch note.name {
        case NSWorkspace.didTerminateApplicationNotification:
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                observers.removeValue(forKey: app.processIdentifier)?.invalidate()
            }
            scheduleRefresh()
        case NSWorkspace.didActivateApplicationNotification:
            focusChanged()
        case NSWorkspace.didLaunchApplicationNotification:
            // Give the app a moment to create its first window and accept AX connections.
            scheduleRefresh(after: 0.5)
        default:
            scheduleRefresh()
        }
    }

    private func axEvent(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            if NSEvent.pressedMouseButtons & 1 != 0 {
                // The user is dragging; act once on mouse-up instead of fighting the drag.
                movedDuringMouseDown = true
                if let id = element.windowID, displayShowing(id) != nil { draggedWindow = id }
                return
            }
            scheduleRefresh()
        case kAXFocusedWindowChangedNotification:
            focusChanged()
        default:
            scheduleRefresh()
        }
    }

    func scheduleRefresh(after delay: TimeInterval = 0.05) {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshPending = false
                self.refresh()
            }
        }
    }

    // MARK: - Config

    func loadConfig() {
        let url = Self.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Config.default.encoded().write(to: url)
        }
        configErrors = []
        do {
            config = try Config.decode(Data(contentsOf: url))
        } catch {
            config = .default
            configErrors.append("config.json could not be read, using defaults: \(error)")
        }

        hotkeys.unregisterAll()
        if !hotkeys.isActive { configErrors.append("Keyboard shortcuts are unavailable: Accessibility access is missing") }
        let (bindings, errors) = config.resolvedBindings()
        configErrors += errors
        for (hotkey, command) in bindings {
            let registered = hotkeys.register(hotkey) { [weak self] in self?.perform(command) }
            if !registered {
                let keys = config.bindings.keys.filter { Hotkey.parse($0) == hotkey }.sorted()
                configErrors.append("\(keys.joined(separator: " and ")) are the same shortcut")
            }
        }
        onChange?()
    }

    // MARK: - Reconciliation

    func refresh() {
        let started = Date()
        defer {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > 0.1 { log.notice("refresh took \(Int(elapsed * 1000)) ms") }
        }
        displays = Display.snapshot()
        stageManagerActive = Self.isStageManagerOn()
        defer { onChange?() }
        guard isEnabled, !stageManagerActive else { return }

        let (seen, unresponsive) = enumerateWindows()
        let focused = focusedWindowID()

        var assignment: [WindowID: SpaceKey] = [:]
        var incoming: [SpaceKey: [Window]] = [:]
        for window in seen where isTileable(window) {
            guard let key = key(for: window) else { continue }
            assignment[window.id] = key
            incoming[key, default: []].append(window)
        }

        // Prune: a window lives in exactly one tree, and leaves visible trees when it is gone,
        // minimized, hidden, fullscreened or no longer tileable.
        let visible = Set(displays.filter { !$0.isFullscreenSpace }.map(\.key))
        for (key, tree) in trees {
            for id in tree.windows {
                if let target = assignment[id] {
                    if target != key { tree.remove(id) }
                    continue
                }
                guard visible.contains(key) else { continue }
                if let window = windows[id], unresponsive.contains(window.pid) { continue }
                if let sibling = tree.sibling(of: id) { reinsertNear[id] = sibling }
                tree.remove(id)
                if zoomed[key] == id { zoomed[key] = nil }
            }
        }

        for display in displays where !display.isFullscreenSpace {
            let tree = tree(for: display.key)
            let newcomers = (incoming[display.key] ?? [])
                .filter { !tree.contains($0.id) }
                .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
            for window in newcomers {
                let anchor = [reinsertNear.removeValue(forKey: window.id), focused, lastFocused]
                    .compactMap { $0 }
                    .first { tree.contains($0) }
                tree.insert(window.id, near: anchor, in: display.visibleFrame, gaps: config.gaps)
            }
            apply(display)
        }

        if let focused, displayShowing(focused) != nil { lastFocused = focused }
    }

    /// Reads every window of every regular, visible app. Apps that fail to answer in time are
    /// reported so their windows are not mistaken for closed ones.
    private func enumerateWindows() -> (windows: [Window], unresponsive: Set<pid_t>) {
        var result: [Window] = []
        var unresponsive: Set<pid_t> = []
        var seen: Set<WindowID> = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            let appStarted = Date()
            defer {
                let elapsed = Date().timeIntervalSince(appStarted)
                if elapsed > 0.05 { log.notice("\(app.localizedName ?? "?", privacy: .public) took \(Int(elapsed * 1000)) ms") }
            }
            let observer = observer(for: app)
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.5)
            guard let elements = axApp.windows() else {
                log.notice("\(app.localizedName ?? "?", privacy: .public) did not answer")
                unresponsive.insert(app.processIdentifier)
                continue
            }
            for element in elements {
                guard let id = element.windowID else { continue }
                let window = windows[id] ?? Window(id: id, element: element, app: app)
                window.update()
                windows[id] = window
                observer?.watch(window)
                seen.insert(id)
                result.append(window)
            }
        }
        let inTrees = Set(trees.values.flatMap(\.windows))
        for (id, window) in windows where !seen.contains(id) && !inTrees.contains(id) && !unresponsive.contains(window.pid) {
            windows[id] = nil
            applied[id] = nil
            observers[window.pid]?.forget(id)
        }
        return (result, unresponsive)
    }

    private func observer(for app: NSRunningApplication) -> AppObserver? {
        let pid = app.processIdentifier
        if let observer = observers[pid] { return observer }
        let observer = AppObserver(pid: pid) { [weak self] notification, element in
            self?.axEvent(notification, element)
        }
        observers[pid] = observer
        return observer
    }

    private func isTileable(_ window: Window) -> Bool {
        guard window.isStandard, !userFloating.contains(window.id) else { return false }
        if userTiled.contains(window.id) { return true }
        if let float = config.shouldFloat(bundleID: window.bundleID, appName: window.appName, title: window.title) {
            return !float
        }
        return window.isResizable
    }

    /// Which visible (Space, display) a window belongs to, or `nil` if it is on a hidden Space,
    /// a fullscreen Space, or on every Space at once.
    private func key(for window: Window) -> SpaceKey? {
        let candidates = displays.filter { !$0.isFullscreenSpace }
        let spaces = SkyLight.spaces(forWindow: window.id)
        var natural: SpaceKey?
        if spaces.count <= 1 {
            let onSpace = spaces.isEmpty ? candidates : candidates.filter { spaces.contains($0.currentSpace) }
            natural = onSpace.max {
                Geometry.intersectionArea($0.frame, window.frame) < Geometry.intersectionArea($1.frame, window.frame)
            }?.key
        }
        if let pending = pendingMoves[window.id] {
            if natural != pending.key, pending.until > Date(), candidates.contains(where: { $0.key == pending.key }) {
                return pending.key
            }
            pendingMoves[window.id] = nil
        }
        return natural
    }

    private func tree(for key: SpaceKey) -> LayoutTree {
        if let tree = trees[key] { return tree }
        let tree = LayoutTree()
        trees[key] = tree
        return tree
    }

    func mode(_ key: SpaceKey) -> LayoutMode { modes[key] ?? config.defaultLayout }

    // MARK: - Applying layouts

    private func targetFrames(_ display: Display) -> [WindowID: CGRect] {
        guard let tree = trees[display.key], !tree.isEmpty else { return [:] }
        let bounds = display.visibleFrame
        let full = bounds.insetBy(dx: config.gaps.outer, dy: config.gaps.outer)
        var frames: [WindowID: CGRect]
        switch mode(display.key) {
        case .bsp: frames = tree.frames(in: bounds, gaps: config.gaps)
        case .monocle: frames = Dictionary(uniqueKeysWithValues: tree.windows.map { ($0, full) })
        }
        if let id = zoomed[display.key], frames[id] != nil { frames[id] = full }
        return frames.mapValues(\.pixelAligned)
    }

    private func apply(_ display: Display) {
        for (id, target) in targetFrames(display) {
            guard let window = windows[id] else { continue }
            if Geometry.approximatelyEqual(window.frame, target) {
                applied[id] = (target, 0)
                continue
            }
            // Give up after a few tries when an app refuses a frame (e.g. a minimum size),
            // instead of looping on its resize notifications forever.
            let attempts = applied[id].map { $0.frame == target ? $0.attempts : 0 } ?? 0
            guard attempts < 3 else { continue }
            window.setFrame(target)
            applied[id] = (target, attempts + 1)
        }
    }

    // MARK: - Mouse

    private func mouseUp() {
        defer { movedDuringMouseDown = false }
        guard let id = draggedWindow else {
            if movedDuringMouseDown { scheduleRefresh() }
            return
        }
        draggedWindow = nil
        defer {
            applied[id] = nil
            scheduleRefresh()
        }
        guard let window = windows[id], let display = displayShowing(id), let tree = trees[display.key],
              let expected = applied[id]?.frame else { return }
        window.updateFrame()

        let resized = abs(window.frame.width - expected.width) > 2 || abs(window.frame.height - expected.height) > 2
        if resized {
            if mode(display.key) == .bsp {
                tree.adjust(id, toMatch: window.frame, in: display.visibleFrame, gaps: config.gaps)
            }
            return
        }

        // Dropped somewhere: swap with the tiled window under the cursor, or join that display.
        let cursor = Screen.mouseLocation
        if let (target, targetDisplay) = tiledWindow(at: cursor, excluding: id) {
            if targetDisplay.key == display.key {
                tree.swap(id, target)
            } else {
                transfer(id, from: display, to: targetDisplay, near: target, focus: false)
            }
        } else if let targetDisplay = displays.first(where: { $0.frame.contains(cursor) }),
                  targetDisplay.key != display.key, !targetDisplay.isFullscreenSpace {
            transfer(id, from: display, to: targetDisplay, near: nil, focus: false)
        }
    }

    private func tiledWindow(at point: CGPoint, excluding excluded: WindowID) -> (WindowID, Display)? {
        for display in displays where !display.isFullscreenSpace && display.frame.contains(point) {
            let frames = targetFrames(display).filter { $0.key != excluded && $0.value.contains(point) }
            if let id = frontmost(among: Set(frames.keys)) ?? frames.keys.first { return (id, display) }
        }
        return nil
    }

    // MARK: - Focus

    private func focusChanged() {
        let focused = focusedWindowID()
        if let focused, let display = displayShowing(focused) {
            lastFocused = focused
            // Focusing another window on a zoomed Space ends the zoom.
            if let zoomedID = zoomed[display.key], zoomedID != focused {
                zoomed[display.key] = nil
                apply(display)
            }
        }
        onChange?()
    }

    private func focusedWindowElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier).element(kAXFocusedWindowAttribute)
    }

    func focusedWindowID() -> WindowID? { focusedWindowElement()?.windowID }

    /// The visible display whose current tree contains `id`.
    private func displayShowing(_ id: WindowID) -> Display? {
        displays.first { !$0.isFullscreenSpace && trees[$0.key]?.contains(id) == true }
    }

    /// The display the user is working on: the focused window's, else the one under the cursor.
    func activeDisplay() -> Display? {
        if let id = focusedWindowID(), let display = displayShowing(id) { return display }
        if let frame = focusedWindowElement()?.frame {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if let display = displays.first(where: { $0.frame.contains(center) }) { return display }
        }
        let mouse = Screen.mouseLocation
        return displays.first { $0.frame.contains(mouse) } ?? displays.first
    }

    private func focus(window id: WindowID) {
        guard let window = windows[id] else { return }
        window.focus()
        if config.mouseFollowsFocus {
            CGWarpMouseCursorPosition(CGPoint(x: window.frame.midX, y: window.frame.midY))
        }
    }

    private func focus(display: Display) {
        if let top = frontmost(among: Set(trees[display.key]?.windows ?? [])) {
            focus(window: top)
            return
        }
        // Fullscreen apps and floating windows aren't in a tree: focus whatever is in front there.
        // Some front-most windows have no AX counterpart (e.g. Chrome's fullscreen toolbar), so
        // take the first one that does.
        for (id, pid) in windowsFrontToBack(on: display) {
            guard let element = AXUIElementCreateApplication(pid).windows()?.first(where: { $0.windowID == id }),
                  element.string(kAXRoleAttribute) == kAXWindowRole else { continue }
            Window.focus(element, pid: pid)
            if config.mouseFollowsFocus, let frame = element.frame {
                CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
            }
            return
        }
        // Nothing to focus: at least bring the cursor over so the user sees where they are.
        CGWarpMouseCursorPosition(CGPoint(x: display.visibleFrame.midX, y: display.visibleFrame.midY))
    }

    /// Normal windows whose center is on `display`, managed or not, front-most first.
    private func windowsFrontToBack(on display: Display) -> [(WindowID, pid_t)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != getpid(),
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width > 50, bounds.height > 50,
                  display.frame.contains(CGPoint(x: bounds.midX, y: bounds.midY))
            else { return nil }
            return (id, pid)
        }
    }

    /// The front-most of `ids` in the window server's stacking order.
    private func frontmost(among ids: Set<WindowID>) -> WindowID? {
        guard !ids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for info in list {
            if let number = info[kCGWindowNumber as String] as? NSNumber, ids.contains(number.uint32Value) {
                return number.uint32Value
            }
        }
        return nil
    }

    // MARK: - Commands

    func perform(_ command: Command) {
        log.info("perform \(String(describing: command), privacy: .public)")
        switch command {
        case .toggleTiling:
            isEnabled.toggle()
            if isEnabled { refresh() } else { onChange?() }
            return
        case .reloadConfig:
            loadConfig()
            refresh()
            return
        default:
            break
        }
        guard isEnabled, !stageManagerActive else { return }
        displays = Display.snapshot()

        switch command {
        case .focus(let direction): focus(direction)
        case .move(let direction): move(direction)
        case .resize(let axis, let amount):
            withFocusedTile { id, display, tree in
                let delta: Double
                switch amount {
                case .grow: delta = config.resizeStep
                case .shrink: delta = -config.resizeStep
                case .points(let points): delta = points
                }
                tree.resize(id, axis: axis, by: delta, in: display.visibleFrame, gaps: config.gaps)
            }
        case .toggleSplit:
            withFocusedTile { id, _, tree in tree.toggleSplit(id) }
        case .balance:
            if let display = activeDisplay(), let tree = trees[display.key] {
                tree.balance()
                apply(display)
            }
        case .toggleFloat: toggleFloat()
        case .zoom:
            withFocusedTile { id, display, _ in
                zoomed[display.key] = zoomed[display.key] == id ? nil : id
            }
        case .nativeFullscreen:
            if let element = focusedWindowElement() {
                element.set("AXFullScreen", element.bool("AXFullScreen") == true ? kCFBooleanFalse : kCFBooleanTrue)
            }
        case .layout(let change):
            guard let display = activeDisplay() else { return }
            switch change {
            case .set(let mode): modes[display.key] = mode
            case .toggle: modes[display.key] = mode(display.key) == .bsp ? .monocle : .bsp
            }
            apply(display)
            if let id = focusedWindowID() { focus(window: id) }
            onChange?()
        case .focusDisplay(let target):
            if let current = activeDisplay(), let display = resolve(target, from: current) { focus(display: display) }
        case .moveToDisplay(let target): moveToDisplay(target)
        case .retile:
            trees.removeAll()
            zoomed.removeAll()
            applied.removeAll()
            refresh()
        case .toggleTiling, .reloadConfig:
            break
        }
    }

    /// Runs `body` on the focused window's tree, then re-applies that display's layout.
    private func withFocusedTile(_ body: (WindowID, Display, LayoutTree) -> Void) {
        guard let id = focusedWindowID(), let display = displayShowing(id), let tree = trees[display.key] else { return }
        body(id, display, tree)
        apply(display)
    }

    private func focus(_ direction: Direction) {
        let focusedID = focusedWindowID()

        // Monocle: left/up and right/down cycle through the stack.
        if let id = focusedID, let display = displayShowing(id), mode(display.key) == .monocle,
           let list = trees[display.key]?.windows, list.count > 1, let index = list.firstIndex(of: id) {
            let next = (index + (direction.isForward ? 1 : list.count - 1)) % list.count
            focus(window: list[next])
            return
        }

        enum Target: Hashable {
            case window(WindowID)
            /// A display with nothing tiled on it, e.g. one showing a fullscreen app.
            case display(String)
        }
        let mouse = Screen.mouseLocation
        let source = focusedWindowElement()?.frame ?? CGRect(origin: mouse, size: .zero)
        var candidates: [(Target, CGRect)] = []
        for display in displays {
            let frames = display.isFullscreenSpace ? [:] : targetFrames(display)
            if frames.isEmpty {
                candidates.append((.display(display.uuid), display.frame))
            } else if mode(display.key) == .monocle {
                if let top = frontmost(among: Set(frames.keys)), let frame = frames[top] { candidates.append((.window(top), frame)) }
            } else {
                candidates += frames.map { (.window($0.key), $0.value) }
            }
        }
        candidates.removeAll { $0.0 == focusedID.map(Target.window) }
        switch Geometry.closest(from: source, toward: direction, among: candidates) {
        case .window(let id): focus(window: id)
        case .display(let uuid): displays.first { $0.uuid == uuid }.map { focus(display: $0) }
        case nil: break
        }
    }

    private func move(_ direction: Direction) {
        guard let id = focusedWindowID(), let display = displayShowing(id), let tree = trees[display.key] else { return }
        // Use the BSP geometry even in monocle so moves stay predictable when switching back.
        let frames = tree.frames(in: display.visibleFrame, gaps: config.gaps)
        if let source = frames[id],
           let target = Geometry.closest(from: source, toward: direction, among: frames.filter { $0.key != id }.map { ($0.key, $0.value) }) {
            tree.swap(id, target)
            apply(display)
            return
        }
        // At the edge of this display: continue onto the neighboring one.
        if let next = resolve(.direction(direction), from: display), !next.isFullscreenSpace {
            let nextFrames = targetFrames(next).map { ($0.key, $0.value) }
            let anchor = frames[id].flatMap { Geometry.closest(from: $0, toward: direction, among: nextFrames) }
            transfer(id, from: display, to: next, near: anchor, focus: true)
        }
    }

    private func moveToDisplay(_ target: DisplayTarget) {
        guard let current = activeDisplay(), let next = resolve(target, from: current), !next.isFullscreenSpace,
              let id = focusedWindowID() else { return }
        if displayShowing(id) != nil {
            transfer(id, from: current, to: next, near: frontmost(among: Set(trees[next.key]?.windows ?? [])), focus: true)
        } else if let element = focusedWindowElement(), let frame = element.frame {
            // Floating: keep its size, center it on the other display.
            let area = next.visibleFrame
            let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
            element.setPosition(CGPoint(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded()))
        }
    }

    /// Moves a tiled window into another display's current Space.
    private func transfer(_ id: WindowID, from source: Display, to target: Display, near anchor: WindowID?, focus shouldFocus: Bool) {
        trees[source.key]?.remove(id)
        if zoomed[source.key] == id { zoomed[source.key] = nil }
        tree(for: target.key).insert(id, near: anchor, in: target.visibleFrame, gaps: config.gaps)
        pendingMoves[id] = (target.key, Date().addingTimeInterval(1.5))
        applied[id] = nil
        apply(target)
        apply(source)
        if shouldFocus { focus(window: id) }
    }

    private func toggleFloat() {
        guard let id = focusedWindowID(), let window = windows[id] else { return }
        if let display = displayShowing(id) {
            trees[display.key]?.remove(id)
            if zoomed[display.key] == id { zoomed[display.key] = nil }
            userFloating.insert(id)
            userTiled.remove(id)
            applied[id] = nil
            let area = display.visibleFrame
            let size = CGSize(width: area.width * 0.6, height: area.height * 0.6)
            window.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                   width: size.width, height: size.height).pixelAligned)
            apply(display)
            window.focus()
        } else {
            userFloating.remove(id)
            userTiled.insert(id)
            refresh()
        }
    }

    private func resolve(_ target: DisplayTarget, from current: Display) -> Display? {
        let ordered = displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        guard ordered.count > 1, let index = ordered.firstIndex(where: { $0.uuid == current.uuid }) else { return nil }
        switch target {
        case .next:
            return ordered[(index + 1) % ordered.count]
        case .previous:
            return ordered[(index + ordered.count - 1) % ordered.count]
        case .direction(let direction):
            let others = ordered.filter { $0.uuid != current.uuid }
            let uuid = Geometry.closest(from: current.frame, toward: direction, among: others.map { ($0.uuid, $0.frame) })
            return others.first { $0.uuid == uuid }
        }
    }

    // MARK: - Status

    struct Status {
        var desktopNumber: Int?
        var isFullscreenSpace: Bool
        var mode: LayoutMode
        var tiledCount: Int
    }

    func status() -> Status? {
        guard let display = activeDisplay() else { return nil }
        return Status(
            desktopNumber: display.desktopNumber,
            isFullscreenSpace: display.isFullscreenSpace,
            mode: mode(display.key),
            tiledCount: trees[display.key]?.windows.count ?? 0
        )
    }

    /// Stage Manager owns window placement while it is on, so tiling pauses.
    private static func isStageManagerOn() -> Bool {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue("GloballyEnabled" as CFString, domain) as? Bool) ?? false
    }
}
