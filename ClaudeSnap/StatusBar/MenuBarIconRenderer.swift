import AppKit

/// Draws the live menu bar glyph: 18×18pt canvas, 14pt-diameter ring (r=7, 2pt stroke, round cap),
/// arc starting at 12 o'clock and sweeping clockwise. Geometry mirrors the design spec's `arc(p)`
/// function exactly (sampled polyline instead of a single SVG arc command, since we don't need to
/// dodge the "can't draw an exact 360° arc with one `A` command" workaround the web mock uses).
enum MenuBarIconRenderer {
    static let canvasSize: CGFloat = 18
    private static let center = CGPoint(x: 9, y: 9)
    private static let radius: CGFloat = 7

    static func image(usage: UsageSnapshot, style: MenuBarIconStyle, isLightMenuBar: Bool, strokeWidth: CGFloat = 2) -> NSImage {
        let size = NSSize(width: canvasSize, height: canvasSize)
        let image = NSImage(size: size, flipped: true) { rect in
            drawIcon(in: rect, usage: usage, style: style, isLightMenuBar: isLightMenuBar, strokeWidth: strokeWidth)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Drawing

    private static func drawIcon(in rect: NSRect, usage: UsageSnapshot, style: MenuBarIconStyle, isLightMenuBar: Bool, strokeWidth: CGFloat) {
        let nearLimit = usage.isAvailable && usage.percentUsed >= 100
        let glyphColor = neutral(nearLimit ? 0.45 : 0.9, isLight: isLightMenuBar)

        switch style {
        case .glyph:
            drawChevron(color: glyphColor)
            if usage.isWorking {
                drawWorkingDot()
            }
        case .ring, .text, .full:
            guard usage.isAvailable else {
                drawChevron(color: glyphColor)
                return
            }
            let trackColor = neutral(0.26, isLight: isLightMenuBar, lightOverride: 0.22)
            drawRingTrack(color: trackColor, strokeWidth: strokeWidth)
            drawArc(usage: usage, strokeWidth: strokeWidth)
            drawChevron(color: glyphColor)
        }
    }

    private static func neutral(_ darkOpacity: CGFloat, isLight: Bool, lightOverride: CGFloat? = nil) -> NSColor {
        isLight ? NSColor.black.withAlphaComponent(lightOverride ?? darkOpacity) : NSColor.white.withAlphaComponent(darkOpacity)
    }

    private static func drawChevron(color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: CGPoint(x: 6.3, y: 7.7))
        path.line(to: CGPoint(x: 9, y: 10.4))
        path.line(to: CGPoint(x: 11.7, y: 7.7))
        color.setStroke()
        path.stroke()
    }

    private static func drawWorkingDot() {
        // 5pt clay dot, top-right of the glyph. Breathing/pulse animation (1.4s) is applied by the
        // status item host swapping this image on a short timer — see StatusBarController.
        let dotRect = CGRect(x: 12.6, y: 3.0, width: 5, height: 5)
        DesignColor.clay.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private static func drawRingTrack(color: NSColor, strokeWidth: CGFloat) {
        let ovalRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: ovalRect)
        path.lineWidth = strokeWidth
        color.setStroke()
        path.stroke()
    }

    private static func drawArc(usage: UsageSnapshot, strokeWidth: CGFloat) {
        let points = arcPoints(percent: usage.percentUsed)
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        let level = UsageLevel.level(for: usage.percentUsed, thresholds: UsageThresholds())
        level.nsColor.setStroke()
        path.stroke()
    }

    /// Sampled points along the ring from 12 o'clock, clockwise, for `percent` of a full turn.
    /// Coordinate space matches the design's flipped (y-down) SVG viewBox.
    static func arcPoints(percent: Double) -> [CGPoint] {
        let fraction = max(0, min(percent, 100)) / 100
        guard fraction > 0.005 else { return [] }
        let startDeg = -90.0
        let endDeg = startDeg + 360.0 * fraction
        let steps = max(2, Int(((endDeg - startDeg) / 2.0).rounded(.up)))
        return (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let deg = startDeg + (endDeg - startDeg) * t
            let rad = deg * .pi / 180
            return CGPoint(x: center.x + radius * cos(rad), y: center.y + radius * sin(rad))
        }
    }
}
