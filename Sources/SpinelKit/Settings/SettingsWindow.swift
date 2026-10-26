import AppKit
import QuarryKit
import SwiftUI
import SpinelCore

/// Owns the settings window. While it is open Spinel shows in the Dock and ⌘-Tab like a
/// regular app; when it closes the app goes back to living only in the menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let updater: Updater
    private var window: NSWindow?

    init(manager: WindowManager, updater: Updater) {
        model = SettingsModel(manager: manager)
        self.updater = updater
    }

    func show(_ tab: SettingsTab = .general) {
        model.reload()
        model.tab = tab
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, updater: updater)))
        window.title = "Spinel"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)  // the Ferriteworks look is black-only
        window.backgroundColor = .black
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 860, height: 600))
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.isRecording = false
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel
    let updater: Updater

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarButton(tab.title, symbol: tab.symbol, isSelected: (model.tab ?? .general) == tab) { model.tab = tab }
                        .fallable("sidebar.\(tab.rawValue)")
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            PageContainer { SettingsPage(model: model, tab: model.tab ?? .general, updater: updater) }
                .navigationTitle("")
        }
        .easterEggStage(finale: SpinelEasterEgg.finale)
        .ferriteStyle()
    }
}

/// One page of Spinel's settings on its own, as Quarry shows it.
struct SinglePage: View {
    let model: SettingsModel
    let tab: SettingsTab

    var body: some View {
        PageContainer { SettingsPage(model: model, tab: tab, updater: nil) }
            .easterEggStage(host: SpinelApp.host, finale: SpinelEasterEgg.finale)
            .onDisappear { model.isRecording = false }
    }
}

struct SettingsPage: View {
    let model: SettingsModel
    let tab: SettingsTab
    let updater: Updater?

    var body: some View {
        switch tab {
        case .general: GeneralPage(model: model)
        case .layout: LayoutPage(model: model)
        case .shortcuts: ShortcutsPage(model: model)
        case .rules: RulesPage(model: model)
        case .updates: if let updater { UpdatesPage(model: model, updater: updater) }
        case .about: AboutPage()
        }
    }
}

