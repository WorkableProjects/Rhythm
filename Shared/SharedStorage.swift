import Foundation

/// Locates data shared between the app and the widget extension through an App Group.
///
/// The App Group identifier comes from the `RhythmAppGroupIdentifier` Info.plist key, which is
/// set from the `RHYTHM_APP_GROUP` build setting so it always matches the entitlements. If the
/// App Group is not provisioned for the signing team, `snapshotURL` is `nil`: the app keeps
/// working and widgets show a "open Rhythm" state instead of crashing.
enum SharedStorage {
    static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RhythmAppGroupIdentifier") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    static var containerURL: URL? {
        guard let identifier = appGroupIdentifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// The widget snapshot file, or `nil` when the App Group is unavailable.
    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("WidgetSnapshot.json", isDirectory: false)
    }

    static let widgetKind = "RhythmScheduleWidget"
    static let remindersWidgetKind = "RhythmRemindersWidget"
    static let addReminderWidgetKind = "RhythmAddReminderWidget"

    /// Whether the App Group is provisioned. Without it, the widget extension can't see the
    /// app's reminders.
    static var isGroupAvailable: Bool { containerURL != nil }

    /// Where native reminders live: the App Group container when available (so widgets and App
    /// Intents see the same data), otherwise the app's own Application Support folder.
    static var remindersURL: URL {
        if let container = containerURL {
            return container.appendingPathComponent("Reminders.json", isDirectory: false)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Rhythm/Reminders.json", isDirectory: false)
    }
}
