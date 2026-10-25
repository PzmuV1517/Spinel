import AppKit
import SpinelCore

/// Identifies one tiling area: a native Space as shown on one display. With "Displays have
/// separate Spaces" off, one Space spans every display and each display still tiles separately.
struct SpaceKey: Hashable {
    let space: UInt64
    let display: String
}

/// A snapshot of one display and the Space it is currently showing. Frames are in AX coordinates.
struct Display {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let frame: CGRect
    /// Excludes the menu bar, notch and Dock.
    let visibleFrame: CGRect
    let currentSpace: UInt64
    /// The display is showing a native fullscreen app (or split view) Space, which macOS manages.
    let isFullscreenSpace: Bool
    /// Mission Control's "Desktop N" number for this display, if the current Space is a desktop.
    let desktopNumber: Int?

    var key: SpaceKey { SpaceKey(space: currentSpace, display: uuid) }

    static func snapshot() -> [Display] {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        let managed = SkyLight.managedDisplaySpaces()

        return screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let uuid = uuidString(for: id) ?? "display-\(id)"
            // A single "Main" entry means one Space spans all displays.
            let info = managed.first { ($0["Display Identifier"] as? String) == uuid } ?? (managed.count == 1 ? managed.first : nil)
            let current = info?["Current Space"] as? [String: Any]
            let spaceID = current.map(spaceID(of:)) ?? 0
            let type = (current?["type"] as? NSNumber)?.intValue ?? 0

            var desktopNumber: Int?
            var desktops = 0
            for space in info?["Spaces"] as? [[String: Any]] ?? [] {
                let isDesktop = (space["type"] as? NSNumber)?.intValue == 0
                if isDesktop { desktops += 1 }
                if self.spaceID(of: space) == spaceID {
                    desktopNumber = isDesktop ? desktops : nil
                    break
                }
            }

            return Display(
                id: id,
                uuid: uuid,
                name: screen.localizedName,
                frame: Geometry.flip(screen.frame, primaryHeight: primaryHeight),
                visibleFrame: Geometry.flip(screen.visibleFrame, primaryHeight: primaryHeight),
                currentSpace: spaceID,
                isFullscreenSpace: type == 4,
                desktopNumber: desktopNumber
            )
        }
    }

    private static func spaceID(of space: [String: Any]) -> UInt64 {
        ((space["id64"] ?? space["ManagedSpaceID"]) as? NSNumber)?.uint64Value ?? 0
    }

    private static func uuidString(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

enum Screen {
    /// Converts between Cocoa and AX coordinates using the primary display.
    static func flip(_ point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    static var mouseLocation: CGPoint { flip(NSEvent.mouseLocation) }
}
