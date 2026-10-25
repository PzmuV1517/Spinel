import AppKit
import os
import TileCore

let log = Logger(subsystem: "dev.tilemymac.TileMyMac", category: "wm")

/// Global hotkeys through a keyboard event tap. Matching key presses are swallowed so they never
/// reach the focused app; everything else passes through untouched.
///
/// The tap runs on its own thread: if it waited on the main thread, any slow Accessibility call
/// there would make macOS time the tap out and deliver the shortcut to the app instead.
///
/// Carbon's `RegisterEventHotKey` is not used: on current macOS it reports success but never
/// delivers Option-based shortcuts. The tap needs only the Accessibility permission we already hold.
final class HotkeyCenter: @unchecked Sendable {
    private let lock = NSLock()
    /// Guarded by `lock`; read on the tap thread, written on the main thread.
    private var actions: [Hotkey: @MainActor () -> Void] = [:]
    /// Key codes whose key-down we swallowed, so the matching key-up is swallowed too. Tap thread only.
    private var swallowed: Set<UInt32> = []
    private var tap: CFMachPort?
    private let ready = DispatchSemaphore(value: 0)

    init() {
        let thread = Thread { [unowned self] in self.runTap() }
        thread.name = "TileMyMac.hotkeys"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    var isActive: Bool { tap != nil }

    private func runTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userInfo).takeUnretainedValue()
            return center.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else {
            log.error("Could not create keyboard event tap (Accessibility access missing?)")
            ready.signal()
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        ready.signal()
        CFRunLoopRun()
    }

    /// Returns `false` if the shortcut is already bound.
    @discardableResult
    func register(_ hotkey: Hotkey, action: @escaping @MainActor () -> Void) -> Bool {
        lock.withLock {
            guard actions[hotkey] == nil else { return false }
            actions[hotkey] = action
            return true
        }
    }

    func unregisterAll() {
        lock.withLock { actions.removeAll() }
    }

    /// Returns `true` when the event was a bound shortcut and must not reach the app.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            log.error("Keyboard tap was disabled (\(type.rawValue)); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown:
            let hotkey = Hotkey(modifiers: Self.modifiers(of: event.flags), keyCode: UInt32(event.getIntegerValueField(.keyboardEventKeycode)))
            guard let action = lock.withLock({ actions[hotkey] }) else { return false }
            swallowed.insert(hotkey.keyCode)
            DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
            return true
        case .keyUp:
            return swallowed.remove(UInt32(event.getIntegerValueField(.keyboardEventKeycode))) != nil
        default:
            return false
        }
    }

    private static func modifiers(of flags: CGEventFlags) -> Hotkey.Modifiers {
        var modifiers: Hotkey.Modifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }
}
