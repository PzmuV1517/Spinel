import AppKit

/// Triggers macOS's own Mission Control shortcuts, which is the only way to switch Spaces
/// without disabling SIP. Reads the user's actual key assignments from System Settings.
enum SystemShortcut {
    case previousSpace
    case nextSpace

    /// Marks events we post so our own keyboard tap lets them through untouched.
    static let marker: Int64 = 0x5350_494E  // "SPIN"

    /// IDs in `com.apple.symbolichotkeys`, with macOS's defaults (⌃← / ⌃→).
    private var id: String { self == .previousSpace ? "79" : "81" }
    private var defaultKey: CGKeyCode { self == .previousSpace ? 123 : 124 }
    private static let defaultFlags: UInt64 = 0x84_0000  // control + function (arrow keys carry fn)

    /// Returns `false` if the shortcut is turned off in System Settings.
    @discardableResult
    func post() -> Bool {
        var key = defaultKey
        var flags = Self.defaultFlags
        let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        if let entry = hotkeys?[id] as? [String: Any] {
            if let enabled = entry["enabled"] as? Bool, !enabled { return false }
            if let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int], parameters.count == 3 {
                key = CGKeyCode(parameters[1])
                flags = UInt64(parameters[2])
            }
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else { return false }
            event.flags = CGEventFlags(rawValue: flags)
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
