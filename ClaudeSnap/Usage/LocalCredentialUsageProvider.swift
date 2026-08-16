import Foundation

/// Reads Claude Code's own OAuth token from Keychain and queries Anthropic's rate-limit endpoint
/// for the current 5-hour session usage — the same underlying limit Claude Code's own `statusLine`
/// hook reports via `rate_limits.five_hour`, though that hook JSON and this HTTP response use
/// different shapes/field names for it (see `RateLimitResponse`).
///
/// There is no official public API for this; the endpoint below is unofficial and reverse
/// engineered, so it can change or disappear without notice. Every step degrades to
/// `.unavailable` instead of throwing — verify this against real network traffic (e.g. a proxy
/// while running `claude`) before shipping, and swap it out here if Anthropic ever ships an
/// official endpoint. That's the whole reason this sits behind `UsageProvider`.
struct LocalCredentialUsageProvider: UsageProvider {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage() async -> UsageSnapshot {
        guard let token = ClaudeCodeCredentialStore.readAccessToken() else { return .unavailable }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            // 429 shows up here in normal use (the endpoint is unofficial and rate limited);
            // `UsagePoller` treats the resulting `.unavailable` as transient and backs off.
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unavailable
            }
            return parse(data) ?? .unavailable
        } catch {
            return .unavailable
        }
    }

    private func parse(_ data: Data) -> UsageSnapshot? {
        guard let decoded = try? JSONDecoder().decode(RateLimitResponse.self, from: data),
              let window = decoded.fiveHour,
              let percent = window.utilization else { return nil }

        let resetDate = window.resetsAt.flatMap(Self.parseResetDate)
        return UsageSnapshot(percentUsed: percent, windowResetsAt: resetDate, isAvailable: true)
    }

    private static func parseResetDate(_ string: String) -> Date? {
        fractionalISO8601.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Reverse-engineered shape as of 2026-08 — flat, not wrapped in `rate_limits`, and `resets_at` is
/// an ISO8601 string, not the epoch-seconds number Claude Code's own `statusLine` hook JSON uses
/// for the same field name. This has already drifted once; see the type-level doc comment.
private struct RateLimitResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
    let fiveHour: Window?
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
    }
}
