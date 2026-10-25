// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Spinel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Spinel", targets: ["Spinel"]),
    ],
    targets: [
        // Pure, AppKit-free logic: layout trees, geometry, config, commands. Fully unit-tested.
        .target(name: "SpinelCore"),
        // The app: Accessibility, SkyLight (read-only), hotkeys, menu bar.
        .executableTarget(name: "Spinel", dependencies: ["SpinelCore"]),
        .testTarget(name: "SpinelCoreTests", dependencies: ["SpinelCore"]),
    ],
    swiftLanguageModes: [.v5]
)
