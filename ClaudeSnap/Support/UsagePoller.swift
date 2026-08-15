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

    private var provider: UsageProvider
    private var timer: Timer?
    private var intervalSeconds: Double
    private var consecutiveFailures = 0

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

    func updateInterval(_ seconds: Double) {
        intervalSeconds = seconds
        scheduleNext()
    }

    func updateProvider(_ provider: UsageProvider) {
        self.provider = provider
        consecutiveFailures = 0
        refresh()
    }

    func refresh() {
        let provider = provider
        Task { [weak self] in
            let result = await provider.fetchUsage()
            self?.apply(result)
        }
    }

    private func apply(_ result: UsageSnapshot) {
        if result.isAvailable {
            consecutiveFailures = 0
            snapshot = result
        } else {
            consecutiveFailures += 1
            // Hold the previous figure through a blip; only admit defeat once it's persistent.
            if consecutiveFailures >= failureTolerance {
                snapshot = .unavailable
            }
        }
        scheduleNext()
    }

    /// One-shot timer re-armed after every fetch, so the delay can grow while failing.
    private func scheduleNext() {
        timer?.invalidate()
        guard intervalSeconds > 0 else { return }
        let delay = consecutiveFailures > 0
            ? min(intervalSeconds * pow(2, Double(consecutiveFailures)), maxBackoffSeconds)
            : intervalSeconds
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
