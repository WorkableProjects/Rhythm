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

    func removeSnapshot() {
        guard let url = SharedStorage.snapshotURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastWrittenSignature = nil
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
    }
}
