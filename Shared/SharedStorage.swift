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
}
