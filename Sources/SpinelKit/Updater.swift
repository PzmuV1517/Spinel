import AppKit
import Observation
import QuarryKit

/// Spinel's own updater, used when it runs on its own (inside Quarry, Quarry updates it). Lists
/// GitHub releases and installs them in place; see `Releases` for the checks a download passes.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case checking
        case installing(String)
        case failed(String)
    }

    nonisolated static let repository = "PzmuV1517/Spinel"
    /// Releases older than this can't update themselves.
    nonisolated static let firstSelfUpdatingVersion = Version("0.3.0")!

    private(set) var releases: [Release] = []
    private(set) var phase: Phase = .idle
    private(set) var lastChecked: Date?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored var isAutomatic: () -> Bool = { false }

    var currentVersion: Version? {
        (SpinelApp.bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(Version.init)
    }

    var latest: Release? { releases.first { $0.version != nil && $0.zip != nil } }

    var updateAvailable: Bool {
        guard let latest = latest?.version, let current = currentVersion else { return false }
        return latest > current
    }

    /// Whether this copy can replace itself: it must be a signed .app in a writable folder.
    var canInstall: Bool {
        Releases.canReplace(SpinelApp.bundle.bundleURL)
    }

    /// Checks shortly after launch and then every six hours; installs if automatic updates are on.
    func startAutomaticChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.automaticCheck() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            MainActor.assumeIsolated { self?.automaticCheck() }
        }
    }

    private func automaticCheck() {
        guard isAutomatic() else { return }
        Task {
            await check()
            if updateAvailable, canInstall, let latest { await install(latest) }
        }
    }

    func check() async {
        guard phase != .checking else { return }
        phase = .checking
        do {
            releases = try await Releases.fetch(repository: Self.repository, appName: "Spinel", legacyNames: ["TileMyMac"])
            lastChecked = Date()
            phase = .idle
        } catch {
            phase = .failed("Couldn't check for updates: \(error.localizedDescription)")
        }
    }

    func install(_ release: Release) async {
        guard canInstall else {
            phase = .failed("Move Spinel to Applications to install updates.")
            return
        }
        phase = .installing(release.tag)
        do {
            let target = SpinelApp.bundle.bundleURL
            let app = try await Releases.download(
                release, appName: "Spinel", bundleIdentifier: SpinelApp.identifier, team: Releases.teamIdentifier(of: target)
            )
            try Releases.place(app, at: target)
            Releases.relaunch(target)
        } catch {
            phase = .failed("Update failed: \(error.localizedDescription)")
        }
    }

    func state(of release: Release) -> ReleaseRow.State {
        if release.isLegacy {
            return .unavailable(label: "TileMyMac", reason: "Released under the old name. It can't be installed over Spinel.")
        }
        guard let version = release.version, release.zip != nil else {
            return .unavailable(label: "No download", reason: "This release has no app attached.")
        }
        if version == currentVersion { return .installed }
        return .available(currentVersion.map { version < $0 } == true ? "Downgrade" : "Install")
    }
}
