import Foundation

/// The subset of Claude Code's `statusLine` hook JSON (fed to the hook command on stdin) that
/// Claude Snap's model/ctx/cost segments need. Full shape includes `workspace`, `rate_limits`,
/// etc. — see `~/.claude/statusline-command.sh` for a fuller consumer.
struct ClaudeCodeStatusLinePayload: Decodable, Equatable {
    struct Model: Decodable, Equatable { let displayName: String
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }
    struct Cost: Decodable, Equatable { let totalCostUsd: Double?
        enum CodingKeys: String, CodingKey { case totalCostUsd = "total_cost_usd" }
    }
    struct ContextWindow: Decodable, Equatable { let usedPercentage: Double?
        enum CodingKeys: String, CodingKey { case usedPercentage = "used_percentage" }
    }

    let model: Model
    let cost: Cost?
    let contextWindow: ContextWindow?
    enum CodingKeys: String, CodingKey {
        case model, cost
        case contextWindow = "context_window"
    }
}

/// Claude Code has no API for a running session's model/context/cost — the only place that data
/// exists is the JSON fed to the user's `statusLine` hook command. This installs a wrapper script
/// that tees that JSON to a file Claude Snap can read, then forwards the original stdin to
/// whatever command was already configured (so the user's own status line output, e.g. a colored
/// bar printed in the CLI, is unaffected). Opt-in only, since it edits `~/.claude/settings.json`.
enum ClaudeCodeStatusLineBridge {
    static let dataFileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeSnap", isDirectory: true)
        .appendingPathComponent("statusline.json")

    private static let claudeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    private static let settingsURL = claudeDir.appendingPathComponent("settings.json")
    private static let wrapperScriptURL = claudeDir.appendingPathComponent("claudesnap-statusline-wrapper.sh")
    private static let originalCommandURL = claudeDir.appendingPathComponent("claudesnap-statusline-wrapper.original")
    private static let wrapperCommand = "bash ~/.claude/claudesnap-statusline-wrapper.sh"

    enum BridgeError: Error { case settingsJSONNotADictionary }

    static func install() throws {
        var settings = try readSettings()
        let existingCommand = ((settings["statusLine"] as? [String: Any])?["command"] as? String)
        guard existingCommand != wrapperCommand else { return }

        try FileManager.default.createDirectory(at: dataFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (existingCommand ?? "").write(to: originalCommandURL, atomically: true, encoding: .utf8)
        try wrapperScript(forwardingTo: existingCommand).write(to: wrapperScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperScriptURL.path)

        settings["statusLine"] = ["type": "command", "command": wrapperCommand]
        try writeSettings(settings)
    }

    static func uninstall() throws {
        var settings = try readSettings()
        guard ((settings["statusLine"] as? [String: Any])?["command"] as? String) == wrapperCommand else { return }

        let original = (try? String(contentsOf: originalCommandURL, encoding: .utf8)) ?? ""
        if original.isEmpty {
            settings.removeValue(forKey: "statusLine")
        } else {
            settings["statusLine"] = ["type": "command", "command": original]
        }
        try writeSettings(settings)
        try? FileManager.default.removeItem(at: wrapperScriptURL)
        try? FileManager.default.removeItem(at: originalCommandURL)
    }

    private static func wrapperScript(forwardingTo originalCommand: String?) -> String {
        let forward = originalCommand.map { "printf '%s' \"$input\" | \($0)" } ?? ""
        return """
        #!/bin/bash
        # Installed by Claude Snap. Captures the statusLine JSON for the app, then forwards it
        # unchanged to whatever statusLine command was configured before Claude Snap ran.
        input=$(cat)
        printf '%s' "$input" > "\(dataFileURL.path)"
        \(forward)
        """
    }

    private static func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.settingsJSONNotADictionary
        }
        return dict
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try data.write(to: settingsURL)
    }
}

/// Polls the file `ClaudeCodeStatusLineBridge` writes to and decodes it. Polling (not a
/// DispatchSource watch) because the file may not exist yet and gets replaced, not appended —
/// matches the polling style `StatusLineController` already uses for git status.
@MainActor
final class ClaudeCodeStatusLineWatcher {
    private(set) var payload: ClaudeCodeStatusLinePayload?
    private var lastModified: Date?
    private var timer: Timer?
    var onChange: (() -> Void)?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    private func poll() {
        let url = ClaudeCodeStatusLineBridge.dataFileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date, modified != lastModified,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ClaudeCodeStatusLinePayload.self, from: data) else { return }
        lastModified = modified
        payload = decoded
        onChange?()
    }
}
