import AppKit

/// A thin invisible strip pinned to the card's bottom edge for dragging the panel taller/shorter.
/// Dumb by design (see `StatusBarController`'s callback closures for the same pattern) — it only
/// says "a drag happened", leaving the height math to `DropdownWindowController`.
final class ResizeHandleView: NSView {
    static let thickness: CGFloat = 8

    var onDrag: (() -> Void)?

    /// The panel is non-activating, so a click can arrive while another app is frontmost. Without
    /// this the first click is swallowed just to focus us, and the drag never starts.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// AppKit routes mouseDragged to the view that *handled* mouseDown. NSView's default passes it
    /// up the responder chain, so an empty override here is what claims the whole drag sequence.
    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        onDrag?()
    }

    // SwiftTerm covers the card with an I-beam tracking area, and tracking-area cursor updates win
    // over cursor rects — so match it with our own tracking area instead of `resetCursorRects`.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }
}
