import AppKit

/// A read-only progress row for the usage right-click menu: title/reset on one line, a rounded
/// track+fill bar, and a percent caption below — drawn directly (like `MenuBarIconRenderer`)
/// rather than composed from Auto Layout subviews, since `NSMenu` just reads a custom item view's
/// fixed frame size instead of laying it out itself.
final class UsageMenuRowView: NSView {
    static let rowSize = NSSize(width: 280, height: 62)
    private static let topPadding: CGFloat = 8

    private let title: String
    private let resetText: String
    private let percent: Double
    private let barColor: NSColor

    init(title: String, resetText: String, percent: Double, barColor: NSColor) {
        self.title = title
        self.resetText = resetText
        self.percent = percent
        self.barColor = barColor
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 14
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor
        ]

        let top = bounds.height - Self.topPadding - 18
        title.draw(at: CGPoint(x: inset, y: top), withAttributes: titleAttrs)

        let resetSize = resetText.size(withAttributes: metaAttrs)
        resetText.draw(at: CGPoint(x: bounds.width - inset - resetSize.width, y: top + 1), withAttributes: metaAttrs)

        let barRect = CGRect(x: inset, y: top - 20, width: bounds.width - inset * 2, height: 5)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 2.5, yRadius: 2.5).fill()

        let fraction = max(0, min(percent / 100, 1))
        if fraction > 0.01 {
            let fillRect = CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width * fraction, height: barRect.height)
            barColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5).fill()
        }

        let caption = "\(Int(percent.rounded()))% used"
        let captionSize = caption.size(withAttributes: metaAttrs)
        caption.draw(at: CGPoint(x: (bounds.width - captionSize.width) / 2, y: barRect.minY - 18), withAttributes: metaAttrs)
    }
}
