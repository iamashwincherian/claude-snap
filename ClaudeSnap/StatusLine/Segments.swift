import AppKit

struct CwdSegment: StatusLineSegmentProvider {
    let id: StatusLineSegmentID = .cwd

    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue? {
        let name = (context.workingDirectory as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return StatusLineSegmentValue(icon: "◧", text: name)
    }
}

struct BranchSegment: StatusLineSegmentProvider {
    let id: StatusLineSegmentID = .branch

    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue? {
        guard let branch = context.gitBranch else { return nil }
        return StatusLineSegmentValue(icon: "⑂", text: branch, textColor: NSColor.white.withAlphaComponent(0.72))
    }
}

struct DirtySegment: StatusLineSegmentProvider {
    let id: StatusLineSegmentID = .dirty

    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue? {
        guard let count = context.gitDirtyCount, count > 0 else { return nil }
        return StatusLineSegmentValue(icon: "●", text: "\(count)", iconColor: DesignColor.amber, textColor: DesignColor.amber)
    }
}

struct SessionSegment: StatusLineSegmentProvider {
    let id: StatusLineSegmentID = .session

    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue? {
        guard context.usage.isAvailable else {
            return StatusLineSegmentValue(icon: "◔", text: "usage unavailable")
        }
        let level = UsageLevel.level(for: context.usage.percentUsed, thresholds: context.thresholds)
        let reset = UsageFormat.resetString(context.usage)
        let text = reset.isEmpty ? UsageFormat.percentString(context.usage) : UsageFormat.percentString(context.usage) + " · " + reset
        return StatusLineSegmentValue(icon: "◔", text: text, iconColor: level.nsColor, textColor: level.nsColor)
    }
}

/// Renders a dim placeholder until `ClaudeCodeStatusLineBridge` is installed (Preferences ▸ Live
/// status line) and the watcher has seen at least one payload from Claude Code's own `statusLine`
/// hook — the only place model/context/cost for a running session exist.
struct UnavailableSegment: StatusLineSegmentProvider {
    let id: StatusLineSegmentID
    let icon: String

    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue? {
        StatusLineSegmentValue(icon: icon, text: "—", textColor: NSColor.white.withAlphaComponent(0.3))
    }
}

struct ModelSegment: StatusLineSegmentProvider {
    let id: StatusLineSegmentID = .model

    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue? {
        guard let payload = context.liveStatusLine else {
            return StatusLineSegmentValue(icon: "✳", text: "—", textColor: NSColor.white.withAlphaComponent(0.3))
        }
        return StatusLineSegmentValue(icon: "✳", text: payload.model.displayName)
    }
}

struct ContextSegment: StatusLineSegmentProvider {
    let id: StatusLineSegmentID = .ctx

    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue? {
        guard let percent = context.liveStatusLine?.contextWindow?.usedPercentage else {
            return StatusLineSegmentValue(icon: "◍", text: "—", textColor: NSColor.white.withAlphaComponent(0.3))
        }
        let level = UsageLevel.level(for: percent, thresholds: context.thresholds)
        return StatusLineSegmentValue(icon: "◍", text: "\(Int(percent.rounded()))%", iconColor: level.nsColor, textColor: level.nsColor)
    }
}

struct CostSegment: StatusLineSegmentProvider {
    let id: StatusLineSegmentID = .cost

    func currentValue(context: StatusLineContext) -> StatusLineSegmentValue? {
        guard let cost = context.liveStatusLine?.cost?.totalCostUsd else {
            return StatusLineSegmentValue(icon: "$", text: "—", textColor: NSColor.white.withAlphaComponent(0.3))
        }
        return StatusLineSegmentValue(icon: "$", text: String(format: "%.2f", cost))
    }
}
