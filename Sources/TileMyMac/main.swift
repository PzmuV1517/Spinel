import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBar?
    private var manager: WindowManager?
    private var permissionTimer: Timer?

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
        statusBar?.attach(manager)
        manager.start()
    }
}

/// `TileMyMac --diagnose` prints what the window manager sees of displays and Spaces.
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
