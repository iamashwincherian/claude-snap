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

    /// The bare mark with no ring/arc/dot — the same glyph drawn for the `.glyph` icon style's
    /// idle state, reused wherever the app's mark needs to appear standalone (e.g. the terminal's
    /// own status line).
    static func markImage(color: NSColor) -> NSImage {
        let size = NSSize(width: canvasSize, height: canvasSize)
        let image = NSImage(size: size, flipped: true) { _ in
            drawMark(glyphSpokes, color: color)
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
        case .glyph, .text, .full:
            drawMark(glyphSpokes, color: glyphColor)
            if usage.isWorking {
                drawWorkingDot()
            }
        case .ring:
            guard usage.isAvailable else {
                drawMark(glyphSpokes, color: glyphColor)
                return
            }
            let trackColor = neutral(0.26, isLight: isLightMenuBar, lightOverride: 0.22)
            drawRingTrack(color: trackColor, strokeWidth: strokeWidth)
            drawArc(usage: usage, strokeWidth: strokeWidth)
            drawMark(coreSpokes, color: glyphColor)
        }
    }

    private static func neutral(_ darkOpacity: CGFloat, isLight: Bool, lightOverride: CGFloat? = nil) -> NSColor {
        isLight ? NSColor.black.withAlphaComponent(lightOverride ?? darkOpacity) : NSColor.white.withAlphaComponent(darkOpacity)
    }

    /// One radial wedge of the mark: `M a  L b  Q control d  L e  Z` in the design's SVG path
    /// terms — a filled quad from the hub (`a`/`e`) out to the tip (`b`/`d`), rounded off by a
    /// quadratic curve through `control`.
    private struct Spoke {
        let a: CGPoint, b: CGPoint, control: CGPoint, d: CGPoint, e: CGPoint
    }

    /// The seven-spoke "half burst, even" mark from the design system, fit to different targets:
    /// `glyphSpokes` fills the full 18×18 canvas (0.7pt inset) for the standalone glyph and the
    /// no-ring fallback; `coreSpokes` fits inside the r=5.5 circle at the ring's center. Both are
    /// `spoke(i·30°, rIn: 1.5, rOut: 11.2, wIn: 1.02, wOut: 0.56, cy: 6.4)` for i in 0..<7, pre-fit
    /// (bbox scale + translate) by the design's `fitBox`/`fitCircle` helpers — baked in here since
    /// the geometry never changes at runtime.
    private static let rawGlyphSpokes: [Spoke] = [
        Spoke(a: CGPoint(x: 10.0512, y: 5.9222), b: CGPoint(x: 16.8487, y: 5.5998), control: CGPoint(x: 17.3000, y: 5.2074), d: CGPoint(x: 16.8487, y: 4.8150), e: CGPoint(x: 10.0512, y: 4.4926)),
        Spoke(a: CGPoint(x: 9.5529, y: 6.3520), b: CGPoint(x: 15.6010, y: 9.4716), control: CGPoint(x: 16.1880, y: 9.3574), d: CGPoint(x: 15.9934, y: 8.7919), e: CGPoint(x: 10.2677, y: 5.1140)),
        Spoke(a: CGPoint(x: 8.9066, y: 6.4751), b: CGPoint(x: 12.5845, y: 12.2008), control: CGPoint(x: 13.1500, y: 12.3954), d: CGPoint(x: 13.2642, y: 11.8084), e: CGPoint(x: 10.1446, y: 5.7603)),
        Spoke(a: CGPoint(x: 8.2852, y: 6.2586), b: CGPoint(x: 8.6076, y: 13.0561), control: CGPoint(x: 9.0000, y: 13.5074), d: CGPoint(x: 9.3924, y: 13.0561), e: CGPoint(x: 9.7148, y: 6.2586)),
        Spoke(a: CGPoint(x: 7.8554, y: 5.7603), b: CGPoint(x: 4.7358, y: 11.8084), control: CGPoint(x: 4.8500, y: 12.3954), d: CGPoint(x: 5.4155, y: 12.2008), e: CGPoint(x: 9.0934, y: 6.4751)),
        Spoke(a: CGPoint(x: 7.7323, y: 5.1140), b: CGPoint(x: 2.0066, y: 8.7919), control: CGPoint(x: 1.8120, y: 9.3574), d: CGPoint(x: 2.3990, y: 9.4716), e: CGPoint(x: 8.4471, y: 6.3520)),
        Spoke(a: CGPoint(x: 7.9488, y: 4.4926), b: CGPoint(x: 1.1513, y: 4.8150), control: CGPoint(x: 0.7000, y: 5.2074), d: CGPoint(x: 1.1513, y: 5.5998), e: CGPoint(x: 7.9488, y: 5.9222)),
    ]

    /// The design's baked coordinates only span the middle ~half of the 18pt canvas vertically
    /// (y≈4.49–13.51), leaving the mark looking small/off wherever it's placed next to other
    /// content. Scale up (uniformly, x and y together, so the aspect ratio is preserved) so the
    /// mark's bounding box fills most of the canvas height, instead of papering over it with
    /// container-level centering.
    private static let glyphSpokes: [Spoke] = scaleToFillHeight(rawGlyphSpokes, canvas: canvasSize, fillFraction: 0.65)

    private static func scaleToFillHeight(_ spokes: [Spoke], canvas: CGFloat, fillFraction: CGFloat) -> [Spoke] {
        let xs = spokes.flatMap { [$0.a.x, $0.b.x, $0.control.x, $0.d.x, $0.e.x] }
        let ys = spokes.flatMap { [$0.a.y, $0.b.y, $0.control.y, $0.d.y, $0.e.y] }
        let midX = (xs.min()! + xs.max()!) / 2
        let midY = (ys.min()! + ys.max()!) / 2
        let scale = canvas * fillFraction / (ys.max()! - ys.min()!)
        func apply(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - midX) * scale + canvas / 2, y: (p.y - midY) * scale + canvas / 2) }
        return spokes.map { Spoke(a: apply($0.a), b: apply($0.b), control: apply($0.control), d: apply($0.d), e: apply($0.e)) }
    }

    private static let coreSpokes: [Spoke] = [
        Spoke(a: CGPoint(x: 9.6121, y: 7.2077), b: CGPoint(x: 13.5705, y: 7.0200), control: CGPoint(x: 13.8333, y: 6.7915), d: CGPoint(x: 13.5705, y: 6.5630), e: CGPoint(x: 9.6121, y: 6.3752)),
        Spoke(a: CGPoint(x: 9.3220, y: 7.4580), b: CGPoint(x: 12.8439, y: 9.2746), control: CGPoint(x: 13.1857, y: 9.2081), d: CGPoint(x: 13.0724, y: 8.8788), e: CGPoint(x: 9.7382, y: 6.7371)),
        Spoke(a: CGPoint(x: 8.9456, y: 7.5297), b: CGPoint(x: 11.0873, y: 10.8639), control: CGPoint(x: 11.4166, y: 10.9772), d: CGPoint(x: 11.4831, y: 10.6354), e: CGPoint(x: 9.6665, y: 7.1135)),
        Spoke(a: CGPoint(x: 8.5838, y: 7.4036), b: CGPoint(x: 8.7715, y: 11.3620), control: CGPoint(x: 9.0000, y: 11.6248), d: CGPoint(x: 9.2285, y: 11.3620), e: CGPoint(x: 9.4162, y: 7.4036)),
        Spoke(a: CGPoint(x: 8.3335, y: 7.1135), b: CGPoint(x: 6.5169, y: 10.6354), control: CGPoint(x: 6.5834, y: 10.9772), d: CGPoint(x: 6.9127, y: 10.8639), e: CGPoint(x: 9.0544, y: 7.5297)),
        Spoke(a: CGPoint(x: 8.2618, y: 6.7371), b: CGPoint(x: 4.9276, y: 8.8788), control: CGPoint(x: 4.8143, y: 9.2081), d: CGPoint(x: 5.1561, y: 9.2746), e: CGPoint(x: 8.6780, y: 7.4580)),
        Spoke(a: CGPoint(x: 8.3879, y: 6.3752), b: CGPoint(x: 4.4295, y: 6.5630), control: CGPoint(x: 4.1667, y: 6.7915), d: CGPoint(x: 4.4295, y: 7.0200), e: CGPoint(x: 8.3879, y: 7.2077)),
    ]

    private static func drawMark(_ spokes: [Spoke], color: NSColor) {
        let path = NSBezierPath()
        for spoke in spokes {
            path.move(to: spoke.a)
            path.line(to: spoke.b)
            // NSBezierPath only curves cubically; convert the design's quadratic control point
            // to the equivalent cubic pair (standard 2/3-along-the-tangent construction).
            let c1 = CGPoint(x: spoke.b.x + (spoke.control.x - spoke.b.x) * 2 / 3, y: spoke.b.y + (spoke.control.y - spoke.b.y) * 2 / 3)
            let c2 = CGPoint(x: spoke.d.x + (spoke.control.x - spoke.d.x) * 2 / 3, y: spoke.d.y + (spoke.control.y - spoke.d.y) * 2 / 3)
            path.curve(to: spoke.d, controlPoint1: c1, controlPoint2: c2)
            path.line(to: spoke.e)
            path.close()
        }
        color.setFill()
        path.fill()
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
