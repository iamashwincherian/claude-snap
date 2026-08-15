import AppKit

/// Shared `NSOpenPanel` folder chooser — used by the Preferences "Open in" row, the status bar's
/// right-click "Open Terminal In…" item, and the first-launch prompt.
enum DirectoryPicker {
    static func choose(startingAt directory: String? = nil, message: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        if let message { panel.message = message }
        panel.directoryURL = directory.map { URL(fileURLWithPath: $0) }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
