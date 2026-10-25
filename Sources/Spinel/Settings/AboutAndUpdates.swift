import AppKit
import SwiftUI
import SpinelCore

// MARK: - About

struct AboutPage: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                AppIconView(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spinel").font(.system(size: 22, weight: .heavy))
                    Text("Version \(version)").foregroundStyle(Brand.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Fact("Made by", Credits.author)
                Divider()
                Fact("GitHub", "@\(Credits.github)", link: Credits.profile)
                Divider()
                Fact("Source", "github.com/\(Updater.repository)", link: Credits.repository)
                Divider()
                Fact("Bugs", "Open an issue", link: Credits.repository.appendingPathComponent("issues"))
            }
            .glassCard(padding: 4)

            Text("© \(Credits.year) \(Credits.author)")
                .font(.caption)
                .foregroundStyle(Brand.tertiary)
        }
    }
}

/// A label / value line, optionally a link.
private struct Fact: View {
    let label: String
    let value: String
    var link: URL?

    init(_ label: String, _ value: String, link: URL? = nil) {
        self.label = label
        self.value = value
        self.link = link
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Brand.tertiary).frame(width: 90, alignment: .leading)
            if let link {
                Link(destination: link) {
                    HStack(spacing: 4) {
                        Text(value)
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }
                }
                .foregroundStyle(Brand.primary)
            } else {
                Text(value)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

enum Credits {
    static let author = "Andrei Banu"
    static let github = "PzmuV1517"
    static let repository = URL(string: "https://github.com/\(Updater.repository)")!
    static let profile = URL(string: "https://github.com/\(github)")!
    static let year = "2026"
}

// MARK: - Updates

struct UpdatesPage: View {
    @Bindable var model: SettingsModel
    let updater: Updater
    @State private var pendingOldInstall: Updater.Release?

    private var isBusy: Bool {
        switch updater.phase {
        case .checking, .installing: true
        default: false
        }
    }

    private var status: String {
        switch updater.phase {
        case .checking: return "Checking…"
        case .installing(let tag): return "Installing \(tag)…"
        default:
            if updater.updateAvailable, let latest = updater.latest { return "\(latest.tag) is available" }
            if updater.lastChecked != nil { return "Up to date" }
            return "Version \(updater.currentVersion?.description ?? "dev")"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GlassSection(title: "Updates") {
                Row(title: "Install automatically", info: "Checks GitHub every 6 hours and restarts Spinel after installing.") {
                    Toggle("", isOn: $model.config.autoUpdate).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status)
                        if let checked = updater.lastChecked {
                            Text("Checked \(checked.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(Brand.tertiary)
                        }
                    }
                    Spacer()
                    if updater.updateAvailable, let latest = updater.latest {
                        Button("Install \(latest.tag)") { Task { await updater.install(latest) } }
                            .glassButton(prominent: true)
                            .disabled(isBusy)
                    }
                    Button("Check Now") { Task { await updater.check() } }
                        .glassButton()
                        .disabled(isBusy)
                }
                if !updater.canInstall {
                    Text("Installing needs Spinel in the Applications folder.")
                        .font(.caption)
                        .foregroundStyle(Brand.tertiary)
                }
            }

            GlassSection(title: "Versions") {
                if updater.releases.isEmpty {
                    Text(updater.phase == .checking ? "Loading…" : "No releases found")
                        .foregroundStyle(Brand.secondary)
                }
                ForEach(updater.releases) { release in
                    if release != updater.releases.first { Divider() }
                    ReleaseRow(release: release, current: updater.currentVersion, isBusy: isBusy || !updater.canInstall) {
                        if let version = release.version, version < Updater.firstSelfUpdatingVersion {
                            pendingOldInstall = release
                        } else {
                            Task { await updater.install(release) }
                        }
                    }
                }
            }

            if case .failed(let message) = updater.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
        .task {
            if updater.releases.isEmpty { await updater.check() }
        }
        .alert(
            "Install \(pendingOldInstall?.tag ?? "")?",
            isPresented: Binding(get: { pendingOldInstall != nil }, set: { if !$0 { pendingOldInstall = nil } }),
            presenting: pendingOldInstall
        ) { release in
            Button("Install") { Task { await updater.install(release) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This version can't update itself. To come back, download a newer one from GitHub.")
        }
    }
}

private struct ReleaseRow: View {
    let release: Updater.Release
    let current: Version?
    let isBusy: Bool
    let onInstall: () -> Void
    @State private var isExpanded = false

    private var isInstalled: Bool { release.version != nil && release.version == current }
    private var isOlder: Bool {
        guard let version = release.version, let current else { return false }
        return version < current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Brand.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(release.tag).font(.system(size: 14, weight: .bold))
                        if let date = release.date {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(Brand.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if isInstalled {
                    Text("Installed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Brand.hairline))
                } else if release.zip != nil {
                    Button(isOlder ? "Downgrade" : "Install", action: onInstall)
                        .glassButton()
                        .disabled(isBusy)
                }
                Link(destination: release.page) {
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(Brand.secondary)
                .help("Open on GitHub")
            }

            if isExpanded {
                Text(Self.notes(release.notes))
                    .font(.callout)
                    .foregroundStyle(Brand.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 18)
            }
        }
    }

    /// GitHub release notes as styled text; headings become bold lines.
    static func notes(_ markdown: String) -> AttributedString {
        let text = markdown.isEmpty ? "No notes." : markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard line.hasPrefix("#") else { return String(line) }
                return "**" + line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) + "**"
            }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
