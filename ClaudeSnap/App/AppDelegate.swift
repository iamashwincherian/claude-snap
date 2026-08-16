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
        let poller = UsagePoller(provider: LocalCredentialUsageProvider(), intervalSeconds: preferences.usagePollIntervalSeconds)
        self.poller = poller
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

        // Opening the terminal is the moment the usage figure matters most, and after a lid-close
        // the backoff timer can be up to ten minutes from its next tick. Both paths funnel through
        // one closure so the hotkey behaves like the menu bar click.
        let toggle: () -> Void = { [weak dropdownController, weak poller] in
            poller?.refreshIfStale()
            dropdownController?.toggle()
        }

        let statusBarController = StatusBarController(preferences: preferences, poller: poller, workingStateWatcher: workingStateWatcher)
        statusBarController.onToggle = toggle
        statusBarController.onOpenPreferences = { [weak self] in self?.openPreferences() }
        statusBarController.onQuit = { NSApp.terminate(nil) }
        self.statusBarController = statusBarController
        dropdownController.statusItemWindow = statusBarController.buttonWindow

        HotkeyManager.registerToggleHandler(toggle)

        // Timers don't fire while the Mac is asleep, so on wake the held reading can be hours old
        // and the next poll is however far the backoff had grown.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak poller] _ in
            Task { @MainActor in poller?.refresh() }
        }
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
