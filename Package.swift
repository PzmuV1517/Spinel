// swift-tools-version:6.0
import PackageDescription

// QuarryKit: the interface Quarry loads Spinel through, plus the look both share. Set QUARRY_PATH
// to build against a local checkout of Quarry (the Makefile does when ../Quarry exists).
let quarry: Package.Dependency = Context.environment["QUARRY_PATH"].map { .package(path: $0) }
    ?? .package(url: "https://github.com/PzmuV1517/Quarry.git", from: "0.1.0")

let package = Package(
    name: "Spinel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Spinel", targets: ["Spinel"]),
        // All of Spinel. The Spinel app loads it to run on its own; Quarry loads it to run it inside Quarry.
        .library(name: "SpinelKit", type: .dynamic, targets: ["SpinelKit"]),
    ],
    dependencies: [quarry],
    targets: [
        // Pure, AppKit-free logic: layout trees, geometry, config, commands. Fully unit-tested.
        .target(name: "SpinelCore"),
        // The window manager and its UI: Accessibility, SkyLight (read-only), hotkeys, settings.
        .target(name: "SpinelKit", dependencies: ["SpinelCore", .product(name: "QuarryKit", package: "Quarry")]),
        // A small launcher that loads libSpinelKit.dylib.
        .executableTarget(name: "Spinel"),
        .testTarget(name: "SpinelCoreTests", dependencies: ["SpinelCore"]),
    ],
    swiftLanguageModes: [.v5]
)
