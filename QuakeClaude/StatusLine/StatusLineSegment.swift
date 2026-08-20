import AppKit

enum StatusLineSegmentID: String, CaseIterable {
    case cwd, branch, dirty, model, ctx, cost, session

    var displayName: String {
        switch self {
        case .cwd: return "Project name"
        case .branch: return "Git branch"
        case .dirty: return "Dirty / clean indicator"
        case .model: return "Model in use"
        case .ctx: return "Context window %"
        case .cost: return "Token cost this session"
        case .session: return "Session % + reset"
        }
    }
}

struct StatusLineSegmentValue {
    var icon: String
    var text: String
    var iconColor: NSColor = NSColor.white.withAlphaComponent(0.42)
    var textColor: NSColor = NSColor.white.withAlphaComponent(0.62)
}

struct StatusLineContext {
    var workingDirectory: String
    var gitBranch: String?
    var gitDirtyCount: Int?
    var usage: UsageSnapshot
    var thresholds: UsageThresholds
    var liveStatusLine: ClaudeCodeStatusLinePayload?
}

/// A single status bar segment. `currentValue` returning `nil` means "don't show right now" —
/// e.g. the branch segment outside a git repo — distinct from disabling it in Preferences.
protocol StatusLineSegmentProvider {
    var id: StatusLineSegmentID { get }
    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue?
}
