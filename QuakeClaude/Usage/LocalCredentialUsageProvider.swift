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
        // No credential, or a stale one, is a standing local condition rather than a blip — say so
        // so the poller doesn't back off exponentially over something a login fixes instantly.
        guard let credential = ClaudeCodeCredentialStore.readCredential(), !credential.isExpired else {
            return .signedOut
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
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
              let percent = window.utilization,
              Self.isPlausiblePercent(percent) else { return nil }

        let extra: ExtraUsageSnapshot? = (decoded.extraUsage?.isEnabled == true)
            ? decoded.extraUsage?.utilization.flatMap(Self.validPercent).map(ExtraUsageSnapshot.init(percentUsed:))
            : nil

        return UsageSnapshot(
            percentUsed: percent,
            windowResetsAt: window.resetsAt.flatMap(Self.parseResetDate),
            isAvailable: true,
            weeklyPercentUsed: decoded.sevenDay?.utilization.flatMap(Self.validPercent),
            weeklyResetsAt: decoded.sevenDay?.resetsAt.flatMap(Self.parseResetDate),
            extraUsage: extra
        )
    }

    /// `utilization` is documented-by-observation as 0–100. Rejecting anything else keeps garbage
    /// (NaN, absurd magnitudes) out of `Int(_:rounded())` conversions downstream, which trap.
    ///
    /// ponytail: can't catch a silent switch to a 0–1 fraction — 0.87 is a legal percentage — so a
    /// rescale would still render as "1%". Detecting that needs a second signal (e.g. cross-checking
    /// the statusLine hook's `rate_limits`); add it only if the endpoint actually drifts that way.
    private static func isPlausiblePercent(_ value: Double) -> Bool {
        value.isFinite && (0...100).contains(value)
    }

    private static func validPercent(_ value: Double) -> Double? {
        isPlausiblePercent(value) ? value : nil
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
    /// Dollar fields (`used_credits`, `monthly_limit`) are deliberately not decoded: their scale
    /// (`decimal_places`) is unverified against a real enabled account, and showing a wrong dollar
    /// figure is worse than not showing one — `utilization` is an unambiguous 0–100 either way.
    struct ExtraUsage: Decodable {
        let isEnabled: Bool?
        let utilization: Double?
        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case utilization
        }
    }
    let fiveHour: Window?
    let sevenDay: Window?
    let extraUsage: ExtraUsage?
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
    }
}
