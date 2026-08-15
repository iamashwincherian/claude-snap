# ClaudeSnap

macOS status bar app for Claude Code—shows live usage, opens a Quake-style dropdown terminal on hotkey (Ctrl+`), and provides session management with working directory persistence.

## Build & Test

```bash
xcodebuild build -scheme ClaudeSnap -configuration Debug
# Runs from: ~/Library/Developer/Xcode/DerivedData/ClaudeSnap-*/Build/Products/Debug/ClaudeSnap.app
open ClaudeSnap.app
```

Kill and relaunch during development:
```bash
pkill -f "ClaudeSnap.app/Contents/MacOS/ClaudeSnap"
xcodebuild build -scheme ClaudeSnap -configuration Debug && \
open "$(find ~/Library/Developer/Xcode/DerivedData/ClaudeSnap-*/Build/Products/Debug -name "ClaudeSnap.app" -type d | head -1)"
```

## Architecture

### Status Bar & Window
- `StatusBarController`: Menu bar icon, polling integration, style rendering (glyph, ring, text, full)
- `MenuBarIconRenderer`: Draws chevron + ring arc (18×18pt canvas, sampled polyline, themed colors)
- `DropdownWindowController`: Quake-style reveal/retract with Spring animations (CABasicAnimation), stale-animation cleanup for race safety

### Terminal
- `TerminalViewController`: Hosts SwiftTerm PTY, runs `exec claude` so the process *is* Claude Code (not spawning it as a subprocess)
- `WorkingDirectoryResolver`: Fallback chain: `defaultWorkingDirectory` (user picker) → `lastWorkingDirectory` → `$HOME`
- `AppPreferences`: Persists settings; `rememberWorkingDirectory()` refuses to store `$HOME` (Claude Code won't trust home on relaunch)

### Usage Polling
- `UsagePoller`: One-shot timers (not repeating), exponential backoff (60s → 120s → 240s… up to 10min), transient-failure tolerance (3 strikes)
- `LocalCredentialUsageProvider`: Reads Claude Code's OAuth token from Keychain, queries `https://api.anthropic.com/api/oauth/usage` (unofficial, reverse-engineered, subject to change)
- Response format as of 2026-08: `{five_hour: {utilization: Double, resets_at: ISO8601String}}`
- HTTP 429 treated as transient; holds last good reading through backoff; only shows "unavailable" after 3 consecutive failures
- Menu bar shows bare icon (no ring) when unavailable; status line at terminal bottom shows "usage unavailable" for detail

### Live Status Line (Optional)
- `ClaudeCodeStatusLineBridge`: Wraps `~/.claude/settings.json` `statusLine.command` to capture JSON hook output
- `ClaudeCodeStatusLineWatcher`: Polls `~/Library/Application Support/ClaudeSnap/statusline.json` every 2s for model/context%/cost
- Integrated into terminal status bar if enabled in Preferences

### Session Lifecycle
- `ProcessTerminated` callback closes the dropdown when Claude exits
- Next hotkey press re-opens with fresh session

## Known Constraints

**Unofficial endpoint**: The usage polling endpoint is reverse-engineered and not documented by Anthropic. It can change response shape, rate limits, or disappear entirely. The code degrades gracefully to `.unavailable` instead of crashing if this happens.

**Rate limiting on the endpoint itself**: Separate from your Claude Code session quota. Polling it too frequently (e.g., many app restarts in quick succession) triggers HTTP 429 on the endpoint's own rate limiter. Once hit, it lasts ~1–3 hours depending on how aggressively you were polling. Your Claude Code session still works; you just can't fetch live usage until the endpoint recovers.

**Trust prompt for home folder**: Claude Code deliberately doesn't persist trust for `$HOME`. If the app falls back to launching in home, Claude will ask for trust on every session start. Use Preferences → Terminal → Open in to pick a project folder instead.

## Code Style

**Ponytail mode**: Lazy, efficient code. No speculative abstractions, no boilerplate for "later," deletion over addition. Prefer stdlib and platform features; reuse existing code; shortest diff wins. When simpler solutions cut real corners, mark them with `# ponytail: [ceiling], [upgrade path]`.

**Minimal comments**: WHY only, not WHAT. Naming is clear; code is straightforward.

**Animations**: Core Animation with explicit cleanup of stale animations before applying new state (see `animateReveal()`/`animateRetract()` in `DropdownWindowController`).

**Error handling**: Degrade gracefully at system boundaries (network, file I/O, Keychain). Trust internal code. No defensive null-checks for internal invariants.

## Files to Know

- `ClaudeSnap/App/AppDelegate.swift`: Entry point, status bar setup
- `ClaudeSnap/Window/DropdownWindowController.swift`: Animation, event handling
- `ClaudeSnap/Terminal/TerminalViewController.swift`: SwiftTerm integration, session lifecycle
- `ClaudeSnap/StatusBar/StatusBarController.swift`: Menu bar icon + text, polling wiring
- `ClaudeSnap/StatusBar/MenuBarIconRenderer.swift`: Icon drawing
- `ClaudeSnap/Usage/UsagePoller.swift`: Polling loop, backoff, transient failure handling
- `ClaudeSnap/Usage/LocalCredentialUsageProvider.swift`: OAuth token, HTTP fetch, response decode
- `ClaudeSnap/Support/AppPreferences.swift`: Settings persistence
- `ClaudeSnap/Preferences/PreferencesView.swift`: Settings UI

## Testing

1. **Manual**: Open app, toggle hotkey, verify dropdown opens/closes; check menu bar icon updates
2. **Status polling**: Monitor menu bar icon for usage % during Claude Code usage; verify exponential backoff in Console if endpoint returns 429
3. **Trust prompt**: Set a project folder in Preferences; kill app; relaunch; verify Claude doesn't ask for trust
