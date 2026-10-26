import AppKit
import QuarryKit
import SwiftUI
import SpinelCore

// MARK: - General

struct GeneralPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                AppIcon(bundle: SpinelApp.bundle, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spinel").font(.system(size: 28, weight: .heavy))
                    Label(model.statusLine, systemImage: model.tilingEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                            .foregroundStyle(Brand.secondary)
                        .font(.callout)
                }
            }
            .glassCard(cornerRadius: 26)

            GlassSection(title: "Tiling") {
                Row(title: "Enabled", info: "Turn off to arrange windows by hand. ⌥⇧T also toggles it.") {
                    Toggle("", isOn: $model.tilingEnabled).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                Row(title: "Default layout", info: "Monocle shows one full-size window at a time. ⌥M switches the current Desktop.") {
                    Picker("", selection: $model.config.defaultLayout) {
                        Text("Tiling").tag(LayoutMode.bsp)
                        Text("Monocle").tag(LayoutMode.monocle)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }
                Divider()
                Row(title: "Mouse follows focus", info: "Moves the pointer to the window you focus with the keyboard.") {
                    Toggle("", isOn: $model.config.mouseFollowsFocus).toggleStyle(.switch).labelsHidden()
                }
            }

            if !SpinelApp.isInQuarry {  // Quarry opens at login and brings Spinel with it
                GlassSection(title: "System") {
                    Row(title: "Open at login", info: "Only works from the Applications folder.") {
                        Toggle("", isOn: $model.launchAtLogin).toggleStyle(.switch).labelsHidden()
                    }
                }
            }

            GlassSection(title: "Config File", info: "Settings are saved here. You can also edit it by hand.") {
                Text(WindowManager.configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button("Open") { NSWorkspace.shared.open(WindowManager.configURL) }
                        .glassButton()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([WindowManager.configURL]) }
                        .glassButton()
                    Spacer()
                    Button("Reload") {
                        model.manager.perform(.reloadConfig)
                        model.reload()
                    }
                    .glassButton()
                }
            }

            ProblemsView(model: model)
        }
    }
}

struct ProblemsView: View {
    let model: SettingsModel

    var body: some View {
        let problems = (model.saveError.map { [$0] } ?? []) + model.problems
        if !problems.isEmpty {
            GlassSection(title: "Problems") {
                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
        }
    }
}

// MARK: - Layout

struct LayoutPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GapsPreview(gaps: model.config.gaps)
                .glassCard(cornerRadius: 26)

            GlassSection(title: "Gaps") {
                SliderRow(title: "Between windows", value: $model.config.gaps.inner, range: 0...48)
                Divider()
                SliderRow(title: "Screen edges", value: $model.config.gaps.outer, range: 0...64)
            }

            GlassSection(title: "Resizing") {
                SliderRow(title: "Step", info: "How much each ⌥⌃ H J K L press resizes a window.",
                          value: $model.config.resizeStep, range: 10...240, step: 10)
            }
        }
    }
}

