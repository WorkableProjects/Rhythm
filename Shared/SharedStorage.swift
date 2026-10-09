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

    static var remindersSnapshotURL: URL? {
        containerURL?.appendingPathComponent("RemindersWidgetSnapshot.json", isDirectory: false)
    }

    static let widgetKind = "RhythmScheduleWidget"
    static let remindersWidgetKind = "RhythmRemindersWidget"

    static var sharedDefaults: UserDefaults? {
        guard let identifier = appGroupIdentifier else { return nil }
        return UserDefaults(suiteName: identifier)
    }

    static let pendingCompletedIDsKey = "RhythmPendingCompletedReminderIDs"
    static let pendingSnoozedIDsKey = "RhythmPendingSnoozedReminderIDs"

    static func recordWidgetCompletion(id: UUID) {
        let defaults = sharedDefaults ?? UserDefaults.standard
        var list = defaults.stringArray(forKey: pendingCompletedIDsKey) ?? []
        list.append(id.uuidString)
        defaults.set(list, forKey: pendingCompletedIDsKey)
    }

    static func recordWidgetSnooze(id: UUID, until date: Date) {
        let defaults = sharedDefaults ?? UserDefaults.standard
        var dict = defaults.dictionary(forKey: pendingSnoozedIDsKey) as? [String: Double] ?? [:]
        dict[id.uuidString] = date.timeIntervalSince1970
        defaults.set(dict, forKey: pendingSnoozedIDsKey)
    }

    @MainActor
    static func consumePendingWidgetActions(repository: ScheduleRepository) {
        let defaults = sharedDefaults ?? UserDefaults.standard
        let completedList = defaults.stringArray(forKey: pendingCompletedIDsKey) ?? []
        let snoozedDict = defaults.dictionary(forKey: pendingSnoozedIDsKey) as? [String: Double] ?? [:]

        guard !completedList.isEmpty || !snoozedDict.isEmpty else { return }

        let rules = repository.reminders()

        for idStr in completedList {
            if let uuid = UUID(uuidString: idStr), let rule = rules.first(where: { $0.id == uuid }) {
                repository.setReminderStatus(rule, status: .completed)
            }
        }

        for (idStr, timestamp) in snoozedDict {
            if let uuid = UUID(uuidString: idStr), let rule = rules.first(where: { $0.id == uuid }) {
                let snoozedUntil = Date(timeIntervalSince1970: timestamp)
                repository.setReminderStatus(rule, status: .snoozed, snoozedUntil: snoozedUntil)
            }
        }

        try? repository.save()

        defaults.removeObject(forKey: pendingCompletedIDsKey)
        defaults.removeObject(forKey: pendingSnoozedIDsKey)
    }
}
