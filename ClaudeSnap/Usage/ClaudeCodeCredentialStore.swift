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
}

private struct ClaudeCodeCredentialFile: Decodable {
    let claudeAiOauth: ClaudeCodeOAuthCredential
}

enum ClaudeCodeCredentialStore {
    private static let service = "Claude Code-credentials"

    static func readAccessToken() -> String? {
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
            return wrapped.claudeAiOauth.accessToken
        }
        if let bare = try? JSONDecoder().decode(ClaudeCodeOAuthCredential.self, from: data) {
            return bare.accessToken
        }
        return nil
    }
}
