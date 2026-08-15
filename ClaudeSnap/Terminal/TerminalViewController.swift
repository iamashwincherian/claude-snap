import AppKit
import SwiftTerm

/// Hosts a `LocalProcessTerminalView` (real PTY) that `exec`s straight into `claude` after
/// sourcing the login shell's rc files — so the pty's process *is* Claude Code, not a shell that
/// happens to have typed `claude`. That makes exiting Claude Code (Ctrl-C, `/exit`, etc.) end the
/// pty itself, which `processTerminated` turns into "close the panel and start a fresh session
/// next time" rather than dropping back to a bare shell prompt. A status line strip sits pinned
/// to the bottom.
final class TerminalViewController: NSViewController {
    private let preferences: AppPreferences
    private let poller: UsagePoller
    private var terminalView: LocalProcessTerminalView!
    private var statusLine: StatusLineController!
    private var hasStarted = false

    /// Fires when the Claude Code session process exits, so the owner can close the dropdown.
    var onSessionEnded: (() -> Void)?

    init(preferences: AppPreferences, poller: UsagePoller) {
        self.preferences = preferences
        self.poller = poller
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = FlippedView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.processDelegate = self
        terminal.nativeBackgroundColor = NSColor(srgbHex: 0x18181B, alpha: 0.72)
        terminal.font = NSFont(name: "SFMono-Regular", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView = terminal

        let statusLineController = StatusLineController(preferences: preferences, poller: poller)
        statusLine = statusLineController
        let statusView = statusLineController.containerView
        statusView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(terminal)
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: view.topAnchor),
            terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: statusView.topAnchor),

            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.heightAnchor.constraint(equalToConstant: 23)
        ])
    }

    private func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        var cwd = WorkingDirectoryResolver.resolve(fallback: preferences.terminalFallbackDirectory)
        // Nothing resolved (no Finder/editor folder, no prior session, no explicit default) and
        // we've never asked before: offer a folder picker instead of silently opening in `$HOME`,
        // which would re-trigger Claude Code's trust prompt on every future launch too.
        if cwd == NSHomeDirectory(), preferences.defaultWorkingDirectory == nil, !preferences.hasPromptedInitialDirectory {
            preferences.markPromptedInitialDirectory()
            if let chosen = DirectoryPicker.choose(
                message: "Pick the project folder Claude Snap should open in. Change this anytime from the menu bar icon's right-click menu."
            ) {
                cwd = chosen
                preferences.defaultWorkingDirectory = chosen
            }
        }
        preferences.rememberWorkingDirectory(cwd)
        statusLine.updateWorkingDirectory(cwd)
        // `-ilc "exec claude"`: interactive login shell so PATH/nvm/rbenv-style shims that put
        // `claude` on PATH are sourced the same way they would be in Terminal.app, then `exec`
        // replaces the shell with `claude` itself rather than running it as a child — so the pty
        // process's own exit is Claude Code's exit.
        terminalView.startProcess(executable: LoginShell.path, args: ["-ilc", "exec claude"], currentDirectory: cwd)
    }
}

extension TerminalViewController: DropdownPresentable {
    func panelWillShow() {
        startIfNeeded()
    }
}

extension TerminalViewController: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        preferences.rememberWorkingDirectory(directory)
        statusLine.updateWorkingDirectory(directory)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        hasStarted = false
        terminalView.getTerminal().resetToInitialState()
        onSessionEnded?()
    }
}
