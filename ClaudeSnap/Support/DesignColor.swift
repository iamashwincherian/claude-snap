import AppKit

/// Fixed palette pulled from the Claude Snap design spec — not theme-dependent.
enum DesignColor {
    static let green = NSColor(srgbHex: 0x3ECF6A)
    static let amber = NSColor(srgbHex: 0xE9A23B)
    static let red = NSColor(srgbHex: 0xE8635A)
    static let clay = NSColor(srgbHex: 0xD97757)
}

extension NSColor {
    convenience init(srgbHex hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
