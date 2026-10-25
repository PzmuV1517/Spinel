import AppKit
import SwiftUI
import TileCore

/// A button that shows a shortcut and, when clicked, records the next key combination.
/// TileMyMac's own shortcuts are paused while recording so they can be re-recorded.
struct HotkeyRecorder: View {
    @Binding var hotkey: String
    /// Shared across rows so only one recorder listens at a time.
    @Binding var isRecording: Bool
    @State private var listening = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(listening ? Brand.primary : (hotkey.isEmpty ? Brand.tertiary : Brand.primary))
                .frame(minWidth: 92)
        }
        .glassButton()
        .onDisappear(perform: stop)
        .onChange(of: isRecording) { _, recording in
            // Another row started recording.
            if !recording && listening { stop() }
        }
    }

    private var label: String {
        if listening { return "Press keys" }
        return Hotkey.parse(hotkey)?.displayString ?? "Set"
    }

    private func toggle() {
        listening ? stop() : start()
    }

    private func start() {
        if isRecording { isRecording = false }  // stop any other recorder first
        listening = true
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: Hotkey.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        let keyCode = UInt32(event.keyCode)

        if keyCode == 53, modifiers.isEmpty {  // Escape cancels
            stop()
            return
        }
        guard let name = Hotkey.keyName(for: keyCode), !modifiers.isEmpty || name.hasPrefix("f") && name.count > 1 else {
            NSSound.beep()  // needs a modifier (except F-keys), and a key we can bind
            return
        }
        hotkey = Hotkey(modifiers: modifiers, keyCode: keyCode).configString
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if listening {
            listening = false
            isRecording = false
        }
    }
}
