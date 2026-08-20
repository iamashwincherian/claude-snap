import AppKit

/// Draws the live menu bar glyph: 18×18pt canvas, 14pt-diameter ring (r=7, 2pt stroke, round cap),
/// arc starting at 12 o'clock and sweeping clockwise. Geometry mirrors the design spec's `arc(p)`
/// function exactly (sampled polyline instead of a single SVG arc command, since we don't need to
/// dodge the "can't draw an exact 360° arc with one `A` command" workaround the web mock uses).
enum MenuBarIconRenderer {
    static let canvasSize: CGFloat = 18
    private static let center = CGPoint(x: 9, y: 9)
    private static let radius: CGFloat = 7

    static func image(usage: UsageSnapshot, style: MenuBarIconStyle, thresholds: UsageThresholds, isLightMenuBar: Bool, strokeWidth: CGFloat = 2) -> NSImage {
        let size = NSSize(width: canvasSize, height: canvasSize)
        let image = NSImage(size: size, flipped: true) { rect in
            drawIcon(in: rect, usage: usage, style: style, thresholds: thresholds, isLightMenuBar: isLightMenuBar, strokeWidth: strokeWidth)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The bare mark with no ring/arc/dot — the same glyph drawn for the `.glyph` icon style's
    /// idle state, reused wherever the app's mark needs to appear standalone (e.g. the terminal's
    /// own status line).
    static func markImage(color: NSColor) -> NSImage {
        let size = NSSize(width: canvasSize, height: canvasSize)
        let image = NSImage(size: size, flipped: true) { _ in
            drawPixelCat(color: color, fillFraction: 0.85)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Drawing

    private static func drawIcon(in rect: NSRect, usage: UsageSnapshot, style: MenuBarIconStyle, thresholds: UsageThresholds, isLightMenuBar: Bool, strokeWidth: CGFloat) {
        let nearLimit = usage.isAvailable && usage.headlinePercent >= 100
        let glyphColor = DesignColor.clay.withAlphaComponent(nearLimit ? 0.45 : 1)

        switch style {
        case .glyph, .text, .full:
            drawPixelCat(color: glyphColor, fillFraction: 0.85)
        case .ring:
            if usage.isAvailable {
                let trackColor = neutral(0.26, isLight: isLightMenuBar, lightOverride: 0.22)
                drawRingTrack(color: trackColor, strokeWidth: strokeWidth)
                drawArc(usage: usage, thresholds: thresholds, strokeWidth: strokeWidth)
                drawPixelCat(color: glyphColor, fillFraction: 0.55)
            } else {
                drawPixelCat(color: glyphColor, fillFraction: 0.85)
            }
        }
    }

    /// Just the amber dot, sized to sit as a text attachment at the end of the status item's title
    /// (trailing the percentage) rather than overlaid on the glyph, whose spokes span nearly the
    /// whole canvas and leave nowhere for a badge. Generous leading padding keeps it visually
    /// separate from the percentage text. `pulseOn` blanks the draw — but not the size — every
    /// other tick, giving a breathing effect without the item's width jumping as the host swaps it.
    static let workingDotSize = NSSize(width: 16, height: 9)

    static func workingIndicatorImage(pulseOn: Bool) -> NSImage {
        let image = NSImage(size: workingDotSize, flipped: false) { rect in
            guard !pulseOn else { return true }
            let diameter: CGFloat = 7
            let dotRect = CGRect(x: rect.maxX - diameter, y: rect.midY - diameter / 2, width: diameter, height: diameter)
            DesignColor.amber.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func neutral(_ darkOpacity: CGFloat, isLight: Bool, lightOverride: CGFloat? = nil) -> NSColor {
        isLight ? NSColor.black.withAlphaComponent(lightOverride ?? darkOpacity) : NSColor.white.withAlphaComponent(darkOpacity)
    }

    /// One filled block of the pixel-creature mark, in grid units (not points) — `x`/`y` are the
    /// block's top-left corner, `w`/`h` its span, all taken straight from the OCTOPUS glyph's
    /// `grid-area` cells in the "Pixel Creatures" design (10×9 grid, negative-space eyes).
    private struct GridBlock {
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    }

    private static let creatureCells: [GridBlock] = [
        GridBlock(x: 1, y: 0, w: 8, h: 2),
        GridBlock(x: 0, y: 2, w: 2, h: 1),
        GridBlock(x: 3, y: 2, w: 4, h: 1),
        GridBlock(x: 8, y: 2, w: 2, h: 1),
        GridBlock(x: 0, y: 3, w: 10, h: 1),
        GridBlock(x: 1, y: 4, w: 8, h: 2),
        GridBlock(x: 1, y: 6, w: 1, h: 1),
        GridBlock(x: 3, y: 6, w: 1, h: 1),
        GridBlock(x: 6, y: 6, w: 1, h: 1),
        GridBlock(x: 8, y: 6, w: 1, h: 1),
        GridBlock(x: 3, y: 7, w: 1, h: 1),
        GridBlock(x: 6, y: 7, w: 1, h: 1),
    ]

    /// Renders `creatureCells` uniformly scaled (aspect preserved) so its bounding box fills
    /// `fillFraction` of the canvas, centered — same fit strategy the old spoke mark used, just
    /// against a block grid instead of bezier wedges.
    private static func drawPixelCat(color: NSColor, fillFraction: CGFloat) {
        let minX = creatureCells.map(\.x).min()!
        let minY = creatureCells.map(\.y).min()!
        let maxX = creatureCells.map { $0.x + $0.w }.max()!
        let maxY = creatureCells.map { $0.y + $0.h }.max()!
        let scale = canvasSize * fillFraction / max(maxX - minX, maxY - minY)
        let offsetX = (canvasSize - (maxX - minX) * scale) / 2
        let offsetY = (canvasSize - (maxY - minY) * scale) / 2

        let path = NSBezierPath()
        for cell in creatureCells {
            path.appendRect(CGRect(
                x: offsetX + (cell.x - minX) * scale, y: offsetY + (cell.y - minY) * scale,
                width: cell.w * scale, height: cell.h * scale
            ))
        }
        color.setFill()
        path.fill()
    }

    private static func drawRingTrack(color: NSColor, strokeWidth: CGFloat) {
        let ovalRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: ovalRect)
        path.lineWidth = strokeWidth
        color.setStroke()
        path.stroke()
    }

    private static func drawArc(usage: UsageSnapshot, thresholds: UsageThresholds, strokeWidth: CGFloat) {
        let points = arcPoints(percent: usage.headlinePercent)
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        let level = UsageLevel.level(for: usage.headlinePercent, thresholds: thresholds)
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
