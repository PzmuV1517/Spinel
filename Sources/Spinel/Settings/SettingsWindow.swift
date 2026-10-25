import AppKit
import SwiftUI
import SpinelCore

/// Owns the settings window. While it is open Spinel shows in the Dock and ⌘-Tab like a
/// regular app; when it closes the app goes back to living only in the menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let updater: Updater
    private let egg = EasterEgg()
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, updater: updater).environment(egg)))
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
        egg.reset()
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel
    let updater: Updater
    @Environment(EasterEgg.self) private var egg

    var body: some View {
        NavigationSplitView {
            // Hand-built instead of a selectable List, whose highlight is always the system
            // accent color; this keeps the sidebar monochrome.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarItem(tab: tab, isSelected: (model.tab ?? .general) == tab) { model.tab = tab }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            let tab = model.tab ?? .general
            ScrollView {
                page(tab)
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .background(Backdrop())
            .navigationTitle("")
        }
        .allowsHitTesting(egg.phase == .idle)
        .overlay {
            if egg.phase == .video {
                EasterEggVideo(egg: egg).transition(.opacity)
            }
        }
        .coordinateSpace(name: EasterEgg.space)
        .onPreferenceChange(FallableFrames.self) { frames in
            MainActor.assumeIsolated { egg.frames = frames }
        }
        .tint(Color(white: 0.42))
        .foregroundStyle(Brand.primary)
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralPage(model: model)
        case .layout: LayoutPage(model: model)
        case .shortcuts: ShortcutsPage(model: model)
        case .rules: RulesPage(model: model)
        case .updates: UpdatesPage(model: model, updater: updater)
        case .about: AboutPage()
        }
    }
}

struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(tab.title, systemImage: tab.symbol)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Brand.primary : Brand.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(isSelected ? 0.12 : isHovered ? 0.05 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(isSelected ? 0.10 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .fallable("sidebar.\(tab.rawValue)")
    }
}

/// Ferriteworks-style backdrop: black fading to graphite, a faint dot grid, and soft grey
/// glows for the glass to refract.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.graphite, Brand.black], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.07), .clear], center: UnitPoint(x: 0.7, y: 0.3), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [.white.opacity(0.04), .clear], center: UnitPoint(x: 0.25, y: 0.8), startRadius: 0, endRadius: 420)
            DotGrid()
        }
        .ignoresSafeArea()
    }
}

struct DotGrid: View {
    var spacing: CGFloat = 22
    var opacity: Double = 0.07

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                }
            }
            context.fill(dots, with: .color(.white.opacity(opacity)))
        }
        .allowsHitTesting(false)
    }
}

/// Monochrome palette taken from ferriteworks.com.
enum Brand {
    static let black = Color(red: 0, green: 0, blue: 0)
    static let ink = Color(red: 0.024, green: 0.020, blue: 0.016)  // #060504
    static let graphite = Color(red: 0.086, green: 0.086, blue: 0.086)  // #161616
    static let hairline = Color.white.opacity(0.08)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.38)
}

// MARK: - Liquid Glass with a material fallback before macOS 26

extension View {
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    func glassButton(prominent: Bool = false) -> some View {
        buttonStyle(FerriteButtonStyle(prominent: prominent))
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.regularMaterial, in: Circle())
        }
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @Environment(EasterEgg.self) private var egg

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let card = content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(shape.strokeBorder(Brand.hairline))
        if egg.phase != .idle {
            // Glass smears when rotated, so falling cards get a plain fill.
            card.background(Brand.graphite, in: shape)
        } else if #available(macOS 26, *) {
            card.glassEffect(.regular.tint(.white.opacity(0.02)), in: .rect(cornerRadius: cornerRadius))
        } else {
            card.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// Dark, hairline-bordered buttons in the Ferriteworks style. The system glass buttons take
/// the window tint and come out light grey on black.
struct FerriteButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = configuration.isPressed ? 0.16 : prominent ? 0.11 : 0.05
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Brand.primary : Brand.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(fill)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(prominent ? 0.18 : 0.11)))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A small ? that shows `text` on hover and in a popover on click.
struct InfoButton: View {
    let text: String
    @State private var isShown = false

    var body: some View {
        Button { isShown.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(Brand.tertiary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(12)
        }
    }
}

/// A titled group of settings on a glass card.
struct GlassSection<Content: View>: View {
    let title: String
    var info: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Brand.tertiary)
                if let info { InfoButton(text: info) }
            }
            .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .glassCard()
        }
    }
}

/// A settings row: label (with an optional ?) on the left, control on the right.
struct Row<Control: View>: View {
    let title: String
    var info: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 6) {
                Text(title)
                if let info { InfoButton(text: info) }
            }
            Spacer(minLength: 12)
            control
        }
    }
}
