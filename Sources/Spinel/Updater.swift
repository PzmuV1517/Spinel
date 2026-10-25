import AppKit
import Observation
import Security
import SpinelCore

/// Lists GitHub releases and installs them in place. A downloaded build is only installed if it
/// is signed by the same team as the running app.
@MainActor
@Observable
final class Updater {
    struct Release: Identifiable, Equatable {
        let id: Int
        let tag: String
        let version: Version?
        let notes: String
        let date: Date?
        let zip: URL?
        let page: URL
        /// Released as TileMyMac: listed for history, never installable over Spinel.
        let isLegacy: Bool
    }

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
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(Version.init)
    }

    var latest: Release? { releases.first { $0.version != nil && $0.zip != nil } }

    var updateAvailable: Bool {
        guard let latest = latest?.version, let current = currentVersion else { return false }
        return latest > current
    }

    /// Whether this copy can replace itself: it must be a signed .app in a writable folder.
    var canInstall: Bool {
        let bundle = Bundle.main.bundleURL
        return bundle.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
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
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError("GitHub returned \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            releases = try Self.parse(data)
            lastChecked = Date()
            phase = .idle
        } catch {
            phase = .failed("Couldn't check for updates: \(error.localizedDescription)")
        }
    }

    func install(_ release: Release) async {
        guard let zip = release.zip else { return }
        guard canInstall else {
            phase = .failed("Move Spinel to Applications to install updates.")
            return
        }
        phase = .installing(release.tag)
        do {
            let (download, _) = try await URLSession.shared.download(from: zip)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("Spinel-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let archive = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: download, to: archive)

            let newApp = try await Task.detached {
                try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
                let app = work.appendingPathComponent("Spinel.app")
                guard FileManager.default.fileExists(atPath: app.path) else { throw UpdateError("The download has no Spinel.app") }
                guard Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw UpdateError("The download is a different app")
                }
                return app
            }.value

            guard let expected = Self.teamIdentifier(of: Bundle.main.bundleURL),
                  Self.teamIdentifier(of: newApp) == expected else {
                throw UpdateError("The download isn't signed by the same developer")
            }

            let target = Bundle.main.bundleURL
            _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
            relaunch(target)
        } catch {
            phase = .failed("Update failed: \(error.localizedDescription)")
        }
    }

    private func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static func parse(_ data: Data) throws -> [Release] {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Item: Decodable {
            let id: Int
            let tag_name: String
            let body: String?
            let published_at: Date?
            let html_url: URL
            let draft: Bool
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Item].self, from: data)
            .filter { !$0.draft }
            .map { item in
                let zip = item.assets.first { $0.name.hasPrefix("Spinel") && $0.name.hasSuffix(".zip") }
                return Release(
                    id: item.id,
                    tag: item.tag_name,
                    version: Version(item.tag_name),
                    notes: item.body ?? "",
                    date: item.published_at,
                    zip: zip?.browser_download_url,
                    page: item.html_url,
                    // Releases from before the rename ship TileMyMac.app, which can't replace Spinel.
                    isLegacy: zip == nil && item.assets.contains { $0.name.hasPrefix("TileMyMac") }
                )
            }
            .sorted { ($0.version ?? Version("0")!) > ($1.version ?? Version("0")!) }
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("\(tool) failed") }
    }

    private static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
        else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