struct SliderRow: View {
    let title: String
    var info: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        Row(title: title, info: info) {
            HStack(spacing: 12) {
                Slider(value: $value, in: range, step: step).frame(width: 220)
                Text("\(Int(value)) pt")
                    .monospacedDigit()
                    .foregroundStyle(Brand.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

/// A miniature screen tiled by the real layout engine with the current gaps.
struct GapsPreview: View {
    let gaps: Gaps

    var body: some View {
        GeometryReader { geometry in
            let frames = Self.frames(in: geometry.size, gaps: gaps)
            ZStack(alignment: .topLeading) {
                ForEach(frames, id: \.0) { id, frame in
                    MiniWindow(index: Int(id))
                        .frame(width: max(frame.width, 0), height: max(frame.height, 0))
                        .offset(x: frame.minX, y: frame.minY)
                        .animation(.smooth(duration: 0.25), value: frame)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background {
            ZStack {
                LinearGradient(colors: [Brand.graphite, Brand.ink], startPoint: .top, endPoint: .bottom)
                DotGrid(spacing: 14, opacity: 0.09)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.hairline))
    }

    /// Lays out three windows on a pretend 1000-point-wide screen scaled to `size`, so gaps stay legible.
    static func frames(in size: CGSize, gaps: Gaps) -> [(WindowID, CGRect)] {
        guard size.width > 0 else { return [] }
        let scale = size.width / 1000
        let bounds = CGRect(origin: .zero, size: size)
        let tree = LayoutTree()
        tree.insert(1, in: bounds)
        tree.insert(2, near: 1, in: bounds)
        tree.insert(3, near: 2, in: bounds)
        let scaled = Gaps(inner: gaps.inner * scale, outer: gaps.outer * scale)
        return tree.frames(in: bounds, gaps: scaled).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

struct MiniWindow: View {
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.28)).frame(width: 6, height: 6) }
                Spacer()
            }
            .padding(.horizontal, 7)
            .frame(height: 16)
            .background(.white.opacity(0.05))
            Spacer(minLength: 0)
        }
        .background(
            LinearGradient(colors: [Color(white: [0.30, 0.22, 0.17][(index - 1) % 3]), Color(white: [0.16, 0.12, 0.09][(index - 1) % 3])],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }
}

// MARK: - Shortcuts

struct ShortcutsPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 6) {
                InfoButton(text: "Click a shortcut and press the new keys. Esc cancels.")
                Spacer()
                Button("Reset to Defaults") { model.restoreDefaultShortcuts() }
                    .glassButton()
            }

            let duplicates = model.duplicateHotkeys
            ForEach(Command.catalogGroups, id: \.self) { group in
                GlassSection(title: group) {
                    let commands = Command.catalog.filter { $0.group == group }
                    ForEach(commands, id: \.command) { info in
                        if info != commands.first { Divider() }
                        CommandShortcuts(model: model, command: info.command, title: info.title, duplicates: duplicates)
                    }
                }
            }

            let custom = Set(model.rows.map(\.command)).subtracting(Command.catalog.map(\.command)).sorted()
            if !custom.isEmpty {
                GlassSection(title: "Custom", info: "Added in config.json.") {
                    ForEach(custom, id: \.self) { command in
                        if command != custom.first { Divider() }
                        CommandShortcuts(model: model, command: command, title: command, duplicates: duplicates)
                    }
                }
            }

            ProblemsView(model: model)
        }
    }
}

/// One command with all of its shortcuts as chips, plus a button to add another.
struct CommandShortcuts: View {
    @Bindable var model: SettingsModel
    let command: String
    let title: String
    let duplicates: Set<String>

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 12)
            ForEach(model.rows.indices.filter { model.rows[$0].command == command }, id: \.self) { index in
                HStack(spacing: 2) {
                    if duplicates.contains(model.rows[index].hotkey) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Used more than once")
                    }
                    HotkeyRecorder(hotkey: $model.rows[index].hotkey, isRecording: $model.isRecording)
                    Button {
                        model.rows.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Brand.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            }
            Button {
                model.rows.append(SettingsModel.BindingRow(hotkey: "", command: command))
            } label: {
                Image(systemName: "plus").frame(width: 12, height: 12)
            }
            .glassButton()
            .help("Add shortcut")
        }
    }
}

// MARK: - Window rules

struct RulesPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GlassSection(title: "Floating Apps", info: "Windows of these apps are never tiled.") {
                if model.config.floatApps.isEmpty {
                    Text("None").foregroundStyle(Brand.secondary)
                }
                ForEach(model.config.floatApps, id: \.self) { bundleID in
                    HStack(spacing: 12) {
                        AppBadge(bundleID: bundleID)
                        Spacer()
                        Button {
                            model.config.floatApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus").frame(width: 14, height: 14)
                        }
                        .glassButton()
                    }
                }
                Divider()
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            if let id = app.bundleIdentifier { model.config.floatApps.append(id) }
                        }
                    }
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .fixedSize()
            }

            GlassSection(title: "Rules", info: "First match wins. App is a name or bundle ID, title is a regex. Empty fields match anything.") {
                ForEach($model.config.rules.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    RuleRow(rule: $model.config.rules[index]) {
                        model.config.rules.remove(at: index)
                    }
                }
                if !model.config.rules.isEmpty { Divider() }
                Button {
                    model.config.rules.append(WindowRule(app: "", title: nil, float: true))
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .glassButton()
            }

            ProblemsView(model: model)
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.processIdentifier != getpid() }
            .filter { !model.config.floatApps.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

struct RuleRow: View {
    @Binding var rule: WindowRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("App", text: optional($rule.app))
                .textFieldStyle(.roundedBorder)
            TextField("Title", text: optional($rule.title))
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $rule.float) {
                Text("Float").tag(true)
                Text("Tile").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            Button(action: onDelete) {
                Image(systemName: "minus").frame(width: 14, height: 14)
            }
            .glassButton()
        }
    }

    /// Edits an optional string, storing empty text as `nil`.
    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

struct AppBadge: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 10) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
                Text(bundleID).font(.caption).foregroundStyle(Brand.secondary)
            }
        }
    }
}
