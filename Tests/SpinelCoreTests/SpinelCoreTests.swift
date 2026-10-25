import CoreGraphics
import XCTest
@testable import SpinelCore

final class LayoutTreeTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func testSingleWindowFillsBoundsMinusOuterGap() {
        let tree = LayoutTree()
        tree.insert(1, in: bounds)
        XCTAssertEqual(tree.frames(in: bounds, gaps: Gaps(inner: 0, outer: 10))[1], CGRect(x: 10, y: 10, width: 980, height: 580))
    }

    func testDwindleSplitsAlongLongerSide() {
        let tree = LayoutTree()
        tree.insert(1, in: bounds)
        tree.insert(2, near: 1, in: bounds)
        tree.insert(3, near: 2, in: bounds)
        let f = tree.frames(in: bounds)
        XCTAssertEqual(f[1], CGRect(x: 0, y: 0, width: 500, height: 600))
        XCTAssertEqual(f[2], CGRect(x: 500, y: 0, width: 500, height: 300))
        XCTAssertEqual(f[3], CGRect(x: 500, y: 300, width: 500, height: 300))
        XCTAssertEqual(tree.windows, [1, 2, 3])
    }

    func testInnerGap() {
        let tree = LayoutTree()
        tree.insert(1, in: bounds)
        tree.insert(2, in: bounds)
        let f = tree.frames(in: bounds, gaps: Gaps(inner: 10, outer: 0))
        XCTAssertEqual(f[1], CGRect(x: 0, y: 0, width: 495, height: 600))
        XCTAssertEqual(f[2], CGRect(x: 505, y: 0, width: 495, height: 600))
    }

    func testRemoveCollapsesSplitAndReportsSibling() {
        let tree = LayoutTree()
        [1, 2, 3].forEach { tree.insert($0, near: $0 - 1, in: bounds) }
        XCTAssertEqual(tree.sibling(of: 3), 2)
        XCTAssertTrue(tree.remove(2))
        XCTAssertEqual(tree.frames(in: bounds)[3], CGRect(x: 500, y: 0, width: 500, height: 600))
        XCTAssertTrue(tree.remove(1))
        XCTAssertTrue(tree.remove(3))
        XCTAssertTrue(tree.isEmpty)
        XCTAssertFalse(tree.remove(3))
    }

    func testSwapAndToggleSplit() {
        let tree = LayoutTree()
        tree.insert(1, in: bounds)
        tree.insert(2, in: bounds)
        tree.swap(1, 2)
        XCTAssertEqual(tree.windows, [2, 1])
        tree.toggleSplit(1)
        XCTAssertEqual(tree.frames(in: bounds)[2], CGRect(x: 0, y: 0, width: 1000, height: 300))
    }

    func testResizeMovesNearestMatchingSplit() {
        let tree = LayoutTree()
        tree.insert(1, in: bounds)
        tree.insert(2, in: bounds)
        tree.resize(2, axis: .horizontal, by: 100, in: bounds)
        XCTAssertEqual(tree.frames(in: bounds)[2]?.width, 600)
        tree.resize(1, axis: .vertical, by: 100, in: bounds)  // no vertical split: no-op
        XCTAssertEqual(tree.frames(in: bounds)[1]?.width, 400)
    }

    func testAdjustToMouseResizedFrame() {
        let tree = LayoutTree()
        [1, 2, 3].forEach { tree.insert($0, near: $0 - 1, in: bounds) }
        // User drags window 2's left edge to x=300 and bottom edge to y=400.
        tree.adjust(2, toMatch: CGRect(x: 300, y: 0, width: 700, height: 400), in: bounds)
        let f = tree.frames(in: bounds)
        XCTAssertEqual(f[1]?.width, 300)
        XCTAssertEqual(f[2], CGRect(x: 300, y: 0, width: 700, height: 400))
        XCTAssertEqual(f[3], CGRect(x: 300, y: 400, width: 700, height: 200))
    }

    func testBalance() {
        let tree = LayoutTree()
        [1, 2, 3].forEach { tree.insert($0, near: $0 - 1, in: bounds) }
        tree.toggleSplit(3)  // 1 | 2 | 3 side by side
        tree.balance()
        let widths = tree.windows.compactMap { tree.frames(in: bounds)[$0]?.width.rounded() }
        XCTAssertEqual(widths, [333, 333, 333])
    }
}

final class GeometryTests: XCTestCase {
    func testClosestPrefersOverlappingNeighbor() {
        let left = CGRect(x: 0, y: 0, width: 500, height: 600)
        let topRight = CGRect(x: 500, y: 0, width: 500, height: 300)
        let bottomRight = CGRect(x: 500, y: 300, width: 500, height: 300)
        let candidates: [(Int, CGRect)] = [(1, left), (2, topRight), (3, bottomRight)]
        XCTAssertEqual(Geometry.closest(from: bottomRight, toward: .left, among: candidates), 1)
        XCTAssertEqual(Geometry.closest(from: bottomRight, toward: .up, among: candidates), 2)
        XCTAssertNil(Geometry.closest(from: bottomRight, toward: .right, among: candidates))
    }

