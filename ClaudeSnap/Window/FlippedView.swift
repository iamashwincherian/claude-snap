import AppKit

/// Top-left-origin, y-down coordinate space — matches the design mock's CSS/SVG geometry, so the
/// menu bar icon and panel math can be ported over without sign-flipping everything.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
