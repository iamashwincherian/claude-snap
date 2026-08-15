import AppKit
import Combine

/// Glues segment providers + `AppPreferences` ordering/toggles + live usage into the visual
/// strip. `model`/`ctx`/`cost` are backed by `ClaudeCodeStatusLineWatcher`, which reads the file
/// `ClaudeCodeStatusLineBridge` writes once installed (Preferences ▸ Live status line) — until
/// then they render the `UnavailableSegment` placeholder.
@MainActor
final class StatusLineController {
    let containerView: StatusLineView = StatusLineView()

    private let preferences: AppPreferences
    private let poller: UsagePoller
    private let liveStatusLineWatcher = ClaudeCodeStatusLineWatcher()
    private var cancellables = Set<AnyCancellable>()
    private var gitTimer: Timer?

    private var workingDirectory = NSHomeDirectory()
    private var gitBranch: String?
    private var gitDirtyCount: Int?

    private let segments: [StatusLineSegmentID: StatusLineSegmentProvider] = {
        let list: [StatusLineSegmentProvider] = [
            CwdSegment(), BranchSegment(), DirtySegment(), SessionSegment(),
            ModelSegment(), ContextSegment(), CostSegment()
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    init(preferences: AppPreferences, poller: UsagePoller) {
        self.preferences = preferences
        self.poller = poller

        poller.$snapshot.combineLatest(preferences.$statusLineSegmentOrder, preferences.$statusLineSegmentDisabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.render() }
            .store(in: &cancellables)
        liveStatusLineWatcher.onChange = { [weak self] in self?.render() }
        liveStatusLineWatcher.start()
        render()

        // Dirty count can change from outside the terminal (another shell, an editor save), so
        // poll it lightly rather than only on `cd`.
        gitTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshGitInfo() }
        }
    }

    func updateWorkingDirectory(_ path: String) {
        guard path != workingDirectory else { return }
        workingDirectory = path
        refreshGitInfo()
    }

    private func refreshGitInfo() {
        let dir = workingDirectory
        Task.detached(priority: .utility) {
            let branch = GitInspector.branch(at: dir)
            let dirty = branch != nil ? GitInspector.dirtyCount(at: dir) : nil
            await MainActor.run { [weak self] in
                guard let self, self.workingDirectory == dir else { return }
                self.gitBranch = branch
                self.gitDirtyCount = dirty
                self.render()
            }
        }
    }

    private func render() {
        let context = StatusLineContext(
            workingDirectory: workingDirectory,
            gitBranch: gitBranch,
            gitDirtyCount: gitDirtyCount,
            usage: poller.snapshot,
            thresholds: preferences.thresholds,
            liveStatusLine: liveStatusLineWatcher.payload
        )
        let order = preferences.statusLineSegmentOrder.filter { !preferences.statusLineSegmentDisabled.contains($0) }
        let values = order.compactMap { segments[$0]?.currentValue(context: context) }
        containerView.update(values)
    }
}
