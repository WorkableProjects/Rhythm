import Foundation
import Observation
import SwiftUI

/// Appearance options. `system` (the default) follows the device setting.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Small user preferences stored in `UserDefaults`. Schedule data lives in SwiftData; these are
/// device-level settings that do not need relationships or export.
@MainActor
@Observable
final class RhythmPreferences {
    private enum Key {
        static let appearance = "appearance"
        static let accent = "accent"
        static let liveActivities = "liveActivitiesEnabled"
        static let reminders = "remindersEnabled"
        static let onboarding = "hasCompletedOnboarding"
        static let liveActivityExplained = "hasSeenLiveActivityExplanation"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var accent: RhythmAccent {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }

    /// Rhythm's own switch for Live Activities. iOS settings can still disable them.
    var liveActivitiesEnabled: Bool {
        didSet { defaults.set(liveActivitiesEnabled, forKey: Key.liveActivities) }
    }

    /// Master switch for reminder notifications. Individual rules keep their own state.
    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Key.reminders) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
    }

    var hasSeenLiveActivityExplanation: Bool {
        didSet { defaults.set(hasSeenLiveActivityExplanation, forKey: Key.liveActivityExplained) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        accent = RhythmAccent(key: defaults.string(forKey: Key.accent))
        // Live Activities are off until the user opts in, so the feature can be explained first.
        liveActivitiesEnabled = defaults.object(forKey: Key.liveActivities) as? Bool ?? false
        remindersEnabled = defaults.object(forKey: Key.reminders) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        hasSeenLiveActivityExplanation = defaults.bool(forKey: Key.liveActivityExplained)
    }

    /// Restores defaults (used by "Delete All Data").
    func reset() {
        appearance = .system
        accent = .system
        liveActivitiesEnabled = false
        remindersEnabled = true
        hasCompletedOnboarding = false
        hasSeenLiveActivityExplanation = false
    }
}
