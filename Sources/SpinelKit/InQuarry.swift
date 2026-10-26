import AppKit
import QuarryKit
import SwiftUI

/// Where Spinel is running from.
@MainActor
enum SpinelApp {
    static let identifier = "io.github.pzmuv1517.Spinel"

    /// Set while Spinel runs inside Quarry.
    static var host: QuarryHost?
    static var isInQuarry: Bool { host != nil }

    /// Spinel.app, found from this library's own path. Inside Quarry `Bundle.main` is Quarry.
    static let bundle: Bundle = {
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let path = info.dli_fname else { return .main }
        let app = URL(fileURLWithPath: String(cString: path))
            .deletingLastPathComponent()  // Frameworks
            .deletingLastPathComponent()  // Contents
            .deletingLastPathComponent()
        return app.pathExtension == "app" ? Bundle(url: app) ?? .main : .main
    }()
}

/// Spinel as a Quarry tool: its menu items go in Quarry's menu and its settings pages in
/// Quarry's window. Quarry installs and updates it, so it has no updater of its own here.
@MainActor
final class SpinelTool: NSObject, QuarryTool {
    private var manager: WindowManager?
    private var model: SettingsModel?

    var pages: [[String: String]] {
        [SettingsTab.general, .layout, .shortcuts, .rules, .about].map {
            QuarryPage(id: $0.rawValue, title: $0.title, symbol: $0.symbol).dictionary
        }
    }

    func start() {
        guard manager == nil else { return }
        let manager = WindowManager()
        manager.onChange = { SpinelApp.host?.toolDidChange(SpinelApp.identifier) }
        self.manager = manager
        model = SettingsModel(manager: manager)
        manager.start()
    }

    func populateMenu(_ menu: NSMenu) {
        guard let manager else { return }
        SpinelMenu.addItems(to: menu, manager: manager, standalone: false) { tab in
            SpinelApp.host?.showPage(tab.rawValue, ofTool: SpinelApp.identifier)
        }
    }

    func makePage(_ id: String) -> NSViewController {
        guard let model else {
            return NSHostingController(rootView: PageContainer {
                Text("Spinel starts once Quarry has Accessibility access.").foregroundStyle(Brand.secondary)
            })
        }
        model.reload()
        return NSHostingController(rootView: SinglePage(model: model, tab: SettingsTab(rawValue: id) ?? .general))
    }

    var menuBarTitle: String? {
        guard let manager, manager.isEnabled, !manager.stageManagerActive,
              let status = manager.status(), !status.isFullscreenSpace
        else { return nil }
        return status.desktopNumber.map(String.init)
    }
}

@_cdecl("quarry_interface_version")
public func quarryInterfaceVersion() -> Int32 { QuarryInterface.version }

@_cdecl("quarry_tool_make")
public func quarryToolMake(_ host: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    // Quarry calls this on the main thread. The pointer leaves as an address, which is Sendable.
    let address = MainActor.assumeIsolated {
        SpinelApp.host = QuarryInterface.host(from: host)
        return UInt(bitPattern: QuarryInterface.export(SpinelTool()))
    }
    return UnsafeMutableRawPointer(bitPattern: address)
}
