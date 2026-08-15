import AppKit

/// 23pt strip at the bottom of the terminal panel, segments separated by a hairline, left to
/// right in whatever order `StatusLineController` hands over.
final class StatusLineView: FlippedView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor

        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ values: [StatusLineSegmentValue]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for value in values {
            stack.addArrangedSubview(SegmentChipView(value: value))
        }
    }
}

private final class SegmentChipView: NSView {
    init(value: StatusLineSegmentValue) {
        super.init(frame: .zero)

        let icon = NSTextField(labelWithString: value.icon)
        icon.font = .systemFont(ofSize: 10.5)
        icon.textColor = value.iconColor

        let text = NSTextField(labelWithString: value.text)
        text.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        text.textColor = value.textColor

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)
        addSubview(divider)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: divider.leadingAnchor),

            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 0.5),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
