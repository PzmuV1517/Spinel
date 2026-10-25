import AppKit
import ServiceManagement
import SpinelCore

/// Menu bar item showing the active display's Desktop number and layout, with controls.
@MainActor
final class StatusBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var manager: WindowManager?
    var openSettings: ((SettingsTab) -> Void)?
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
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Spinel")
        button.imagePosition = .imageLeading
        button.title = title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if needsPermission {
            menu.addItem(disabled("Needs Accessibility access"))
            menu.addItem(action("Open Accessibility Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
            menu.addItem(.separator())
            menu.addItem(action("Quit Spinel", key: "q") { NSApp.terminate(nil) })
            return
        }
        guard let manager else { return }

        if manager.stageManagerActive {
            menu.addItem(disabled("Paused for Stage Manager"))
        } else if let status = manager.status() {
            let place = status.isFullscreenSpace ? "Fullscreen app" : status.desktopNumber.map { "Desktop \($0)" } ?? "Desktop"
            menu.addItem(disabled("\(place) · \(status.tiledCount) \(status.tiledCount == 1 ? "window" : "windows")"))
        }
        menu.addItem(.separator())

        let tiling = action("Tiling") { manager.perform(.toggleTiling) }
        tiling.state = manager.isEnabled ? .on : .off
        menu.addItem(tiling)

        let layout = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        let layouts = NSMenu()
        let current = manager.status()?.mode
        for (title, mode) in [("Tiling", LayoutMode.bsp), ("Monocle", LayoutMode.monocle)] {
            let entry = action(title) { manager.perform(.layout(.set(mode))) }
            entry.state = current == mode ? .on : .off
            layouts.addItem(entry)
        }
        layout.submenu = layouts
        menu.addItem(layout)
        menu.addItem(action("Balance") { manager.perform(.balance) })
        menu.addItem(action("Retile") { manager.perform(.retile) })
        menu.addItem(.separator())

        menu.addItem(action("Settings…", key: ",") { [weak self] in self?.openSettings?(.general) })
        menu.addItem(action("Shortcuts…") { [weak self] in self?.openSettings?(.shortcuts) })
        menu.addItem(action("Reload Config", key: "r") { manager.perform(.reloadConfig) })
        if !manager.configErrors.isEmpty {
            let problems = NSMenuItem(title: "Config Errors (\(manager.configErrors.count))", action: nil, keyEquivalent: "")
            let list = NSMenu()
            manager.configErrors.forEach { list.addItem(disabled($0)) }
            problems.submenu = list
            menu.addItem(problems)
        }

        let login = action("Open at Login") {
            let service = SMAppService.mainApp
            try? service.status == .enabled ? service.unregister() : service.register()
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action("About Spinel") { [weak self] in self?.openSettings?(.about) })
        menu.addItem(action("Quit Spinel", key: "q") { NSApp.terminate(nil) })
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
