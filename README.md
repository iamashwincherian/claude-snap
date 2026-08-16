# <img src="ClaudeSnap/Resources/octopus.svg" width="36" height="32" align="center" alt="">&nbsp;&nbsp;ClaudeSnap

macOS status bar app for Claude Code — shows live usage, opens a Quake-style dropdown terminal on hotkey (double-tap Control), and provides session management with working directory persistence.

## Installation

### From Latest Release (Recommended)

```bash
curl -s https://raw.githubusercontent.com/iamashwincherian/claude-snap/main/install.sh | bash
```

Or download and run the installer:
```bash
curl -O https://raw.githubusercontent.com/iamashwincherian/claude-snap/main/install.sh
chmod +x install.sh
./install.sh
```

> **Note:** ClaudeSnap isn't notarized by Apple (that requires a paid Developer account), so if you install it manually instead of via `install.sh` — e.g. downloading the zip from a browser and dragging it to Applications — macOS Gatekeeper may say the app "is damaged and can't be opened." It isn't actually damaged; that's just Gatekeeper reacting to the quarantine flag on an unnotarized app. Fix it with:
> ```bash
> xattr -cr /Applications/ClaudeSnap.app
> ```

### Build from Source

**Requirements:**
- macOS 13.0+
- Xcode 15+
- Swift 5.0+

```bash
git clone https://github.com/iamashwincherian/claude-snap.git
cd claude-snap
xcodebuild build -scheme ClaudeSnap -configuration Release
cp -r ~/Library/Developer/Xcode/DerivedData/ClaudeSnap-*/Build/Products/Release/ClaudeSnap.app /Applications/
```

## Usage

**Launch:** Open `/Applications/ClaudeSnap.app` or add it to Login Items for auto-start.

**Hotkey:** Double-tap **Control** to toggle the dropdown terminal (configurable in Preferences → Hotkey, where you can swap in a custom key instead).

**Menu Bar Icons:**
- Click the icon to toggle the terminal
- Right-click for preferences and quick options
- Icon shows live usage % (configurable style: glyph, ring, text, or full)

**Terminal:**
- Runs Claude Code in a PTY
- Works directory persists across sessions
- Set default folder in Preferences → Terminal

**Preferences:**
- **Terminal:** Default working directory, remember last location
- **Usage Display:** Show live token usage with thresholds for warning/critical colors
- **Status Line:** Optional live status line showing current model/context/cost

## Features

### Live Usage Polling
- Reads your OAuth token from Keychain (same one Claude Code uses)
- Queries usage endpoint every 60–600s (exponential backoff)
- Degrades gracefully on network errors (shows "unavailable" after 3 consecutive failures)
- Rate-limit aware (the endpoint itself rate-limits; app backs off automatically)

### Window Management
- Quake-style reveal/hide with Spring animations
- Stale animation cleanup for race safety
- Closes gracefully when Claude session exits

### Session Persistence
- Remembers last working directory
- Respects `defaultWorkingDirectory` setting
- Refuses to trust `$HOME` (Claude Code won't persist trust for home folder on relaunch)

## Constraints & Known Behavior

**Unofficial endpoint:** Usage polling uses a reverse-engineered endpoint not documented by Anthropic. If the response shape, rate limits, or availability change, the app degrades gracefully instead of crashing.

**Rate limiting:** The usage endpoint has its own separate rate limiter (distinct from your Claude Code quota). Polling too frequently in quick succession (e.g., many app restarts) can trigger HTTP 429 for 1–3 hours. Your Claude Code still works; you just won't see live usage until the endpoint recovers.

**Trust prompt for home:** Claude Code deliberately doesn't persist trust for `$HOME`. If the app falls back to launching in home, Claude will ask for permission on every session start. Use Preferences → Terminal → Open in to pick a project folder instead.

## Architecture

- **StatusBarController:** Menu bar icon, polling integration, style rendering
- **MenuBarIconRenderer:** Draws the spoke-mark glyph + ring arc
- **DropdownWindowController:** Quake-style animation and event handling
- **TerminalViewController:** SwiftTerm PTY, runs Claude Code directly
- **WorkingDirectoryResolver:** Fallback chain for session folder
- **UsagePoller:** One-shot timers, exponential backoff, transient-failure tolerance
- **LocalCredentialUsageProvider:** Reads OAuth token, fetches usage

## Code Style

- **Lazy, efficient code:** Stdlib and platform features first, no speculative abstractions
- **Minimal comments:** WHY only, not WHAT
- **Animations:** Core Animation with explicit stale-animation cleanup
- **Error handling:** Degrade gracefully at system boundaries (network, file I/O, Keychain)

## Development

```bash
# Build Debug
xcodebuild build -scheme ClaudeSnap -configuration Debug

# Build & run
pkill -f "ClaudeSnap.app/Contents/MacOS/ClaudeSnap" || true
xcodebuild build -scheme ClaudeSnap -configuration Debug && \
open "$(find ~/Library/Developer/Xcode/DerivedData/ClaudeSnap-*/Build/Products/Debug -name "ClaudeSnap.app" -type d | head -1)"
```

See [`CLAUDE.md`](CLAUDE.md) for more details on architecture, testing, and constraints.

## License

See LICENSE file.
