import AppKit
import SwiftTerm

/// Hosts a `LocalProcessTerminalView` (real PTY) that alternates between a project picker and
/// `claude`, `exec`ing directly into each so the pty's process *is* whichever one is active — never
/// a shell sitting behind either. Picking a project execs into `claude` there; when Claude Code
/// exits, `processTerminated` execs the picker again; backing out of the picker (no selection) is
/// the only thing that closes the dropdown. A status line strip sits pinned to the bottom.
final class TerminalViewController: NSViewController {
    private let preferences: AppPreferences
    private let poller: UsagePoller
    private var terminalView: LocalProcessTerminalView!
    private var statusLine: StatusLineController!
    private var hasStarted = false

    /// Fires when the picker is dismissed without a selection, so the owner can close the dropdown.
    var onSessionEnded: (() -> Void)?

    /// The picker script's signal for "no project chosen" — distinct from any exit code `claude`
    /// itself could plausibly return, so `processTerminated` knows whether to reopen the picker or
    /// close the dropdown.
    private static let pickerCancelledExitCode: Int32 = 99

    /// A Finder-style drill-down browser: each loop iteration lists only the *current* directory's
    /// immediate subfolders (never the whole disk), plus ". (use current directory)" and `..` (up).
    /// Actually `cd`s each step so navigation and the preview resolve for free instead of needing
    /// a hand-tracked path string. Selecting "." breaks the loop; anything else descends and loops.
    /// Falls back to gum filter, then the shell's builtin `select`, one level at a time either way.
    /// Once "." is picked, execs `claude` — reporting the directory back via OSC 7 first since
    /// Swift never learns the chosen path any other way. No selection at any level exits 99.
    private static let pickerScript = #"""
    cd ~ || exit 99
    while true; do
      entries=$(printf '. (use current directory)\n..\n'; find . -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's#^\./##' | sort)
      if command -v fzf >/dev/null 2>&1; then
        choice=$(printf '%s\n' "$entries" | fzf \
          --prompt="$(pwd)/ " --height=100% --reverse \
          --border=rounded --border-label=' Quake Code ' --padding=1 \
          --input-border=rounded --input-label="[$(basename $(pwd))]" --list-border=rounded --preview-window=hidden --no-info \
          --color=border:#c6613f,fg+:#c6613f,hl:#c6613f \
          --header='Enter = go into folder | .. = up')
      elif command -v gum >/dev/null 2>&1; then
        choice=$(printf '%s\n' "$entries" | gum filter --placeholder='Search…' --header="$(pwd)" --height=15)
      else
        echo 'Tip: brew install fzf for a nicer browser.'
        IFS=$'\n'
        select choice in $entries; do break; done
        unset IFS
      fi
      [ -z "$choice" ] && exit 99
      [ "$choice" = ". (use current directory)" ] && break
      cd "$choice" || exit 99
    done
    dir=$(pwd)
    printf '\033]7;%s\033\\' "$dir"
    exec claude
    """#

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

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(srgbHex: 0x18181B, alpha: 0.72).cgColor

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
            terminal.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            terminal.bottomAnchor.constraint(equalTo: statusView.topAnchor, constant: -8),

            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.heightAnchor.constraint(equalToConstant: 23)
        ])
    }

    private func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        // `-ilc`: interactive login shell so PATH/nvm/rbenv-style shims that put `fzf` and
        // `claude` on PATH are sourced the same way they would be in Terminal.app.
        terminalView.startProcess(executable: LoginShell.path, args: ["-ilc", Self.pickerScript], currentDirectory: NSHomeDirectory())
    }

    private func launchClaude(in cwd: String) {
        preferences.rememberWorkingDirectory(cwd)
        statusLine.updateWorkingDirectory(cwd)
        setBackgroundColor(for: .claude)
        // `exec` replaces the shell with `claude` itself rather than running it as a child — so
        // the pty process's own exit is Claude Code's exit.
        terminalView.startProcess(executable: LoginShell.path, args: ["-ilc", "exec claude"], currentDirectory: cwd)
    }

    private func setBackgroundColor(for mode: Mode) {
        let (hexColor, alpha): (UInt32, CGFloat) = mode == .claude ? (0x1a1a1a, 1.0) : (0x18181B, 0.72)
        view.layer?.backgroundColor = NSColor(srgbHex: hexColor, alpha: alpha).cgColor
        terminalView.nativeBackgroundColor = NSColor(srgbHex: hexColor, alpha: alpha)
    }

    private enum Mode { case picker, claude }
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
        setBackgroundColor(for: .claude)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        hasStarted = false
        terminalView.getTerminal().resetToInitialState()
        if exitCode == Self.pickerCancelledExitCode {
            onSessionEnded?()
        } else {
            setBackgroundColor(for: .picker)
            // Relaunch on the *next* runloop turn, never inline: SwiftTerm's `LocalProcess`
            // calls this delegate method and then runs its own teardown (`childStopped()`)
            // afterwards. Starting the replacement process from inside the callback lets that
            // teardown land on the process we just started — clearing `running`, which makes
            // `send()` drop every keystroke, and cancelling the fresh exit monitor, which loses
            // the next termination entirely.
            DispatchQueue.main.async { [weak self] in self?.startIfNeeded() }
        }
    }
}
