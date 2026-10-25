import Foundation

public struct WindowRule: Codable, Equatable, Sendable {
    /// Bundle identifier (`com.apple.finder`) or app name (`Finder`).
    public var app: String?
    /// Regular expression matched against the window title.
    public var title: String?
    public var float: Bool

    public init(app: String? = nil, title: String? = nil, float: Bool) {
        self.app = app
        self.title = title
        self.float = float
    }

    func matches(bundleID: String?, appName: String?, title windowTitle: String) -> Bool {
        if let app, app != bundleID, app.caseInsensitiveCompare(appName ?? "") != .orderedSame {
            return false
        }
        if let title {
            guard windowTitle.range(of: title, options: .regularExpression) != nil else { return false }
        }
        return app != nil || title != nil
    }
}

/// User configuration, stored as JSON at `~/.config/spinel/config.json`.
/// Every key is optional; missing keys fall back to the defaults below.
public struct Config: Codable, Equatable, Sendable {
    public var gaps: Gaps
    public var defaultLayout: LayoutMode
    /// Points added or removed by `grow` / `shrink`.
    public var resizeStep: Double
    /// Warp the cursor to the center of a window focused by keyboard.
    public var mouseFollowsFocus: Bool
    /// Bundle identifiers whose windows always float.
    public var floatApps: [String]
    /// Evaluated in order; the first matching rule wins and overrides `floatApps`.
    public var rules: [WindowRule]
    /// Hotkey (`alt-shift-h`) → command (`move left`).
    public var bindings: [String: String]
    /// Install new GitHub releases automatically.
    public var autoUpdate: Bool

    public init(
        gaps: Gaps = Gaps(inner: 8, outer: 8),
        defaultLayout: LayoutMode = .bsp,
        resizeStep: Double = 60,
        mouseFollowsFocus: Bool = false,
        floatApps: [String] = Config.defaultFloatApps,
        rules: [WindowRule] = [],
        bindings: [String: String] = Config.defaultBindings,
        autoUpdate: Bool = true
    ) {
        self.gaps = gaps
        self.defaultLayout = defaultLayout
        self.resizeStep = resizeStep
        self.mouseFollowsFocus = mouseFollowsFocus
        self.floatApps = floatApps
        self.rules = rules
        self.bindings = bindings
        self.autoUpdate = autoUpdate
    }

    public static let `default` = Config()

    public static let defaultFloatApps = [
        "com.apple.systempreferences",
        "com.apple.calculator",
        "com.apple.archiveutility",
        "com.apple.ScreenSharing",
    ]

    public static let defaultBindings: [String: String] = [
        "alt-h": "focus left",
        "alt-j": "focus down",
        "alt-k": "focus up",
        "alt-l": "focus right",
        "alt-shift-h": "move left",
        "alt-shift-j": "move down",
        "alt-shift-k": "move up",
        "alt-shift-l": "move right",
        "alt-ctrl-h": "shrink width",
        "alt-ctrl-l": "grow width",
        "alt-ctrl-j": "grow height",
        "alt-ctrl-k": "shrink height",
        "alt-left": "focus left",
        "alt-down": "focus down",
        "alt-up": "focus up",
        "alt-right": "focus right",
        "alt-shift-left": "move left",
        "alt-shift-down": "move down",
        "alt-shift-up": "move up",
        "alt-shift-right": "move right",
        "alt-ctrl-left": "shrink width",
        "alt-ctrl-right": "grow width",
        "alt-ctrl-down": "grow height",
        "alt-ctrl-up": "shrink height",
        "alt-e": "toggle-split",
        "alt-shift-b": "balance",
        "alt-shift-space": "toggle-float",
        "alt-f": "zoom",
        "alt-shift-f": "fullscreen",
        "alt-m": "layout toggle",
        "alt-comma": "focus-display previous",
        "alt-period": "focus-display next",
        "alt-shift-comma": "move-to-display previous",
        "alt-shift-period": "move-to-display next",
        "alt-shift-t": "toggle-tiling",
        "alt-shift-r": "retile",
    ]

    enum CodingKeys: String, CodingKey {
        case gaps, defaultLayout, resizeStep, mouseFollowsFocus, floatApps, rules, bindings, autoUpdate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        gaps = try c.decodeIfPresent(Gaps.self, forKey: .gaps) ?? d.gaps
        defaultLayout = try c.decodeIfPresent(LayoutMode.self, forKey: .defaultLayout) ?? d.defaultLayout
        resizeStep = try c.decodeIfPresent(Double.self, forKey: .resizeStep) ?? d.resizeStep
        mouseFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .mouseFollowsFocus) ?? d.mouseFollowsFocus
        floatApps = try c.decodeIfPresent([String].self, forKey: .floatApps) ?? d.floatApps
        rules = try c.decodeIfPresent([WindowRule].self, forKey: .rules) ?? d.rules
        bindings = try c.decodeIfPresent([String: String].self, forKey: .bindings) ?? d.bindings
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? d.autoUpdate
    }

    public static func decode(_ data: Data) throws -> Config {
        try JSONDecoder().decode(Config.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// `true`/`false` when a rule or `floatApps` decides, `nil` to fall back to heuristics.
    public func shouldFloat(bundleID: String?, appName: String?, title: String) -> Bool? {
        if let rule = rules.first(where: { $0.matches(bundleID: bundleID, appName: appName, title: title) }) {
            return rule.float
        }
        if let bundleID, floatApps.contains(bundleID) { return true }
        return nil
    }

    /// Bindings that parse, plus human-readable problems for the ones that don't.
    public func resolvedBindings() -> (bindings: [(Hotkey, Command)], errors: [String]) {
        var out: [(Hotkey, Command)] = []
        var errors: [String] = []
        for (key, value) in bindings.sorted(by: { $0.key < $1.key }) {
            guard let hotkey = Hotkey.parse(key) else {
                errors.append("Unknown hotkey \"\(key)\"")
                continue
            }
            guard let command = Command.parse(value) else {
                errors.append("Unknown command \"\(value)\" for \(key)")
                continue
            }
            out.append((hotkey, command))
        }
        return (out, errors)
    }
}
