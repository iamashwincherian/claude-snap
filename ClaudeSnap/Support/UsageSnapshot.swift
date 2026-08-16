import AppKit

/// A point-in-time read of the current 5-hour Claude Code session, as produced by a `UsageProvider`.
struct UsageSnapshot: Equatable {
    var percentUsed: Double
    var windowResetsAt: Date?
    var isAvailable: Bool

    static let unavailable = UsageSnapshot(percentUsed: 0, windowResetsAt: nil, isAvailable: false)
}

struct UsageThresholds: Equatable {
    var amber: Double = 60
    var red: Double = 85
}

enum UsageLevel {
    case green, amber, red

    static func level(for percent: Double, thresholds: UsageThresholds) -> UsageLevel {
        if percent >= thresholds.red { return .red }
        if percent >= thresholds.amber { return .amber }
        return .green
    }

    var nsColor: NSColor {
        switch self {
        case .green: return DesignColor.green
        case .amber: return DesignColor.amber
        case .red: return DesignColor.red
        }
    }
}

enum UsageFormat {
    static func percentString(_ usage: UsageSnapshot) -> String {
        usage.isAvailable ? "\(Int(usage.percentUsed.rounded()))%" : "—"
    }

    static func resetString(_ usage: UsageSnapshot) -> String {
        guard usage.isAvailable, let reset = usage.windowResetsAt else { return "" }
        let interval = max(0, reset.timeIntervalSinceNow)
        let mins = Int((interval / 60).rounded())
        return String(format: "%dh%02dm", mins / 60, mins % 60)
    }
}
