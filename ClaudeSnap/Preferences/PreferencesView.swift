import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var liveStatusLineError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Icon style", selection: $preferences.iconStyle) {
                    Text("Ring").tag(MenuBarIconStyle.ring)
                    Text("Ring + text").tag(MenuBarIconStyle.text)
                    Text("Ring + countdown").tag(MenuBarIconStyle.full)
                    Text("Glyph only").tag(MenuBarIconStyle.glyph)
                }
                Slider(value: $preferences.amberThreshold, in: 30...90, step: 1) {
                    Text("Amber above \(Int(preferences.amberThreshold))%")
                }
                Slider(value: $preferences.redThreshold, in: preferences.amberThreshold...99, step: 1) {
                    Text("Red above \(Int(preferences.redThreshold))%")
                }
            }

            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Toggle terminal:", name: .toggleTerminal)
            }

            Section("Terminal") {
                HStack {
                    Text("Open in")
                    Spacer()
                    Text(preferences.defaultWorkingDirectory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Auto")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button("Choose…", action: chooseDefaultDirectory)
                    if preferences.defaultWorkingDirectory != nil {
                        Button("Reset") { preferences.defaultWorkingDirectory = nil }
                    }
                }
                Text("Auto uses the frontmost Finder or editor folder. Claude Code never remembers trust for your home folder, so pick a project folder here if you keep getting asked to trust it on launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Window") {
                Picker("Show on", selection: $preferences.displayPreference) {
                    Text("Display with the pointer").tag(DisplayPreference.withPointer)
                    Text("Main display").tag(DisplayPreference.main)
                }
                Slider(value: $preferences.screenCoveragePercent, in: 25...95, step: 1) {
                    Text("Height \(Int(preferences.screenCoveragePercent))%")
                }
                Slider(value: $preferences.widthPercent, in: 40...100, step: 1) {
                    Text("Width \(Int(preferences.widthPercent))%")
                }
                Picker("Animation", selection: $preferences.animationSpeed) {
                    Text("Instant").tag(AnimationSpeed.instant)
                    Text("Standard").tag(AnimationSpeed.standard)
                    Text("Relaxed").tag(AnimationSpeed.relaxed)
                }
                .pickerStyle(.segmented)
            }

            Section("Live status line") {
                Toggle("Show real model / context % / cost", isOn: Binding(
                    get: { preferences.liveStatusLineEnabled },
                    set: { enabled in
                        do {
                            if enabled { try ClaudeCodeStatusLineBridge.install() } else { try ClaudeCodeStatusLineBridge.uninstall() }
                            preferences.liveStatusLineEnabled = enabled
                            liveStatusLineError = nil
                        } catch {
                            liveStatusLineError = error.localizedDescription
                        }
                    }
                ))
                Text("Adds a wrapper around your Claude Code `statusLine` hook (~/.claude/settings.json) that forwards to your existing command unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let liveStatusLineError {
                    Text(liveStatusLineError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Status bar segments") {
                ForEach(preferences.statusLineSegmentOrder, id: \.self) { id in
                    Toggle(id.displayName, isOn: Binding(
                        get: { !preferences.statusLineSegmentDisabled.contains(id) },
                        set: { enabled in
                            if enabled {
                                preferences.statusLineSegmentDisabled.remove(id)
                            } else {
                                preferences.statusLineSegmentDisabled.insert(id)
                            }
                        }
                    ))
                }
            }

            Section("Startup") {
                LaunchAtLogin.Toggle()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 480)
    }

    private func chooseDefaultDirectory() {
        guard let path = DirectoryPicker.choose(startingAt: preferences.defaultWorkingDirectory) else { return }
        preferences.defaultWorkingDirectory = path
    }
}
