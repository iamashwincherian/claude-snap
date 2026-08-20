import AppKit

/// Borderless, non-activating panel that can still become key (so the embedded terminal receives
/// keystrokes) without stealing app activation from whatever was frontmost — the same trick
/// Spotlight-style overlays use. Lives at `.statusBar` level so it always draws above normal
/// windows and floats on every Space.
final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none // we drive the reveal/retract ourselves
    }
}
