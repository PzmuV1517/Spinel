public enum DisplayTarget: Equatable, Sendable {
    case next, previous
    case direction(Direction)
}

public enum ResizeAmount: Equatable, Sendable {
    /// Use the configured `resizeStep`.
    case grow, shrink
    case points(Double)
}

public enum LayoutChange: Equatable, Sendable {
    case set(LayoutMode)
    case toggle
}

/// Everything a hotkey (or, later, the CLI) can ask the window manager to do.
public enum Command: Equatable, Sendable {
    case focus(Direction)
    case move(Direction)
    case resize(Axis, ResizeAmount)
    case toggleSplit
    case balance
    case toggleFloat
    case zoom
    case nativeFullscreen
    case layout(LayoutChange)
    case focusDisplay(DisplayTarget)
    case moveToDisplay(DisplayTarget)
    case toggleTiling
    case retile
    case reloadConfig

    /// Parses commands such as `focus left`, `resize width -40`, `grow height`,
    /// `layout monocle`, `move-to-display next`.
    public static func parse(_ text: String) -> Command? {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let verb = words.first else { return nil }
        let args = Array(words.dropFirst())

        switch (verb, args.count) {
        case ("focus", 1): return Direction(rawValue: args[0]).map(Command.focus)
        case ("move", 1): return Direction(rawValue: args[0]).map(Command.move)
        case ("resize", 2):
            guard let axis = axis(args[0]), let points = Double(args[1]) else { return nil }
            return .resize(axis, .points(points))
        case ("grow", 1): return axis(args[0]).map { .resize($0, .grow) }
        case ("shrink", 1): return axis(args[0]).map { .resize($0, .shrink) }
        case ("toggle-split", 0): return .toggleSplit
        case ("balance", 0): return .balance
        case ("toggle-float", 0): return .toggleFloat
        case ("zoom", 0): return .zoom
        case ("fullscreen", 0): return .nativeFullscreen
        case ("layout", 1):
            if args[0] == "toggle" { return .layout(.toggle) }
            return LayoutMode(rawValue: args[0]).map { .layout(.set($0)) }
        case ("focus-display", 1): return displayTarget(args[0]).map(Command.focusDisplay)
        case ("move-to-display", 1): return displayTarget(args[0]).map(Command.moveToDisplay)
        case ("toggle-tiling", 0): return .toggleTiling
        case ("retile", 0): return .retile
        case ("reload-config", 0): return .reloadConfig
        default: return nil
        }
    }

    private static func axis(_ word: String) -> Axis? {
        switch word {
        case "width", "horizontal": return .horizontal
        case "height", "vertical": return .vertical
        default: return nil
        }
    }

    private static func displayTarget(_ word: String) -> DisplayTarget? {
        switch word {
        case "next": return .next
        case "prev", "previous": return .previous
        default: return Direction(rawValue: word).map(DisplayTarget.direction)
        }
    }
}
