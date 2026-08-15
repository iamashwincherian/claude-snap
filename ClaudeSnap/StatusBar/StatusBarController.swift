import AppKit
import Combine

/// Owns the NSStatusItem: renders the live icon/text per `AppPreferences.iconStyle`, routes a
/// left click to toggling the dropdown and a right click to a small menu (Preferences / Quit).
@MainActor
final class StatusBarController: NSObject {
    var onToggle: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    /// The status item button's own window — so `DropdownWindowController`'s outside-click
    /// dismiss monitor can ignore clicks here and leave toggling entirely to `onToggle`.
    var buttonWindow: NSWindow? { statusItem.button?.window }

    private let statusItem: NSStatusItem
    private let preferences: AppPreferences
    private let poller: UsagePoller
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var workingPulseTimer: Timer?
    private var pulseOn = false

    init(preferences: AppPreferences, poller: UsagePoller) {
        self.preferences = preferences
        self.poller = poller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        poller.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.updateWorkingPulse(snapshot.isWorking); self?.render() }
            .store(in: &cancellables)

        preferences.$iconStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        preferences.$amberThreshold.merge(with: preferences.$redThreshold.map { _ in 0.0 })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.render()
        }

        render()
    }

    // MARK: - Interaction

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            onToggle?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Terminal In…", action: #selector(chooseWorkingDirectory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claude Snap", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Sets where the *next* session opens, without going through Preferences — the folder takes
    /// effect the next time the dropdown starts a session (the currently running one, if any,
    /// keeps its own cwd).
    @objc private func chooseWorkingDirectory() {
        guard let path = DirectoryPicker.choose(
            startingAt: preferences.defaultWorkingDirectory,
            message: "Pick the folder new terminal sessions should open in."
        ) else { return }
        preferences.defaultWorkingDirectory = path
    }

    @objc private func openPreferences() { onOpenPreferences?() }
    @objc private func quit() { onQuit?() }

    // MARK: - Rendering

    private func updateWorkingPulse(_ isWorking: Bool) {
        workingPulseTimer?.invalidate()
        workingPulseTimer = nil
        pulseOn = false
        guard isWorking, preferences.iconStyle == .glyph else { return }
        workingPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pulseOn.toggle()
                self?.render()
            }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        var usage = poller.snapshot
        let style = preferences.iconStyle
        let isLight = isLightMenuBar(button: button)

        if usage.isWorking, style == .glyph, !pulseOn {
            // Breathing dot: alternate opacity by skipping the draw every other tick rather than
            // animating the NSImage itself.
            usage.isWorking = false
        }

        button.image = MenuBarIconRenderer.image(usage: usage, style: style, isLightMenuBar: isLight)
        button.imagePosition = style == .glyph || style == .ring ? .imageOnly : .imageLeft

        switch style {
        case .glyph, .ring:
            button.attributedTitle = NSAttributedString(string: "")
        case .text:
            button.attributedTitle = attributedText(usage: poller.snapshot, includeReset: false, isLight: isLight)
        case .full:
            button.attributedTitle = attributedText(usage: poller.snapshot, includeReset: true, isLight: isLight)
        }
    }

    /// Unavailable (including a transient rate limit — see `UsagePoller`) renders as just the bare
    /// chevron icon with no title, same as `.glyph`/`.ring`: the "usage unavailable" wording stays
    /// on the terminal's own status line (`SessionSegment`), which has room to explain itself.
    private func attributedText(usage: UsageSnapshot, includeReset: Bool, isLight: Bool) -> NSAttributedString {
        guard usage.isAvailable else { return NSAttributedString(string: "") }
        let level = UsageLevel.level(for: usage.percentUsed, thresholds: preferences.thresholds)
        var text = " " + UsageFormat.percentString(usage)
        if includeReset {
            let reset = UsageFormat.resetString(usage)
            if !reset.isEmpty { text += " · " + reset }
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: level.nsColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    private func isLightMenuBar(button: NSButton) -> Bool {
        button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }
}
