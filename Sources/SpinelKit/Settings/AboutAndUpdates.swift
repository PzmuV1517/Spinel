import AppKit
import QuarryKit
import SwiftUI
import SpinelCore

// MARK: - About

struct AboutPage: View {
    private var version: String {
        let info = SpinelApp.bundle.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                AppIcon(bundle: SpinelApp.bundle, size: 56).fallable("about.icon")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spinel")
                        .font(.system(size: 22, weight: .heavy))
                        .easterEggTrigger(taps: 5)
                        .fallable("about.name")
                    Text("Version \(version)").foregroundStyle(Brand.secondary).fallable("about.version")
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Fact("Made by", Credits.author)
                Divider()
                Fact("GitHub", "@\(Credits.github)", link: Credits.profile)
                Divider()
                Fact("Source", "github.com/\(Updater.repository)", link: Credits.repository("Spinel"))
                Divider()
                Fact("Bugs", "Open an issue", link: Credits.repository("Spinel").appendingPathComponent("issues"))
            }
            .glassCard(padding: 4)
            .fallable("about.card")

            Text("© \(Credits.year) \(Credits.author)")
                .font(.caption)
                .foregroundStyle(Brand.tertiary)
                .fallable("about.copyright")
        }
    }
}

// MARK: - Updates

struct UpdatesPage: View {
    @Bindable var model: SettingsModel
    let updater: Updater
    @State private var pendingOldInstall: Release?

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
                    ReleaseRow(release: release, state: updater.state(of: release), isBusy: isBusy || !updater.canInstall) {
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
