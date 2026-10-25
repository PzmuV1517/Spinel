/// A bindable command as shown in the settings UI.
public struct CommandInfo: Hashable, Sendable {
    public let command: String
    public let title: String
    public let group: String
}

extension Command {
    /// Every command the settings UI offers, in display order.
    public static let catalog: [CommandInfo] = {
        var list: [CommandInfo] = []
        func add(_ group: String, _ entries: [(String, String)]) {
            list += entries.map { CommandInfo(command: $0.0, title: $0.1, group: group) }
        }
        add("Focus", [
            ("focus left", "Focus Left"), ("focus down", "Focus Down"),
            ("focus up", "Focus Up"), ("focus right", "Focus Right"),
            ("focus-display previous", "Focus Previous Display"), ("focus-display next", "Focus Next Display"),
        ])
        add("Move", [
            ("move left", "Move Left"), ("move down", "Move Down"),
            ("move up", "Move Up"), ("move right", "Move Right"),
            ("move-to-display previous", "Move to Previous Display"), ("move-to-display next", "Move to Next Display"),
        ])
        add("Resize", [
            ("grow width", "Wider"), ("shrink width", "Narrower"),
            ("grow height", "Taller"), ("shrink height", "Shorter"),
            ("balance", "Balance Windows"),
        ])
        add("Layout", [
            ("toggle-split", "Flip Split"), ("layout toggle", "Toggle Tiling / Monocle"),
            ("layout bsp", "Tiling Layout"), ("layout monocle", "Monocle Layout"),
            ("zoom", "Zoom"), ("fullscreen", "Native Fullscreen"), ("toggle-float", "Float / Tile Window"),
        ])
        add("Control", [
            ("toggle-tiling", "Pause / Resume Tiling"), ("retile", "Retile Everything"),
            ("reload-config", "Reload Config"),
        ])
        return list
    }()

    public static let catalogGroups = ["Focus", "Move", "Resize", "Layout", "Control"]

    public static func title(for command: String) -> String {
        catalog.first { $0.command == command }?.title ?? command
    }
}
