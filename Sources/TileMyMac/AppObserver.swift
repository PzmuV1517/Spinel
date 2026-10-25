import AppKit
import TileCore

/// Subscribes to one app's Accessibility notifications and forwards them to a handler.
@MainActor
final class AppObserver {
    typealias Handler = @MainActor (_ notification: String, _ element: AXUIElement) -> Void

    let pid: pid_t
    private let observer: AXObserver
    private let app: AXUIElement
    private let handler: Handler
    private var watched: Set<WindowID> = []

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    private static let windowNotifications = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
    ]

    /// Fails when the app isn't ready to talk to us yet (e.g. still launching); callers retry.
    init?(pid: pid_t, handler: @escaping Handler) {
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { observer.handler(notification as String, element) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return nil }
        self.pid = pid
        self.observer = created
        self.app = AXUIElementCreateApplication(pid)
        self.handler = handler
        AXUIElementSetMessagingTimeout(app, 0.5)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.appNotifications {
            let result = AXObserverAddNotification(observer, app, notification as CFString, refcon)
            guard result == .success || result == .notificationAlreadyRegistered else { return nil }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func watch(_ window: Window) {
        guard watched.insert(window.id).inserted else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.windowNotifications {
            AXObserverAddNotification(observer, window.element, notification as CFString, refcon)
        }
    }

    func forget(_ id: WindowID) {
        watched.remove(id)
    }

    func invalidate() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}
