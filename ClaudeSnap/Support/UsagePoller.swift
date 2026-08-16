import Foundation
import Combine

/// Polls a `UsageProvider` on a configurable interval and republishes the latest snapshot.
/// A parse/network failure in the provider surfaces as `.unavailable`, never a crash.
///
/// Failures are treated as transient first: the usage endpoint is unofficial and does hand back
/// 429s (and any laptop goes offline), so a single bad fetch keeps showing the last good number
/// and backs the polling off rather than blanking the display and retrying straight into the
/// rate limit.
@MainActor
final class UsagePoller: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .unavailable

    private let provider: UsageProvider
    private var timer: Timer?
    private let intervalSeconds: Double
    private var consecutiveFailures = 0
    private var isFetching = false
    private var lastFetchStartedAt: Date?

    /// Failures tolerated before the last good reading is replaced with "unavailable".
    private let failureTolerance = 3
    private let maxBackoffSeconds: Double = 600

    init(provider: UsageProvider, intervalSeconds: Double = 60) {
        self.provider = provider
        self.intervalSeconds = intervalSeconds
    }

    func start() {
        refresh()
    }

    /// Refresh prompted by the user showing up — waking the Mac, opening the dropdown, opening the
    /// menu — rather than by the timer. Coalesced against the poll interval because the endpoint is
    /// rate limited and these triggers can fire in bursts; a reading that recent is good enough.
    func refreshIfStale() {
        if let last = lastFetchStartedAt, Date().timeIntervalSince(last) < intervalSeconds { return }
        refresh()
    }

    func refresh() {
        guard !isFetching else { return }
        isFetching = true
        lastFetchStartedAt = Date()
        let provider = provider
        Task { [weak self] in
            let result = await provider.fetchUsage()
            self?.apply(result)
        }
    }

    private func apply(_ result: UsageSnapshot) {
        isFetching = false
        if result.isAvailable {
            consecutiveFailures = 0
            snapshot = result
        } else if !result.failureIsTransient {
            // Nothing to back off from — there's no credential to use. Keep checking at the normal
            // interval so a fresh login is picked up promptly.
            consecutiveFailures = 0
            snapshot = .unavailable
        } else {
            consecutiveFailures += 1
            // Hold the previous figure through a blip; only admit defeat once it's persistent — or
            // as soon as the window it describes has rolled over, since a pre-reset percentage is
            // worse than no percentage at all.
            if consecutiveFailures >= failureTolerance || snapshot.isExpired {
                snapshot = .unavailable
            }
        }
        scheduleNext()
    }

    /// One-shot timer re-armed after every fetch, so the delay can grow while failing.
    private func scheduleNext() {
        timer?.invalidate()
        guard intervalSeconds > 0 else { return }
        // First retry waits one plain interval; doubling starts only after that, so a single blip
        // doesn't cost minutes of staleness before the display is corrected.
        let delay = consecutiveFailures > 0
            ? min(intervalSeconds * pow(2, Double(consecutiveFailures - 1)), maxBackoffSeconds)
            : intervalSeconds
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // `.common` so polling doesn't stall while a menu is tracking or a scroll is in flight.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
