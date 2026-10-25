import AppKit
import ServiceManagement
import TileCore

/// Menu bar item showing the active display's Desktop number and layout, with controls.
@MainActor
final class StatusBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var manager: WindowManager?
    private var needsPermission = false

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        update()
    }

    func attach(_ manager: WindowManager) {
        self.manager = manager
        needsPermission = false
        update()
    }

    func showNeedsPermission() {
        needsPermission = true
        update()
    }

    func update() {
        guard let button = item.button else { return }
        let symbol: String
        var title = ""
        if needsPermission {
            symbol = "exclamationmark.triangle"
        } else if let manager, !manager.isEnabled || manager.stageManagerActive {
            symbol = "pause.rectangle"
        } else if let status = manager?.status() {
            if status.isFullscreenSpace {
                symbol = "arrow.up.left.and.arrow.down.right"
            } else {
                symbol = status.mode == .monocle ? "square.stack" : "rectangle.split.2x1"
                title = status.desktopNumber.map { " \($0)" } ?? ""
            }
        } else {
            symbol = "rectangle.split.2x1"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TileMyMac")
        button.imagePosition = .imageLeading
        button.title = title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if needsPermission {
            menu.addItem(disabled("TileMyMac needs Accessibility access"))
            menu.addItem(action("Open Accessibility Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
            menu.addItem(.separator())
            menu.addItem(action("Quit TileMyMac", key: "q") { NSApp.terminate(nil) })
            return
        }
        guard let manager else { return }

        if manager.stageManagerActive {
            menu.addItem(disabled("Paused while Stage Manager is on"))
        } else if let status = manager.status() {
            let place = status.isFullscreenSpace ? "Fullscreen app" : status.desktopNumber.map { "Desktop \($0)" } ?? "Desktop"
            menu.addItem(disabled("\(place) · \(status.tiledCount) tiled"))
        }
        menu.addItem(.separator())

        let tiling = action("Tiling Enabled") { manager.perform(.toggleTiling) }
        tiling.state = manager.isEnabled ? .on : .off
        menu.addItem(tiling)

        let layout = NSMenuItem(title: "Layout on This Desktop", action: nil, keyEquivalent: "")
        let layouts = NSMenu()
        let current = manager.status()?.mode
        for (title, mode) in [("Tiling (BSP)", LayoutMode.bsp), ("Monocle", LayoutMode.monocle)] {
            let entry = action(title) { manager.perform(.layout(.set(mode))) }
            entry.state = current == mode ? .on : .off
            layouts.addItem(entry)
        }
        layout.submenu = layouts
        menu.addItem(layout)
        menu.addItem(action("Balance Windows") { manager.perform(.balance) })
        menu.addItem(action("Retile Everything") { manager.perform(.retile) })
        menu.addItem(.separator())

        menu.addItem(action("Edit Config…", key: ",") {
            NSWorkspace.shared.open(WindowManager.configURL)
        })
        menu.addItem(action("Reload Config", key: "r") { manager.perform(.reloadConfig) })
        if !manager.configErrors.isEmpty {
            let problems = NSMenuItem(title: "Config Problems (\(manager.configErrors.count))", action: nil, keyEquivalent: "")
            let list = NSMenu()
            manager.configErrors.forEach { list.addItem(disabled($0)) }
            problems.submenu = list
            menu.addItem(problems)
        }

        let login = action("Launch at Login") {
            let service = SMAppService.mainApp
            try? service.status == .enabled ? service.unregister() : service.register()
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action("Quit TileMyMac", key: "q") { NSApp.terminate(nil) })
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, key: String = "", _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, handler: handler)
        return item
    }
}

@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
