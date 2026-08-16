import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleTerminal = Self("toggleTerminal")
}

@MainActor
enum HotkeyManager {
    /// The double-tap-Control detector needs to see `flagsChanged` both while some other app is
    /// frontmost (global monitor) and while ClaudeSnap's own panel is key (local monitor) — a
    /// global monitor alone goes blind the moment our own window has focus.
    private static var globalMonitor: Any?
    private static var localMonitor: Any?
    private static var wasControlDown = false
    private static var lastControlOnlyPressAt: Date?
    private static let doubleTapWindow: TimeInterval = 0.35

    static func registerToggleHandler(_ handler: @escaping () -> Void, preferences: AppPreferences) {
        // Exactly one hotkey mechanism is ever live, gated by the Preferences picker — not by
        // whether a Recorder shortcut happens to be set, so "custom mode, key cleared" means no
        // hotkey at all rather than silently falling back to double-tap.
        KeyboardShortcuts.onKeyUp(for: .toggleTerminal) {
            guard preferences.hotkeyMode == .custom else { return }
            handler()
        }

        func handleFlagsChanged(_ event: NSEvent) {
            guard preferences.hotkeyMode == .doubleControlTap else { return }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isControlOnly = flags == .control
            let isControlDown = flags.contains(.control)

            if isControlDown && !wasControlDown {
                if isControlOnly, let last = lastControlOnlyPressAt, Date().timeIntervalSince(last) < doubleTapWindow {
                    lastControlOnlyPressAt = nil
                    handler()
                } else {
                    lastControlOnlyPressAt = isControlOnly ? Date() : nil
                }
            } else if isControlDown && !isControlOnly {
                // A chord (e.g. Ctrl+Cmd) rode in on top of the Control press — not a plain tap.
                lastControlOnlyPressAt = nil
            }
            wasControlDown = isControlDown
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor in handleFlagsChanged(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleFlagsChanged(event)
            return event
        }
    }
}
