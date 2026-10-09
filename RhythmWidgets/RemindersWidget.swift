import AppIntents
import RhythmCore
import SwiftUI
import WidgetKit

// MARK: - App Intents for Interactive Widget

struct CompleteReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Reminder"
    static let description = IntentDescription("Marks a reminder as done.")

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {
        self.reminderID = ""
    }

    init(id: UUID) {
        self.reminderID = id.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let url = SharedStorage.remindersSnapshotURL,
              let uuid = UUID(uuidString: reminderID) else { return .result() }

        SharedStorage.recordWidgetCompletion(id: uuid)
        if case .success(var snapshot) = RemindersWidgetSnapshotCodec.decode(try? Data(contentsOf: url)) {
            snapshot.items = snapshot.items.map { item in
                var updated = item
                if updated.id == uuid {
                    updated.statusRaw = "completed"
                }
                return updated
            }
            if let data = try? RemindersWidgetSnapshotCodec.encode(snapshot) {
                try? data.write(to: url, options: [.atomic])
            }
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.remindersWidgetKind)
        }
        return .result()
    }
}

struct SnoozeReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Snooze Reminder"
    static let description = IntentDescription("Snoozes a reminder for 15 minutes.")

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {
        self.reminderID = ""
    }

    init(id: UUID) {
        self.reminderID = id.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let url = SharedStorage.remindersSnapshotURL,
              let uuid = UUID(uuidString: reminderID) else { return .result() }

        let snoozeUntil = Date.now.addingTimeInterval(15 * 60)
        SharedStorage.recordWidgetSnooze(id: uuid, until: snoozeUntil)
        if case .success(var snapshot) = RemindersWidgetSnapshotCodec.decode(try? Data(contentsOf: url)) {
            snapshot.items = snapshot.items.map { item in
                var updated = item
                if updated.id == uuid {
                    updated.statusRaw = "snoozed"
                    updated.snoozedUntilDate = snoozeUntil
                }
                return updated
            }
            if let data = try? RemindersWidgetSnapshotCodec.encode(snapshot) {
                try? data.write(to: url, options: [.atomic])
            }
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.remindersWidgetKind)
        }
        return .result()
    }
}

// MARK: - Timeline Provider

struct RemindersEntry: TimelineEntry {
    let date: Date
    let snapshot: RemindersWidgetSnapshot?
    let accent: RhythmAccent
}

struct RemindersTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemindersEntry {
        RemindersEntry(date: .now, snapshot: placeholderSnapshot, accent: .system)
    }

    func getSnapshot(in context: Context, completion: @escaping (RemindersEntry) -> Void) {
        let loaded = loadSnapshot()
        completion(RemindersEntry(date: .now, snapshot: loaded ?? placeholderSnapshot, accent: .system))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemindersEntry>) -> Void) {
        let loaded = loadSnapshot()
        let entry = RemindersEntry(date: .now, snapshot: loaded, accent: .system)
        let nextUpdate = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadSnapshot() -> RemindersWidgetSnapshot? {
        guard let url = SharedStorage.remindersSnapshotURL else { return nil }
        if case .success(let snapshot) = RemindersWidgetSnapshotCodec.decode(try? Data(contentsOf: url)) {
            return snapshot
        }
        return nil
    }

    private var placeholderSnapshot: RemindersWidgetSnapshot {
        RemindersWidgetSnapshot(
            items: [
                RemindersWidgetItem(id: UUID(), title: "Submit Homework", periodTitle: "Period 1 Biology", priorityRaw: "high"),
                RemindersWidgetItem(id: UUID(), title: "Bring Permission Slip", periodTitle: "Homeroom", priorityRaw: "medium")
            ]
        )
    }
}

// MARK: - Widget View

struct RemindersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStorage.remindersWidgetKind, provider: RemindersTimelineProvider()) { entry in
            RemindersWidgetView(entry: entry)
        }
        .configurationDisplayName("Reminders")
        .description("View, complete, and snooze your active reminders.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RemindersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RemindersEntry

    var activeItems: [RemindersWidgetItem] {
        guard let snapshot = entry.snapshot else { return [] }
        return snapshot.items.filter { $0.statusRaw == "active" }
    }

    var body: some View {
        Group {
            if activeItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("No Active Reminders")
                        .font(.caption.weight(.bold))
                    Text("You're all caught up!")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch family {
                case .systemMedium:
                    MediumRemindersView(items: activeItems)
                default:
                    SmallRemindersView(items: activeItems)
                }
            }
        }
        .tint(entry.accent.color)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(DeepLink.reminders.url)
    }
}

private struct SmallRemindersView: View {
    let items: [RemindersWidgetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Reminders", systemImage: "bell.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                Spacer()
                Text("\(items.count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
            }

            if let first = items.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(first.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    if let period = first.periodTitle {
                        Text(period)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Button(intent: CompleteReminderIntent(id: first.id)) {
                            Label("Done", systemImage: "checkmark")
                                .font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button(intent: SnoozeReminderIntent(id: first.id)) {
                            Label("Snooze", systemImage: "clock")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumRemindersView: View {
    let items: [RemindersWidgetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Reminders", systemImage: "bell.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                Spacer()
                Text("\(items.count) active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.prefix(3)) { item in
                    HStack(spacing: 8) {
                        Button(intent: CompleteReminderIntent(id: item.id)) {
                            Image(systemName: "circle")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            if let period = item.periodTitle {
                                Text(period)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button(intent: SnoozeReminderIntent(id: item.id)) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
