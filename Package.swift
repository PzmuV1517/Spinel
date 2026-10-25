// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TileMyMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TileMyMac", targets: ["TileMyMac"]),
    ],
    targets: [
        // Pure, AppKit-free logic: layout trees, geometry, config, commands. Fully unit-tested.
        .target(name: "TileCore"),
        // The app: Accessibility, SkyLight (read-only), hotkeys, menu bar.
        .executableTarget(name: "TileMyMac", dependencies: ["TileCore"]),
        .testTarget(name: "TileCoreTests", dependencies: ["TileCore"]),
    ],
    swiftLanguageModes: [.v5]
)
