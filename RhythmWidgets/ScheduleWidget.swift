import RhythmCore
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ScheduleEntry: TimelineEntry {
    enum Content {
        case status(WidgetStatus)
        /// The snapshot is missing, corrupt, from a newer version, or out of date.
        case needsRefresh
    }

    let date: Date
    let content: Content
    let accent: RhythmAccent
}

/// Builds entries at each period boundary from the app's snapshot. WidgetKit schedules
/// refreshes itself; countdown text is rendered by the system so no per-second reloads happen.
struct ScheduleTimelineProvider: TimelineProvider {
    private var calendar: Calendar { .autoupdatingCurrent }

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: .now, content: .status(Self.placeholderStatus), accent: .system)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        if context.isPreview, case .failure = loadSnapshot() {
            completion(placeholder(in: context))
            return
        }
        completion(entry(at: .now, from: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date.now
        let loaded = loadSnapshot()
        guard case .success(let snapshot) = loaded else {
            let entry = ScheduleEntry(date: now, content: .needsRefresh, accent: .system)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3600))))
            return
        }

        let transitions = snapshot.transitionDates(after: now, limit: 40)
        let dates = [now] + transitions
        let entries = dates.map { entry(at: $0, from: loaded) }
        let nextMidnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(6 * 3600)
        let reload = transitions.last.map { min($0.addingTimeInterval(60), nextMidnight) } ?? nextMidnight
        completion(Timeline(entries: entries, policy: .after(min(reload, snapshot.validThrough))))
    }

    private func loadSnapshot() -> Result<WidgetSnapshot, WidgetSnapshotError> {
        guard let url = SharedStorage.snapshotURL else { return .failure(.missing) }
        return WidgetSnapshotCodec.decode(try? Data(contentsOf: url))
    }

    private func entry(at date: Date, from loaded: Result<WidgetSnapshot, WidgetSnapshotError>) -> ScheduleEntry {
        guard case .success(let snapshot) = loaded else {
            return ScheduleEntry(date: date, content: .needsRefresh, accent: .system)
        }
        let status = snapshot.status(at: date, calendar: calendar)
        let accent = RhythmAccent(key: snapshot.accentKey)
        if status.isStale {
            return ScheduleEntry(date: date, content: .needsRefresh, accent: accent)
        }
        return ScheduleEntry(date: date, content: .status(status), accent: accent)
    }

    /// Shown only while WidgetKit renders a redacted placeholder or a gallery preview.
    static var placeholderStatus: WidgetStatus {
        let now = Date.now
        let current = WidgetSnapshot.Period(id: UUID(), title: "Biology", kind: .classPeriod, symbolName: "book.closed",
                                            colorKey: nil, startDate: now.addingTimeInterval(-20 * 60), endDate: now.addingTimeInterval(30 * 60))
        let next = WidgetSnapshot.Period(id: UUID(), title: "Lunch", kind: .lunch, symbolName: "fork.knife",
                                         colorKey: nil, startDate: now.addingTimeInterval(35 * 60), endDate: now.addingTimeInterval(70 * 60))
        return WidgetStatus(state: .inProgress, active: current, next: next, nextIsToday: true, todayPeriods: [current, next])
    }
}

// MARK: - Widget

struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStorage.widgetKind, provider: ScheduleTimelineProvider()) { entry in
            ScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("Current Period")
        .description("The current period, time remaining, and what’s next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        Group {
            switch entry.content {
            case .needsRefresh:
                RefreshNeededView()
            case .status(let status):
                if family == .systemMedium {
                    HStack(alignment: .top, spacing: 16) {
                        StatusSummaryView(status: status, now: entry.date)
                        DayListView(status: status, now: entry.date)
                    }
                } else {
                    StatusSummaryView(status: status, now: entry.date)
                }
            }
        }
        .tint(entry.accent.color)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(deepLink)
    }

    private var deepLink: URL {
        if case .status(let status) = entry.content, let active = status.active {
            return DeepLink.period(id: active.id, date: LocalDate(active.startDate, calendar: .autoupdatingCurrent)).url
        }
        return DeepLink.today(date: nil).url
    }
}

/// The primary status: current period with countdown, or what's next.
private struct StatusSummaryView: View {
    let status: WidgetStatus
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .textCase(.uppercase)

            switch status.state {
            case .inProgress:
                if let active = status.active {
                    Text(active.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(timerInterval: safeRange(now, active.endDate), countsDown: true)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    ProgressView(timerInterval: safeRange(active.startDate, active.endDate), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    Text("Ends \(active.endDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .upcoming, .freeTime:
                if let next = status.next {
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(timerInterval: safeRange(now, next.startDate), countsDown: true)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text("Starts \(next.startDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .dayComplete, .noSchool:
                Text(status.state == .noSchool ? "No school today" : "Done for today")
                    .font(.headline)
                Spacer(minLength: 0)
                if let next = status.next {
                    Text("Next: \(next.title)")
                        .font(.subheadline)
                        .lineLimit(2)
                    Text(next.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .scheduleNeeded:
                Text("Set up your schedule in Rhythm.")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch status.state {
        case .inProgress: "Now"
        case .upcoming: "Up Next"
        case .freeTime: "Free Time"
        case .dayComplete: "Today"
        case .noSchool: "Today"
        case .scheduleNeeded: "Rhythm"
        }
    }
}

/// The rest of today's periods for the medium widget.
private struct DayListView: View {
    let status: WidgetStatus
    let now: Date

    var body: some View {
        let remaining = status.todayPeriods.filter { $0.endDate > now }.prefix(4)
        VStack(alignment: .leading, spacing: 6) {
            if remaining.isEmpty {
                Text("No more periods today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(remaining)) { period in
                let isCurrent = period.startDate <= now && now < period.endDate
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isCurrent ? Color.accentColor : RhythmPalette.tint(kind: period.kind, colorKey: period.colorKey).opacity(0.6))
                        .frame(width: 3, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(period.title)
                            .font(.caption.weight(isCurrent ? .semibold : .regular))
                            .lineLimit(1)
                        Text(period.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct RefreshNeededView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Open Rhythm to update your schedule.")
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// `Text(timerInterval:)` and `ProgressView(timerInterval:)` require a non-inverted range.
func safeRange(_ start: Date, _ end: Date) -> ClosedRange<Date> {
    start <= end ? start...end : end...end
}
