import Foundation

/// Cheap, dependency-free git introspection: reads `.git/HEAD` directly for the branch (no
/// subprocess), shells out to `git status --porcelain` only for the dirty count. Both are called
/// off the main thread by `StatusLineController` and are safe to call from any queue.
enum GitInspector {
    static func branch(at directory: String) -> String? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: directory, isDirectory: true)

        for _ in 0..<32 {
            let gitURL = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) else {
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { return nil }
                dir = parent
                continue
            }
            // `.git` as a plain file (worktrees, submodules) isn't resolved in v1 — bail cleanly.
            guard isDirectory.boolValue,
                  let head = try? String(contentsOf: gitURL.appendingPathComponent("HEAD"), encoding: .utf8) else {
                return nil
            }
            let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
            let refPrefix = "ref: refs/heads/"
            if trimmed.hasPrefix(refPrefix) {
                return String(trimmed.dropFirst(refPrefix.count))
            }
            if trimmed.count >= 7 {
                return String(trimmed.prefix(7)) // detached HEAD, short SHA
            }
            return nil
        }
        return nil
    }

    static func dirtyCount(at directory: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory, "status", "--porcelain", "--untracked-files=normal"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").filter { !$0.isEmpty }.count
    }
}
