import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBar?
    private var manager: WindowManager?
    private var permissionTimer: Timer?
    private var settings: SettingsWindowController?
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBar()
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            start()
            return
        }
        statusBar?.showNeedsPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                self?.permissionTimer?.invalidate()
                self?.start()
            }
        }
    }

    private func start() {
        let manager = WindowManager()
        manager.onChange = { [weak self] in self?.statusBar?.update() }
        self.manager = manager
        updater.isAutomatic = { [weak manager] in manager?.config.autoUpdate ?? false }
        updater.startAutomaticChecks()
        let settings = SettingsWindowController(manager: manager, updater: updater)
        self.settings = settings
        statusBar?.openSettings = { settings.show($0) }
        statusBar?.attach(manager)
        NSApp.mainMenu = Self.mainMenu(target: self)
        manager.start()
        // `--settings[=tab]` opens the settings window on launch.
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--settings") }) {
            settings.show(SettingsTab(rawValue: String(argument.drop { $0 != "=" }.dropFirst())) ?? .general)
        }
    }

    /// Opening the app again (e.g. from Finder or Spotlight) shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return false
    }

    @objc private func showSettings() { settings?.show() }
    @objc private func showAbout() { settings?.show(.about) }

    /// The menu bar shown while the settings window is in front. Mostly so text fields get
    /// copy and paste and the window closes with ⌘W.
    private static func mainMenu(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Spinel", action: #selector(showAbout), keyEquivalent: "").target = target
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = target
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Spinel", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Spinel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        for (title, submenu) in [("Spinel", app), ("Edit", edit), ("Window", window)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}

/// `Spinel --diagnose` prints what the window manager sees of displays and Spaces.
func diagnose() {
    print("SkyLight Spaces API available: \(SkyLight.spacesAvailable)")
    for display in Display.snapshot() {
        let desktop = display.desktopNumber.map { "Desktop \($0)" } ?? (display.isFullscreenSpace ? "fullscreen Space" : "?")
        print("\(display.name) [\(display.uuid)] space=\(display.currentSpace) \(desktop) frame=\(display.frame) visible=\(display.visibleFrame)")
    }
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--diagnose") {
        diagnose()
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
