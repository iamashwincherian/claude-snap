import Foundation
import Security

/// The OAuth object Claude Code CLI stores in Keychain under service "Claude Code-credentials".
/// Field names/shape are reverse-engineered (there's no public spec) and may drift across CLI
/// versions — every caller treats a decode failure as "not logged in" rather than crashing.
struct ClaudeCodeOAuthCredential: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Double?
    let subscriptionType: String?

    /// Claude Code writes epoch milliseconds here; the seconds branch is a cheap hedge in case
    /// that drifts, since the two are ~3000 years apart and can't be confused for one another.
    var expiryDate: Date? {
        guard let expiresAt else { return nil }
        return Date(timeIntervalSince1970: expiresAt > 1e11 ? expiresAt / 1000 : expiresAt)
    }

    /// Treated as unusable rather than optimistically sent: an expired token earns a 401, which is
    /// indistinguishable from a rate limit at the HTTP layer and would trigger pointless backoff.
    var isExpired: Bool {
        guard let expiryDate else { return false }
        return expiryDate <= Date()
    }
}

private struct ClaudeCodeCredentialFile: Decodable {
    let claudeAiOauth: ClaudeCodeOAuthCredential
}

enum ClaudeCodeCredentialStore {
    private static let service = "Claude Code-credentials"

    static func readCredential() -> ClaudeCodeOAuthCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }

        if let wrapped = try? JSONDecoder().decode(ClaudeCodeCredentialFile.self, from: data) {
            return wrapped.claudeAiOauth
        }
        return try? JSONDecoder().decode(ClaudeCodeOAuthCredential.self, from: data)
    }
}
