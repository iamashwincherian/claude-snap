import Foundation

/// Source of truth for "how much of the current 5-hour session has been used". There is no
/// official Anthropic usage API, so implementations read local Claude Code state (Keychain /
/// session files) today. The protocol exists so a future official API can be swapped in without
/// touching anything that consumes `UsagePoller`.
protocol UsageProvider {
    func fetchUsage() async -> UsageSnapshot
}

/// Returns `.unavailable` unconditionally. Used until a real provider is wired up, and as the
/// safe fallback a real provider should degrade to on parse failure.
struct UnavailableUsageProvider: UsageProvider {
    func fetchUsage() async -> UsageSnapshot { .unavailable }
}
