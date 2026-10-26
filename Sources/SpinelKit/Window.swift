import AppKit
import SpinelCore

/// A top-level window of some app, addressed through Accessibility.
@MainActor
final class Window {
    let id: WindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    let appName: String?

    private(set) var title = ""
    private(set) var role: String?
    private(set) var subrole: String?
    private(set) var isMinimized = false
    private(set) var isFullscreen = false
    private(set) var isResizable = true
    private(set) var frame: CGRect = .zero

    init(id: WindowID, element: AXUIElement, app: NSRunningApplication) {
        self.id = id
        self.element = element
        self.pid = app.processIdentifier
        self.bundleID = app.bundleIdentifier
        self.appName = app.localizedName
    }

    func update() {
        title = element.string(kAXTitleAttribute) ?? ""
        role = element.string(kAXRoleAttribute)
        subrole = element.string(kAXSubroleAttribute)
        isMinimized = element.bool(kAXMinimizedAttribute) ?? false
        isFullscreen = element.bool("AXFullScreen") ?? false
        isResizable = element.isSettable(kAXSizeAttribute)
        updateFrame()
    }

    func updateFrame() {
        if let frame = element.frame { self.frame = frame }
    }

    /// Standard, resizable, on-screen windows are tiled; dialogs, sheets, panels, palettes,
    /// fixed-size windows and anything minimized or natively fullscreen float.
    var isStandard: Bool {
        role == kAXWindowRole && subrole == kAXStandardWindowSubrole
            && !isMinimized && !isFullscreen && frame.width > 50 && frame.height > 50
    }

    func setFrame(_ target: CGRect) {
        // Apps with AXEnhancedUserInterface on (set by VoiceOver-adjacent tools) animate every
        // AX frame change, which makes tiling crawl. Switch it off for the duration.
        let app = AXUIElementCreateApplication(pid)
        let enhanced = app.bool("AXEnhancedUserInterface") == true
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        // Size, position, size: shrinking first lets the window cross onto a smaller display,
        // and the second size fixes apps that clamp size to the display they started on.
        element.setSize(target.size)
        element.setPosition(target.origin)
        element.setSize(target.size)
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
        updateFrame()
    }

    func focus() {
        Self.focus(element, pid: pid)
    }

    /// Focuses any window, including ones we don't manage such as native fullscreen windows.
    static func focus(_ element: AXUIElement, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        app.set(kAXFrontmostAttribute, kCFBooleanTrue)
        element.set(kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    func setNativeFullscreen(_ on: Bool) {
        element.set("AXFullScreen", on ? kCFBooleanTrue : kCFBooleanFalse)
    }
}
