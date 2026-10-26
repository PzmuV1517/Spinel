import ApplicationServices
import Foundation

/// Read-only access to the private SkyLight (window server) and HIServices symbols we need to
/// understand native Spaces. Symbols are resolved at runtime so a future macOS that drops one
/// degrades to per-display tiling instead of crashing. Nothing here requires disabling SIP.
enum SkyLight {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT

    private static func symbol<T>(_ names: [String], in handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        for name in names {
            if let pointer = dlsym(handle, name) { return unsafeBitCast(pointer, to: type) }
        }
        return nil
    }

    private static let mainConnectionID = symbol(["SLSMainConnectionID", "CGSMainConnectionID"], in: skyLight, as: MainConnectionFn.self)
    private static let copyManagedDisplaySpaces = symbol(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], in: skyLight, as: CopyManagedDisplaySpacesFn.self)
    private static let copySpacesForWindows = symbol(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], in: skyLight, as: CopySpacesForWindowsFn.self)
    private static let getWindow = symbol(["_AXUIElementGetWindow"], in: defaultHandle, as: GetWindowFn.self)

    private static let connection: Int32? = mainConnectionID?()

    static var spacesAvailable: Bool {
        connection != nil && copyManagedDisplaySpaces != nil && copySpacesForWindows != nil
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// One dictionary per display ("Display Identifier", "Current Space", "Spaces"), or a single
    /// "Main" entry when "Displays have separate Spaces" is off.
    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let connection, let copyManagedDisplaySpaces,
              let array = copyManagedDisplaySpaces(connection)?.takeRetainedValue() else { return [] }
        return (array as? [[String: Any]]) ?? []
    }

    /// The Spaces a window lives on. Empty if unknown; more than one for "All Desktops" windows.
    static func spaces(forWindow id: CGWindowID) -> [UInt64] {
        guard let connection, let copySpacesForWindows else { return [] }
        let ids = [NSNumber(value: id)] as CFArray
        let allSpaces: Int32 = 0x7
        guard let array = copySpacesForWindows(connection, allSpaces, ids)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return array.map(\.uint64Value)
    }
}
