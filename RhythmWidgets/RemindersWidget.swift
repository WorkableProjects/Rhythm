import AppIntents
import RhythmCore
import SwiftUI
import WidgetKit

// MARK: - Timeline

/// A reminder reduced to what a widget draws.
struct ReminderWidgetItem: Identifiable, Hashable {
    var id: UUID
    var title: String
    var dueLabel: String?
    /// For overdue checks at each entry date; all-day reminders resolve to the end of their day.
    var dueInstant: Date?
    var priority: ReminderPriority
    var isFlagged: Bool
    var tint: Color
}

struct RemindersEntry: TimelineEntry {
    enum Content {
        case reminders(title: String, symbol: String, tint: Color, items: [ReminderWidgetItem], total: Int)
        /// The App Group isn't available, so the extension can't see Rhythm's reminders.
        case unavailable
    }

    let date: Date
    let content: Content
}

/// Reads the shared reminders file. Completing a reminder from a widget button edits that file
/// and reloads this timeline, so the list always reflects the latest state.
struct RemindersTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = RemindersWidgetIntent

    func placeholder(in context: Context) -> RemindersEntry {
        let items = ["Turn in essay", "Study for quiz", "Bring gym clothes"].map {
            ReminderWidgetItem(id: UUID(), title: $0, dueLabel: "Today", dueInstant: nil, priority: .none, isFlagged: false, tint: .blue)
        }
        return RemindersEntry(date: .now, content: .reminders(title: "Today", symbol: "sun.max.fill", tint: .blue, items: items, total: 3))
    }

    func snapshot(for configuration: Intent, in context: Context) async -> RemindersEntry {
        if context.isPreview { return placeholder(in: context) }
        return entry(for: configuration, at: .now)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<RemindersEntry> {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let first = entry(for: configuration, at: now)

        // Re-render when a timed reminder becomes overdue and at midnight, when "Today" changes.
        var dates: [Date] = []
        if case .reminders(_, _, _, let items, _) = first.content {
            dates = items.compactMap(\.dueInstant).filter { $0 > now && calendar.isDate($0, inSameDayAs: now) }
        }
        let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(6 * 3600)
        let boundaries = Array(Set(dates)).sorted().prefix(12)
        let entries = [first] + boundaries.map { entry(for: configuration, at: $0) }
        return Timeline(entries: entries, policy: .after(midnight))
    }

    private func entry(for configuration: Intent, at date: Date) -> RemindersEntry {
        guard SharedStorage.isGroupAvailable else { return RemindersEntry(date: date, content: .unavailable) }
        let library = ReminderActions.store.load()
        let calendar = Calendar.autoupdatingCurrent
        let today = LocalDate(date, calendar: calendar)

        let filter: ReminderFilter
        let title: String
        let symbol: String
        let tint: Color
        if let selected = configuration.list, let list = library.list(selected.id) {
            filter = .list(list.id)
            title = list.name
            symbol = list.symbolName
            tint = RhythmPalette.color(forKey: list.colorKey) ?? .blue
        } else {
            filter = .today
            title = "Today"
            symbol = "sun.max.fill"
            tint = .blue
        }

        let reminders = library.items(for: filter, today: today, calendar: calendar)
        let items = reminders.prefix(10).map { reminder in
            ReminderWidgetItem(
                id: reminder.id,
                title: reminder.trimmedTitle,
                dueLabel: Self.dueLabel(reminder, today: today, calendar: calendar),
                dueInstant: reminder.dueInstant(calendar: calendar),
                priority: reminder.priority,
                isFlagged: reminder.isFlagged,
                tint: RhythmPalette.color(forKey: library.list(reminder.listID)?.colorKey) ?? .blue)
        }
        return RemindersEntry(date: date, content: .reminders(title: title, symbol: symbol, tint: tint, items: Array(items), total: reminders.count))
    }

    private static func dueLabel(_ reminder: NativeReminder, today: LocalDate, calendar: Calendar) -> String? {
        guard let date = reminder.dueDate else { return nil }
        let time = reminder.dueTime?.formatted(calendar: calendar)
        if date == today { return time ?? "All day" }
        if date < today { return time.map { "Overdue · \($0)" } ?? "Overdue" }
        let day = date.formatted(in: calendar, style: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return time.map { "\(day), \($0)" } ?? day
    }
}

// MARK: - Widget

struct RemindersWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedStorage.remindersWidgetKind, intent: RemindersWidgetIntent.self,
                               provider: RemindersTimelineProvider()) { entry in
            RemindersWidgetView(entry: entry)
        }
        .configurationDisplayName("Reminders")
        .description("See what’s due and check reminders off right from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct RemindersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RemindersEntry

    var body: some View {
        Group {
            switch entry.content {
            case .unavailable:
                UnavailableView()
            case .reminders(let title, let symbol, let tint, let items, let total):
                switch family {
                case .accessoryInline:
                    Text(total == 0 ? "No reminders due" : "\(total) reminder\(total == 1 ? "" : "s") due")
                case .accessoryCircular:
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 0) {
                            Image(systemName: "checklist").font(.caption)
                            Text("\(total)").font(.title3.weight(.semibold)).minimumScaleFactor(0.6)
                        }
                    }
                    .accessibilityLabel("\(total) reminders due")
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        Label(title, systemImage: symbol).font(.caption.weight(.semibold))
                        if items.isEmpty {
                            Text("All done").font(.caption)
                        }
                        ForEach(items.prefix(2)) { item in
                            Text("• \(item.title)").font(.caption).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                default:
                    ReminderListLayout(title: title, symbol: symbol, tint: tint, items: items, total: total,
                                       now: entry.date, family: family)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(DeepLink.reminders.url)
    }
}

/// Header plus checkable rows, sized to the widget family.
private struct ReminderListLayout: View {
    let title: String
    let symbol: String
    let tint: Color
    let items: [ReminderWidgetItem]
    let total: Int
    let now: Date
    let family: WidgetFamily

    private var rowLimit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 3
        default: 8
        }
    }

    private var shown: [ReminderWidgetItem] { Array(items.prefix(rowLimit)) }
    private var showsDetail: Bool { family != .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(total)")
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
                Link(destination: DeepLink.newReminder.url) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                .accessibilityLabel("New reminder")
            }

            if shown.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(tint)
                    Text("All done").font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(shown) { item in
                    ReminderWidgetRow(item: item, now: now, showsDetail: showsDetail)
                }
                if total > shown.count {
                    Text("+\(total - shown.count) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ReminderWidgetRow: View {
    let item: ReminderWidgetItem
    let now: Date
    let showsDetail: Bool

    private var isOverdue: Bool { item.dueInstant.map { $0 < now } ?? false }

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteReminderIntent(reminderID: item.id)) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(item.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")

            Link(destination: DeepLink.reminder(id: item.id).url) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        if item.priority != .none {
                            Text(item.priority.marks).font(.caption.weight(.bold)).foregroundStyle(item.tint)
                        }
                        Text(item.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if item.isFlagged {
                            Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    if showsDetail, let label = item.dueLabel {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct UnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Open Rhythm to set up Reminders.")
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Add Reminder widget

/// A one-tap shortcut that opens Rhythm to a new reminder.
struct AddReminderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStorage.addReminderWidgetKind, provider: AddReminderProvider()) { _ in
            AddReminderView()
        }
        .configurationDisplayName("New Reminder")
        .description("Jump straight into adding a reminder.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct AddReminderEntry: TimelineEntry {
    let date: Date
}

struct AddReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> AddReminderEntry { AddReminderEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (AddReminderEntry) -> Void) { completion(AddReminderEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AddReminderEntry>) -> Void) {
        completion(Timeline(entries: [AddReminderEntry(date: .now)], policy: .never))
    }
}

private struct AddReminderView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "plus").font(.title2.weight(.semibold))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("New Reminder")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(DeepLink.newReminder.url)
        .accessibilityLabel("New reminder")
    }
}
