import AppKit
import ApplicationServices

/// Picks the directory the new terminal should open in: the frontmost Finder window's target
/// folder, or the containing folder of the frontmost editor's focused document (via the
/// accessibility `AXDocument` attribute, which works across most NSDocument-based apps without
/// per-app scripting support), falling back to `$HOME`.
enum WorkingDirectoryResolver {
    /// `fallback` is used when neither Finder nor an editor's focused document resolves —
    /// pass the last directory a session actually opened in, not `$HOME`. Claude Code
    /// deliberately never remembers trust for `$HOME` (unlike every real project directory), so
    /// defaulting to it makes the trust prompt reappear on every single launch.
    static func resolve(fallback: String) -> String {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return fallback
        }

        if app.bundleIdentifier == "com.apple.finder", let dir = finderFrontWindowDirectory() {
            return dir
        }
        if let dir = axFrontDocumentDirectory(pid: app.processIdentifier) {
            return dir
        }
        return fallback
    }

    /// The accessibility permission `axFrontDocumentDirectory` uses is deliberately never
    /// *prompted* for. A code-signature change (every rebuild, every app update) invalidates the
    /// TCC grant, so a proactive `AXIsProcessTrustedWithOptions(prompt: true)` nags on launch
    /// after launch with no way to satisfy it permanently. The AX lookup is only one candidate
    /// among the picker's list now, and it already degrades silently when untrusted — so grant it
    /// by hand in System Settings if you want it, and nothing breaks if you don't.

    /// The Finder-automation permission `finderFrontWindowDirectory` needs is different: fire it
    /// once at launch, off the main thread, so its TCC prompt lands before the dropdown ever
    /// shows. Otherwise the prompt appears the first time `resolve()` runs (while the dropdown is
    /// open), and answering it is a mouse click outside the panel — which the dropdown's own
    /// "click outside to dismiss" handling was closing the panel over.
    static func requestAutomationPermissionIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            _ = finderFrontWindowDirectory()
        }
    }

    private static func finderFrontWindowDirectory() -> String? {
        let source = """
        tell application "Finder"
            if (count of Finder windows) = 0 then return ""
            return POSIX path of (target of front window as alias)
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let path = result.stringValue, !path.isEmpty else { return nil }
        return path
    }

    private static func axFrontDocumentDirectory(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement

        var docRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef) == .success,
              let urlString = docRef as? String,
              let url = URL(string: urlString), url.isFileURL else { return nil }

        return url.deletingLastPathComponent().path
    }
}
