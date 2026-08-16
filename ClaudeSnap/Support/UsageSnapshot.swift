import AppKit

/// A point-in-time read of Claude's rate-limit windows, as produced by a `UsageProvider`. The
/// 5-hour session figures are the ones the menu bar icon/text render; weekly and extra usage ride
/// along on the same poll (the API returns all three in one response) purely for the right-click
/// menu's usage breakdown.
struct UsageSnapshot: Equatable {
    var percentUsed: Double
    var windowResetsAt: Date?
    var isAvailable: Bool
    var weeklyPercentUsed: Double?
    var weeklyResetsAt: Date?
    var extraUsage: ExtraUsageSnapshot?

    static let unavailable = UsageSnapshot(percentUsed: 0, windowResetsAt: nil, isAvailable: false)
}

/// Only populated when the account has pay-as-you-go extra usage enabled — most don't, so this is
/// nil far more often than not. No reset date: the API doesn't supply one for this window (it's
/// monthly, unlike the two rate-limit windows), so the menu computes "1st of next month" itself.
struct ExtraUsageSnapshot: Equatable {
    var percentUsed: Double
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
