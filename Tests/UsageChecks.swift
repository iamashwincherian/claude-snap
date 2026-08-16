import Foundation

/// Self-check for the usage/limit logic — the branchy parts that decide what number the menu bar
/// shows. Compiled directly against the source files rather than through an XCTest bundle; see the
/// run command in CLAUDE.md ▸ Testing.
///
/// ponytail: asserts + a fake provider, no framework. Move to XCTest if this ever needs fixtures
/// or more than one file's worth of cases.

private func check(_ condition: Bool, _ label: String) {
    guard condition else {
        FileHandle.standardError.write(Data("FAIL: \(label)\n".utf8))
        exit(1)
    }
    print("ok  \(label)")
}

private struct ScriptedProvider: UsageProvider {
    let results: [UsageSnapshot]
    private let cursor = Cursor()

    final class Cursor: @unchecked Sendable {
        var index = 0
    }

    func fetchUsage() async -> UsageSnapshot {
        let result = results[min(cursor.index, results.count - 1)]
        cursor.index += 1
        return result
    }
}

private func available(session: Double, weekly: Double? = nil, resetsIn: TimeInterval = 3600) -> UsageSnapshot {
    UsageSnapshot(
        percentUsed: session,
        windowResetsAt: Date().addingTimeInterval(resetsIn),
        isAvailable: true,
        weeklyPercentUsed: weekly,
        weeklyResetsAt: weekly.map { _ in Date().addingTimeInterval(resetsIn * 10) }
    )
}

@main
enum UsageChecks {
    @MainActor
    static func main() async {
        headlineWindow()
        expiry()
        formatting()
        await pollerHoldsThroughBlips()
        await pollerDropsExpiredHeldReading()
        await pollerDoesNotBackOffWhenSignedOut()
        print("\nall checks passed")
    }

    /// The menu bar must reflect whichever window is closest to its cap, not always the 5-hour one.
    static func headlineWindow() {
        let weeklyWorse = available(session: 8, weekly: 97)
        check(weeklyWorse.headlinePercent == 97, "headline follows the weekly window when it's worse")
        check(weeklyWorse.headlineResetsAt == weeklyWorse.weeklyResetsAt, "headline reset date follows the headline window")

        let sessionWorse = available(session: 91, weekly: 12)
        check(sessionWorse.headlinePercent == 91, "headline follows the session window when it's worse")
        check(sessionWorse.headlineResetsAt == sessionWorse.windowResetsAt, "session reset date used when session leads")

        check(available(session: 40).headlinePercent == 40, "headline falls back to session when weekly is absent")
    }

    static func expiry() {
        check(!available(session: 50, resetsIn: 600).isExpired, "a live window is not expired")
        check(available(session: 50, resetsIn: -1).isExpired, "a passed session window marks the reading expired")

        var weeklyGone = available(session: 50, weekly: 20)
        weeklyGone.weeklyResetsAt = Date().addingTimeInterval(-1)
        check(weeklyGone.isExpired, "a passed weekly window marks the reading expired")
    }

    static func formatting() {
        check(UsageFormat.resetString(available(session: 10, resetsIn: -60)).isEmpty, "expired window prints no countdown")
        check(UsageFormat.resetString(available(session: 10, resetsIn: 5400)) == "1h30m", "live window prints a countdown")
        check(UsageFormat.percentString(available(session: 8, weekly: 97)) == "97%", "percent string reports the headline window")
        check(UsageFormat.percentString(.unavailable) == "—", "unavailable prints a dash")
    }

    /// A single 429 should not blank a good reading, but three in a row should.
    @MainActor
    static func pollerHoldsThroughBlips() async {
        let poller = UsagePoller(
            provider: ScriptedProvider(results: [available(session: 42), .unavailable]),
            intervalSeconds: 3600
        )
        await settle(poller)
        check(poller.snapshot.percentUsed == 42, "first successful poll is published")

        await settle(poller)
        check(poller.snapshot.percentUsed == 42, "one failure holds the last good reading")
        await settle(poller)
        check(poller.snapshot.percentUsed == 42, "two failures still hold")
        await settle(poller)
        check(!poller.snapshot.isAvailable, "three failures give up and report unavailable")
    }

    /// The regression that motivated `isExpired`: holding a pre-reset percentage past its window.
    @MainActor
    static func pollerDropsExpiredHeldReading() async {
        let poller = UsagePoller(
            provider: ScriptedProvider(results: [available(session: 93, resetsIn: 1), .unavailable]),
            intervalSeconds: 3600
        )
        await settle(poller)
        check(poller.snapshot.percentUsed == 93, "reading published while its window is live")

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await settle(poller)
        check(!poller.snapshot.isAvailable, "held reading is dropped as soon as its window has reset")
    }

    /// No credential is a standing condition, not a blip — it should surface immediately.
    @MainActor
    static func pollerDoesNotBackOffWhenSignedOut() async {
        let poller = UsagePoller(
            provider: ScriptedProvider(results: [available(session: 30), .signedOut]),
            intervalSeconds: 3600
        )
        await settle(poller)
        check(poller.snapshot.percentUsed == 30, "reading published before sign-out")

        await settle(poller)
        check(!poller.snapshot.isAvailable, "signed out reports unavailable without a 3-failure grace period")
    }

    @MainActor
    static func settle(_ poller: UsagePoller) async {
        poller.refresh()
        try? await Task.sleep(nanoseconds: 80_000_000)
    }
}
