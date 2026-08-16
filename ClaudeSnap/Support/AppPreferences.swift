import Foundation
import Combine

enum MenuBarIconStyle: String, CaseIterable {
    case ring
    case text
    case full
    case glyph
}

enum AnimationSpeed: String, CaseIterable {
    case instant, standard, relaxed

    var retractDuration: TimeInterval {
        switch self {
        case .instant: return 0
        case .standard: return 0.2
        case .relaxed: return 0.3
        }
    }
}

enum DisplayPreference: String, CaseIterable {
    case withPointer
    case main
}

/// UserDefaults-backed, observable preferences store. Single source of truth read by the status
/// bar icon, the dropdown panel, and the Preferences window.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private let defaults: UserDefaults

    @Published var iconStyle: MenuBarIconStyle { didSet { defaults.set(iconStyle.rawValue, forKey: Keys.iconStyle) } }
    @Published var screenCoveragePercent: Double { didSet { defaults.set(screenCoveragePercent, forKey: Keys.screenCoverage) } }
    @Published var widthPercent: Double { didSet { defaults.set(widthPercent, forKey: Keys.widthPercent) } }
    @Published var amberThreshold: Double { didSet { defaults.set(amberThreshold, forKey: Keys.amberThreshold) } }
    @Published var redThreshold: Double { didSet { defaults.set(redThreshold, forKey: Keys.redThreshold) } }
    @Published var animationSpeed: AnimationSpeed { didSet { defaults.set(animationSpeed.rawValue, forKey: Keys.animationSpeed) } }
    @Published var displayPreference: DisplayPreference { didSet { defaults.set(displayPreference.rawValue, forKey: Keys.displayPreference) } }
    @Published var usagePollIntervalSeconds: Double { didSet { defaults.set(usagePollIntervalSeconds, forKey: Keys.pollInterval) } }
    @Published var statusLineSegmentOrder: [StatusLineSegmentID] {
        didSet { defaults.set(statusLineSegmentOrder.map(\.rawValue), forKey: Keys.segmentOrder) }
    }
    @Published var statusLineSegmentDisabled: Set<StatusLineSegmentID> {
        didSet { defaults.set(statusLineSegmentDisabled.map(\.rawValue), forKey: Keys.segmentDisabled) }
    }
    @Published var liveStatusLineEnabled: Bool { didSet { defaults.set(liveStatusLineEnabled, forKey: Keys.liveStatusLineEnabled) } }
    /// Where the terminal opened last — set only via `rememberWorkingDirectory`, never directly,
    /// so `$HOME` can't leak in and become a permanent fallback.
    @Published private(set) var lastWorkingDirectory: String? { didSet { defaults.set(lastWorkingDirectory, forKey: Keys.lastWorkingDirectory) } }
    /// Explicit user override for where sessions open when nothing else resolves.
    @Published var defaultWorkingDirectory: String? { didSet { defaults.set(defaultWorkingDirectory, forKey: Keys.defaultWorkingDirectory) } }

    /// Where a session opens when neither Finder nor a focused editor document resolves.
    ///
    /// Never plain `$HOME` if anything better is known: Claude Code deliberately does not persist
    /// `hasTrustDialogAccepted` for the home directory (trusting it would transitively trust every
    /// project beneath it), so a session that lands there re-asks the trust question every launch.
    var terminalFallbackDirectory: String {
        defaultWorkingDirectory ?? lastWorkingDirectory ?? NSHomeDirectory()
    }

    /// Records where a session actually ran, ignoring `$HOME` for the reason above — remembering
    /// it would pin the fallback to the one directory that always re-prompts.
    func rememberWorkingDirectory(_ path: String) {
        guard path != NSHomeDirectory() else { return }
        lastWorkingDirectory = path
    }

    var thresholds: UsageThresholds { UsageThresholds(amber: amberThreshold, red: redThreshold) }

    private enum Keys {
        static let iconStyle = "iconStyle"
        static let screenCoverage = "screenCoveragePercent"
        static let widthPercent = "widthPercent"
        static let amberThreshold = "amberThreshold"
        static let redThreshold = "redThreshold"
        static let animationSpeed = "animationSpeed"
        static let displayPreference = "displayPreference"
        static let pollInterval = "usagePollIntervalSeconds"
        static let segmentOrder = "statusLineSegmentOrder"
        static let segmentDisabled = "statusLineSegmentDisabled"
        static let liveStatusLineEnabled = "liveStatusLineEnabled"
        static let lastWorkingDirectory = "lastWorkingDirectory"
        static let defaultWorkingDirectory = "defaultWorkingDirectory"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        iconStyle = MenuBarIconStyle(rawValue: defaults.string(forKey: Keys.iconStyle) ?? "") ?? .text
        screenCoveragePercent = defaults.object(forKey: Keys.screenCoverage) as? Double ?? 58
        widthPercent = defaults.object(forKey: Keys.widthPercent) as? Double ?? 62
        amberThreshold = defaults.object(forKey: Keys.amberThreshold) as? Double ?? 60
        redThreshold = defaults.object(forKey: Keys.redThreshold) as? Double ?? 85
        animationSpeed = AnimationSpeed(rawValue: defaults.string(forKey: Keys.animationSpeed) ?? "") ?? .standard
        displayPreference = DisplayPreference(rawValue: defaults.string(forKey: Keys.displayPreference) ?? "") ?? .withPointer
        usagePollIntervalSeconds = defaults.object(forKey: Keys.pollInterval) as? Double ?? 60
        statusLineSegmentOrder = (defaults.stringArray(forKey: Keys.segmentOrder) ?? StatusLineSegmentID.allCases.map(\.rawValue))
            .compactMap(StatusLineSegmentID.init(rawValue:))
        statusLineSegmentDisabled = Set(
            (defaults.stringArray(forKey: Keys.segmentDisabled) ?? [StatusLineSegmentID.model, .ctx, .cost].map(\.rawValue))
                .compactMap(StatusLineSegmentID.init(rawValue:))
        )
        liveStatusLineEnabled = defaults.object(forKey: Keys.liveStatusLineEnabled) as? Bool ?? false
        // A pre-existing `$HOME` value here is discarded: earlier builds stored it, which pinned
        // the fallback to the one directory whose trust prompt never stops reappearing.
        let storedLast = defaults.string(forKey: Keys.lastWorkingDirectory)
        lastWorkingDirectory = storedLast == NSHomeDirectory() ? nil : storedLast
        defaultWorkingDirectory = defaults.string(forKey: Keys.defaultWorkingDirectory)
    }
}
