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
    /// Whether a failed read is worth backing off and retrying (429, offline) or is a standing
    /// local condition — no credential, or an expired one — that a fast retry can't fix and that
    /// costs nothing to re-check at the normal interval.
    var failureIsTransient: Bool = true

    static let unavailable = UsageSnapshot(percentUsed: 0, windowResetsAt: nil, isAvailable: false)
    /// No usable Claude Code credential on this machine. Distinct from `.unavailable` only in that
    /// the poller won't back off over it: recovery is a Keychain read away once the user logs in.
    static let signedOut = UsageSnapshot(percentUsed: 0, windowResetsAt: nil, isAvailable: false, failureIsTransient: false)

    /// The window driving the menu bar: whichever rate-limit window sits closest to its cap.
    /// Rendering only `five_hour` shows a calm green while the weekly window is nearly spent, and
    /// the user finds out by getting cut off. Extra usage is deliberately excluded — it's a spend
    /// pool rather than a throttle, and the breakdown menu shows it on its own row.
    var headlinePercent: Double { max(percentUsed, weeklyPercentUsed ?? 0) }

    /// The reset date belonging to `headlinePercent`, so the icon's countdown describes the same
    /// window as its percentage.
    var headlineResetsAt: Date? {
        (weeklyPercentUsed ?? 0) > percentUsed ? weeklyResetsAt : windowResetsAt
    }

    /// A reading is only true until the first of its windows rolls over; past that its percentages
    /// describe a window that no longer exists. Matters because the poller holds the last good
    /// figure through a failure streak — without this it would keep showing a pre-reset 90%.
    var isExpired: Bool {
        let now = Date()
        return [windowResetsAt, weeklyResetsAt].compactMap { $0 }.contains { $0 <= now }
    }
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
        usage.isAvailable ? "\(Int(usage.headlinePercent.rounded()))%" : "—"
    }

    /// Empty once the window has passed, rather than clamping to "0h00m" — a countdown reading
    /// zero looks like a live number that just happens to be at the boundary.
    static func resetString(_ usage: UsageSnapshot) -> String {
        guard usage.isAvailable, let reset = usage.headlineResetsAt else { return "" }
        let interval = reset.timeIntervalSinceNow
        guard interval > 0 else { return "" }
        let mins = Int((interval / 60).rounded())
        return String(format: "%dh%02dm", mins / 60, mins % 60)
    }
}
