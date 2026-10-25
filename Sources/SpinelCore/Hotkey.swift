/// A global keyboard shortcut such as `alt-shift-h`, expressed as a physical key code so it
/// works regardless of the active keyboard layout.
public struct Hotkey: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var modifiers: Modifiers
    public var keyCode: UInt32

    public init(modifiers: Modifiers, keyCode: UInt32) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public static func parse(_ text: String) -> Hotkey? {
        let parts = text.lowercased().split(separator: "-").map(String.init)
        guard let keyName = parts.last, let keyCode = keyCodes[keyName] else { return nil }
        var modifiers: Modifiers = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "alt", "opt", "option": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        return Hotkey(modifiers: modifiers, keyCode: keyCode)
    }

    /// ANSI virtual key codes (`kVK_*` from Carbon's Events.h), as reported by `CGEvent`.
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24, "9": 25, "7": 26,
        "minus": 27, "8": 28, "0": 29, "rightbracket": 30, "o": 31, "u": 32, "leftbracket": 33,
        "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "quote": 39, "k": 40,
        "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46,
        "period": 47, "tab": 48, "space": 49, "grave": 50, "backspace": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}

extension Hotkey {
    /// The config spelling, e.g. `alt-shift-h`.
    public var configString: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(Self.keyName(for: keyCode) ?? "?")
        return parts.joined(separator: "-")
    }

    /// Menu-style symbols in Apple's modifier order, e.g. `⌃⌥⇧H`.
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let name = Self.keyName(for: keyCode) ?? "?"
        return text + (Self.keySymbols[name] ?? name.uppercased())
    }

    /// The config name of a key code, or `nil` if it can't be bound.
    public static func keyName(for keyCode: UInt32) -> String? { keyNames[keyCode] }

    private static let keyNames: [UInt32: String] = Dictionary(
        keyCodes.filter { $0.key != "enter" }.map { ($0.value, $0.key) },
        uniquingKeysWith: { first, _ in first }
    )

    private static let keySymbols: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "space": "Space",
        "tab": "⇥", "escape": "⎋", "backspace": "⌫", "comma": ",", "period": ".", "minus": "-",
        "equal": "=", "slash": "/", "semicolon": ";", "quote": "'", "grave": "`",
        "leftbracket": "[", "rightbracket": "]", "backslash": "\\",
    ]
}