    func testClosestCrossesDisplays() {
        let window = CGRect(x: 0, y: 0, width: 800, height: 600)
        let otherDisplay = CGRect(x: 1920, y: 100, width: 800, height: 600)
        XCTAssertEqual(Geometry.closest(from: window, toward: .right, among: [("b", otherDisplay)]), "b")
    }

    func testFlipIsInvolution() {
        let r = CGRect(x: 10, y: 20, width: 300, height: 200)
        XCTAssertEqual(Geometry.flip(Geometry.flip(r, primaryHeight: 1000), primaryHeight: 1000), r)
        XCTAssertEqual(Geometry.flip(r, primaryHeight: 1000).minY, 780)
    }
}

final class ConfigTests: XCTestCase {
    func testPartialConfigFallsBackToDefaults() throws {
        let config = try Config.decode(Data(#"{"gaps": {"inner": 4, "outer": 2}}"#.utf8))
        XCTAssertEqual(config.gaps, Gaps(inner: 4, outer: 2))
        XCTAssertEqual(config.bindings, Config.defaultBindings)
    }

    func testDefaultBindingsAllParse() {
        let (bindings, errors) = Config.default.resolvedBindings()
        XCTAssertEqual(errors, [])
        XCTAssertEqual(bindings.count, Config.defaultBindings.count)
    }

    func testRoundTrip() throws {
        XCTAssertEqual(try Config.decode(Config.default.encoded()), Config.default)
    }

    func testRules() {
        var config = Config.default
        config.rules = [
            WindowRule(app: "Finder", title: "^Copy", float: true),
            WindowRule(app: "com.apple.calculator", float: false),
        ]
        XCTAssertEqual(config.shouldFloat(bundleID: "com.apple.finder", appName: "Finder", title: "Copy 3 items"), true)
        XCTAssertNil(config.shouldFloat(bundleID: "com.apple.finder", appName: "Finder", title: "Downloads"))
        XCTAssertEqual(config.shouldFloat(bundleID: "com.apple.calculator", appName: "Calculator", title: ""), false)
        XCTAssertEqual(config.shouldFloat(bundleID: "com.apple.systempreferences", appName: nil, title: ""), true)
    }
}

final class ParsingTests: XCTestCase {
    func testHotkey() {
        XCTAssertEqual(Hotkey.parse("alt-shift-h"), Hotkey(modifiers: [.option, .shift], keyCode: 4))
        XCTAssertEqual(Hotkey.parse("cmd-ctrl-minus"), Hotkey(modifiers: [.command, .control], keyCode: 27))
        XCTAssertNil(Hotkey.parse("hyper-h"))
        XCTAssertNil(Hotkey.parse("alt-nope"))
    }

    func testCommands() {
        XCTAssertEqual(Command.parse("focus left"), .focus(.left))
        XCTAssertEqual(Command.parse("resize width -40"), .resize(.horizontal, .points(-40)))
        XCTAssertEqual(Command.parse("grow height"), .resize(.vertical, .grow))
        XCTAssertEqual(Command.parse("layout monocle"), .layout(.set(.monocle)))
        XCTAssertEqual(Command.parse("move-to-display prev"), .moveToDisplay(.previous))
        XCTAssertEqual(Command.parse("focus-display up"), .focusDisplay(.direction(.up)))
        XCTAssertNil(Command.parse("focus sideways"))
        XCTAssertNil(Command.parse(""))
    }
}

final class SettingsSupportTests: XCTestCase {
    func testHotkeyStringsRoundTrip() {
        for key in Config.defaultBindings.keys {
            let hotkey = Hotkey.parse(key)!
            XCTAssertEqual(Hotkey.parse(hotkey.configString), hotkey, key)
        }
        XCTAssertEqual(Hotkey.parse("alt-shift-h")?.displayString, "⌥⇧H")
        XCTAssertEqual(Hotkey.parse("ctrl-alt-left")?.displayString, "⌃⌥←")
        XCTAssertEqual(Hotkey.parse("cmd-enter")?.configString, "cmd-return")
    }

    func testCatalogCommandsParseAndCoverDefaults() {
        for info in Command.catalog { XCTAssertNotNil(Command.parse(info.command), info.command) }
        let catalogued = Set(Command.catalog.map(\.command))
        for command in Config.defaultBindings.values { XCTAssertTrue(catalogued.contains(command), command) }
        XCTAssertEqual(Set(Command.catalog.map(\.group)), Set(Command.catalogGroups))
    }
}

final class VersionTests: XCTestCase {
    func testParsingAndOrdering() {
        XCTAssertEqual(Version("v0.2.0")?.description, "0.2.0")
        XCTAssertNil(Version("v0.2-beta"))
        XCTAssertNil(Version(""))
        XCTAssertLessThan(Version("0.1.1")!, Version("v0.2.0")!)
        XCTAssertLessThan(Version("0.9")!, Version("0.10")!)
        XCTAssertEqual(Version("1.0")!, Version("1.0.0")!)
        XCTAssertFalse(Version("1.2.0")! < Version("1.1.9")!)
    }
}
