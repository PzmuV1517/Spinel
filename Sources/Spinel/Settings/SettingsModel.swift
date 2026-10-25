import AppKit
import Observation
import ServiceManagement
import SpinelCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, layout, shortcuts, rules, updates, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .layout: "Layout"
        case .shortcuts: "Shortcuts"
        case .rules: "Window Rules"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .layout: "rectangle.split.3x1"
        case .shortcuts: "keyboard"
        case .rules: "macwindow.on.rectangle"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

/// The settings window's editable copy of the config. Every change is saved to
/// `config.json` shortly after it is made and applied right away, like System Settings.
@MainActor
@Observable
final class SettingsModel {
    struct BindingRow: Identifiable, Equatable {
        let id = UUID()
        var hotkey: String
        var command: String
    }

    var tab: SettingsTab? = .general

    var config: Config {
        didSet { if !isLoading { scheduleSave() } }
    }

    /// Shortcuts as an ordered, editable list; written back into `config.bindings`.
    var rows: [BindingRow] {
        didSet {
            guard !isLoading else { return }
            config.bindings = Dictionary(
                rows.filter { Hotkey.parse($0.hotkey) != nil }.map { ($0.hotkey, $0.command) },
                uniquingKeysWith: { _, last in last }
            )
        }
    }

    var tilingEnabled: Bool {
        didSet { if tilingEnabled != manager.isEnabled { manager.perform(.toggleTiling) } }
    }

    var launchAtLogin: Bool {
        didSet {
            let service = SMAppService.mainApp
            do {
                if launchAtLogin, service.status != .enabled { try service.register() }
                if !launchAtLogin, service.status == .enabled { try service.unregister() }
            } catch {
                saveError = "Open at login: \(error.localizedDescription)"
            }
        }
    }

    var isRecording = false {
        didSet { manager.hotkeysPaused = isRecording }
    }

    private(set) var problems: [String] = []
    private(set) var saveError: String?

    @ObservationIgnored let manager: WindowManager
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    init(manager: WindowManager) {
        self.manager = manager
        config = manager.config
        rows = Self.rows(from: manager.config.bindings)
        tilingEnabled = manager.isEnabled
        launchAtLogin = SMAppService.mainApp.status == .enabled
        problems = manager.configErrors
    }

    /// Re-reads everything from the window manager, e.g. after the file was edited by hand.
    func reload() {
        isLoading = true
        config = manager.config
        rows = Self.rows(from: manager.config.bindings)
        tilingEnabled = manager.isEnabled
        problems = manager.configErrors
        isLoading = false
    }

    func restoreDefaultShortcuts() {
        rows = Self.rows(from: Config.defaultBindings)
    }

    /// Hotkeys bound more than once.
    var duplicateHotkeys: Set<String> {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for row in rows where !row.hotkey.isEmpty {
            if !seen.insert(row.hotkey).inserted { duplicates.insert(row.hotkey) }
        }
        return duplicates
    }

    var statusLine: String {
        guard manager.isEnabled else { return "Paused" }
        guard !manager.stageManagerActive else { return "Paused for Stage Manager" }
        guard let status = manager.status() else { return "On" }
        if status.isFullscreenSpace { return "Fullscreen app" }
        let desktop = status.desktopNumber.map { "Desktop \($0)" } ?? "Desktop"
        let windows = status.tiledCount == 1 ? "1 window" : "\(status.tiledCount) windows"
        return "\(desktop) · \(windows)"
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func save() {
        do {
            try manager.save(config)
            saveError = nil
        } catch {
            saveError = "Couldn't save config.json: \(error.localizedDescription)"
        }
        problems = manager.configErrors
    }

    private static func rows(from bindings: [String: String]) -> [BindingRow] {
        let order = Dictionary(uniqueKeysWithValues: Command.catalog.enumerated().map { ($1.command, $0) })
        return bindings
            .map { BindingRow(hotkey: $0.key, command: $0.value) }
            .sorted {
                let a = order[$0.command] ?? .max
                let b = order[$1.command] ?? .max
                if a != b { return a < b }
                // H J K L before the arrow keys for the same command.
                return ($0.hotkey.count, $0.hotkey) < ($1.hotkey.count, $1.hotkey)
            }
    }
}
