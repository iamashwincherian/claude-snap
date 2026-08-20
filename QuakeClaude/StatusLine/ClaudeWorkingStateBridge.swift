import Foundation

/// Claude Code exposes no API for "is the current session generating a response" — hooks are the
/// only place that state surfaces. `UserPromptSubmit` fires right as a prompt starts processing,
/// `Stop` fires when the agent hands control back, so installing both to flip a one-byte flag file
/// gives Quake Claude a working/idle signal with no polling of Claude Code itself required.
enum ClaudeWorkingStateBridge {
    static let stateFileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QuakeClaude", isDirectory: true)
        .appendingPathComponent("working", isDirectory: false)

    private static let claudeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    private static let settingsURL = claudeDir.appendingPathComponent("settings.json")

    private static let startCommand = "printf 1 > '\(stateFileURL.path)'"
    private static let stopCommand = "printf 0 > '\(stateFileURL.path)'"

    /// Idempotent and additive: merges into whatever `hooks` already exist (e.g. the ponytail
    /// plugin's `SessionStart` hook) instead of overwriting the key, and skips re-adding its own
    /// command if already present.
    static func install() {
        guard var settings = readSettings() else { return }
        try? FileManager.default.createDirectory(at: stateFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "0".write(to: stateFileURL, atomically: true, encoding: .utf8)

        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        hooks["UserPromptSubmit"] = mergedEntries(hooks["UserPromptSubmit"], adding: startCommand)
        hooks["Stop"] = mergedEntries(hooks["Stop"], adding: stopCommand)
        settings["hooks"] = hooks

        try? writeSettings(settings)
    }

    private static func mergedEntries(_ existing: Any?, adding command: String) -> [[String: Any]] {
        var entries = (existing as? [[String: Any]]) ?? []
        let alreadyInstalled = entries.contains { entry in
            ((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String) == command }
        }
        guard !alreadyInstalled else { return entries }
        entries.append(["matcher": "", "hooks": [["type": "command", "command": command]]])
        return entries
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try data.write(to: settingsURL)
    }
}

/// Polls the flag file `ClaudeWorkingStateBridge` writes to. A short interval (unlike the 2s
/// statusline poll) so the menu bar dot feels responsive to Claude actually starting/stopping.
@MainActor
final class ClaudeWorkingStateWatcher {
    private(set) var isWorking = false
    private var timer: Timer?
    private var lastModified: Date?
    var onChange: (() -> Void)?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    private func poll() {
        let url = ClaudeWorkingStateBridge.stateFileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date, modified != lastModified,
              let data = try? Data(contentsOf: url) else { return }
        lastModified = modified
        let working = data.first == UInt8(ascii: "1")
        guard working != isWorking else { return }
        isWorking = working
        onChange?()
    }
}
