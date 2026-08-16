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
    private let workingStateWatcher: ClaudeWorkingStateWatcher
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var workingPulseTimer: Timer?
    private var pulseOn = false

    init(preferences: AppPreferences, poller: UsagePoller, workingStateWatcher: ClaudeWorkingStateWatcher) {
        self.preferences = preferences
        self.poller = poller
        self.workingStateWatcher = workingStateWatcher
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        poller.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        workingStateWatcher.onChange = { [weak self] in
            guard let self else { return }
            self.updateWorkingPulse(self.workingStateWatcher.isWorking)
            self.render()
        }

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
        if appendUsageRows(to: menu) {
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claude Snap", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Appends the session/weekly/extra-usage progress rows. Returns whether anything was added,
    /// so the caller knows whether it needs a trailing separator before Preferences.
    private func appendUsageRows(to menu: NSMenu) -> Bool {
        let usage = poller.snapshot
        guard usage.isAvailable else { return false }

        appendUsageRow(to: menu, title: "Session (5 hour)", resetText: sessionResetText(usage.windowResetsAt), percent: usage.percentUsed)
        if let weeklyPercent = usage.weeklyPercentUsed {
            appendUsageRow(to: menu, title: "Weekly (7 day)", resetText: weeklyResetText(usage.weeklyResetsAt), percent: weeklyPercent)
        }
        if let extra = usage.extraUsage {
            appendUsageRow(to: menu, title: "Extra usage", resetText: extraUsageResetText(), percent: extra.percentUsed)
        }
        return true
    }

    private func appendUsageRow(to menu: NSMenu, title: String, resetText: String, percent: Double) {
        let item = NSMenuItem()
        item.view = UsageMenuRowView(title: title, resetText: resetText, percent: percent, barColor: DesignColor.clay)
        menu.addItem(item)
    }

    private func sessionResetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "Resets at \(formatter.string(from: date))"
    }

    private func weeklyResetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return "Resets on \(formatter.string(from: date))"
    }

    /// The API supplies no reset date for extra usage (unlike the two rate-limit windows) — it's
    /// a monthly credit pool, so "1st of next month" is computed here instead.
    private func extraUsageResetText() -> String {
        let calendar = Calendar.current
        guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())),
              let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfThisMonth) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Resets \(formatter.string(from: startOfNextMonth))"
    }

    @objc private func openPreferences() { onOpenPreferences?() }
    @objc private func quit() { onQuit?() }

    // MARK: - Rendering

    private func updateWorkingPulse(_ isWorking: Bool) {
        workingPulseTimer?.invalidate()
        workingPulseTimer = nil
        pulseOn = false
        guard isWorking else { return }
        workingPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pulseOn.toggle()
                self?.render()
            }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let usage = poller.snapshot
        let style = preferences.iconStyle
        let isLight = isLightMenuBar(button: button)

        let title = NSMutableAttributedString()
        var hasContent = false
        let gap = NSAttributedString(string: " ")

        switch style {
        case .glyph, .ring:
            break
        case .text:
            let text = attributedText(usage: usage, includeReset: false, isLight: isLight)
            if text.length > 0 {
                if hasContent { title.append(gap) }
                title.append(text)
                hasContent = true
            }
        case .full:
            let text = attributedText(usage: usage, includeReset: true, isLight: isLight)
            if text.length > 0 {
                if hasContent { title.append(gap) }
                title.append(text)
                hasContent = true
            }
        }

        if workingStateWatcher.isWorking {
            if hasContent { title.append(gap) }
            title.append(workingDotAttachment())
        }

        button.image = MenuBarIconRenderer.image(usage: usage, style: style, isLightMenuBar: isLight)
        button.imagePosition = title.length == 0 ? .imageOnly : .imageLeft
        button.attributedTitle = title
    }

    /// The working dot lives inside the status item's own title — trailing the percentage — rather
    /// than in a second `NSStatusItem`: the logo and percentage are one item, so a separate item
    /// would read as an unrelated third icon (and macOS orders items by persisted position, not by
    /// creation, so it wouldn't reliably stay adjacent anyway).
    ///
    /// The image keeps its size while `pulseOn` blanks it, so the breathing animation doesn't
    /// change the item's width every tick.
    private func workingDotAttachment() -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = MenuBarIconRenderer.workingIndicatorImage(pulseOn: pulseOn)
        attachment.bounds = CGRect(x: 0, y: 0, width: MenuBarIconRenderer.workingDotSize.width, height: MenuBarIconRenderer.workingDotSize.height)
        return NSAttributedString(attachment: attachment)
    }

    /// Unavailable (including a transient rate limit — see `UsagePoller`) renders as just the bare
    /// chevron icon with no title, same as `.glyph`/`.ring`: the "usage unavailable" wording stays
    /// on the terminal's own status line (`SessionSegment`), which has room to explain itself.
    private func attributedText(usage: UsageSnapshot, includeReset: Bool, isLight: Bool) -> NSAttributedString {
        guard usage.isAvailable else { return NSAttributedString(string: "") }
        let level = UsageLevel.level(for: usage.percentUsed, thresholds: preferences.thresholds)
        var text = "  " + UsageFormat.percentString(usage)
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
