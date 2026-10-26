import ApplicationServices
import SpinelCore

extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }

    func bool(_ attribute: String) -> Bool? { (value(attribute) as? NSNumber)?.boolValue }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// `nil` only when the app could not answer (busy / not ready), so callers can tell
    /// "no windows" apart from "don't know".
    func windows() -> [AXUIElement]? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value) {
        case .success: return (value as? [AXUIElement]) ?? []
        case .noValue, .attributeUnsupported: return []
        default: return nil
        }
    }

    var frame: CGRect? {
        guard let position = axValue(kAXPositionAttribute), let size = axValue(kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private func axValue(_ attribute: String) -> AXValue? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    func setPosition(_ point: CGPoint) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) { set(kAXPositionAttribute, value) }
    }

    func setSize(_ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) { set(kAXSizeAttribute, value) }
    }

    var windowID: WindowID? { SkyLight.windowID(of: self) }
}
