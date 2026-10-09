import Foundation
import RhythmCore
import WidgetKit

/// Writes the compact widget snapshot to the App Group container and asks WidgetKit to reload
/// only when the content actually changed, avoiding reload loops.
@MainActor
final class WidgetSnapshotStore {
    private var lastWrittenSignature: Data?

    /// `false` when the App Group is not provisioned; widgets then show a refresh state.
    var isAvailable: Bool { SharedStorage.snapshotURL != nil }

    func update(configuration: ScheduleConfiguration, engine: ScheduleEngine, accentKey: String, now: Date = .now) {
        guard let url = SharedStorage.snapshotURL else { return }
        let snapshot = WidgetSnapshot.make(engine: engine, configuration: configuration, now: now, accentKey: accentKey)

        // Compare everything except the generation time.
        var comparable = snapshot
        comparable.generatedAt = .distantPast
        let signature = try? WidgetSnapshotCodec.encode(comparable)
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        guard signature != lastWrittenSignature || !fileExists else { return }

        do {
            let data = try WidgetSnapshotCodec.encode(snapshot)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            lastWrittenSignature = signature
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
        } catch {
            // Widgets fall back to their "open Rhythm" state; the app is unaffected.
            lastWrittenSignature = nil
        }
    }

    func updateReminders(repository: ScheduleRepository, accentKey: String, now: Date = .now) {
        guard let url = SharedStorage.remindersSnapshotURL else { return }
        let allRules = repository.reminders()
        let items = allRules.compactMap { rule -> RemindersWidgetItem? in
            guard rule.isEnabled else { return nil }
            let periodTitle = rule.period?.title
            let formattedDueDate: String? = {
                if let date = rule.dueDate {
                    if let time = rule.dueTime {
                        return "\(date.key) at \(time)"
                    }
                    return date.key
                }
                return nil
            }()
            return RemindersWidgetItem(
                id: rule.id,
                title: rule.title,
                body: rule.body,
                periodTitle: periodTitle,
                statusRaw: rule.status.rawValue,
                priorityRaw: rule.priority.rawValue,
                formattedDueDate: formattedDueDate,
                snoozedUntilDate: rule.snoozedUntil
            )
        }
        let snapshot = RemindersWidgetSnapshot(generatedAt: now, accentKey: accentKey, items: items)
        do {
            let data = try RemindersWidgetSnapshotCodec.encode(snapshot)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.remindersWidgetKind)
        } catch {
            // Widgets fall back safely
        }
    }

    func removeSnapshot() {
        if let url = SharedStorage.snapshotURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let remindersURL = SharedStorage.remindersSnapshotURL {
            try? FileManager.default.removeItem(at: remindersURL)
        }
        lastWrittenSignature = nil
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.remindersWidgetKind)
    }
}
