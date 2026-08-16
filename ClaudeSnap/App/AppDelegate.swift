import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences.shared
    private var poller: UsagePoller!
    private var workingStateWatcher: ClaudeWorkingStateWatcher!
    private var statusBarController: StatusBarController!
    private var dropdownController: DropdownWindowController!
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        poller = UsagePoller(provider: LocalCredentialUsageProvider(), intervalSeconds: preferences.usagePollIntervalSeconds)
        poller.start()

        ClaudeWorkingStateBridge.install()
        workingStateWatcher = ClaudeWorkingStateWatcher()
        workingStateWatcher.start()

        let dropdownController = DropdownWindowController(preferences: preferences)
        let terminalViewController = TerminalViewController(preferences: preferences, poller: poller)
        terminalViewController.onSessionEnded = { [weak dropdownController] in dropdownController?.hide() }
        dropdownController.embedContent(terminalViewController)
        self.dropdownController = dropdownController

        WorkingDirectoryResolver.requestAutomationPermissionIfNeeded()

        let statusBarController = StatusBarController(preferences: preferences, poller: poller, workingStateWatcher: workingStateWatcher)
        statusBarController.onToggle = { [weak dropdownController] in dropdownController?.toggle() }
        statusBarController.onOpenPreferences = { [weak self] in self?.openPreferences() }
        statusBarController.onQuit = { NSApp.terminate(nil) }
        self.statusBarController = statusBarController
        dropdownController.statusItemWindow = statusBarController.buttonWindow

        HotkeyManager.registerToggleHandler { [weak dropdownController] in dropdownController?.toggle() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func openPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(preferences: preferences)))
            window.title = "Claude Snap Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}
