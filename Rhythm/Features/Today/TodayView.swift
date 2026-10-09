import RhythmCore
import SwiftData
import SwiftUI

/// The home screen: live status for today, the day's timeline, relevant reminders, and
/// favourite Quicklinks. It can also show another date for review.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var router = model.router
        NavigationStack {
            ScrollView {
                // Minute-level refresh for timeline row states; the live module ticks every second.
                TimelineView(.everyMinute) { context in
                    TodayContent(now: model.now(context.date))
                }
                .padding(.horizontal, RhythmSpacing.lg)
                .padding(.bottom, RhythmSpacing.xxxl)
            }
            .background(RhythmSurface.background)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .sheet(item: $router.presentedPeriod) { presentation in
                PeriodDetailView(presentation: presentation)
            }
        }
    }
}

/// The scrollable Today content for a given instant.
private struct TodayContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let now: Date

    private var displayedDate: LocalDate { model.router.todayDate ?? LocalDate(now, calendar: model.calendar) }
    private var isToday: Bool { displayedDate == LocalDate(now, calendar: model.calendar) }

    var body: some View {
        let day = model.resolvedDay(displayedDate)
        VStack(alignment: .leading, spacing: RhythmSpacing.xl) {
            DateNavigator(date: displayedDate, isToday: isToday, source: day.source)

            if model.hasSampleData {
                SampleBanner()
            }

            switch day.source {
            case .noScheduleConfigured:
                ScheduleNeededView()
            case .noSchoolOverride, .unassigned:
                NoSchoolView(source: day.source, date: displayedDate)
            case .template, .customOverride:
                if day.periods.isEmpty {
                    NoSchoolView(source: day.source, date: displayedDate)
                } else {
                    if isToday {
                        LiveStatusModule()
                    } else {
                        DaySummaryView(day: day)
                    }
                    TodayRemindersView(day: day, now: now)
                    VStack(alignment: .leading, spacing: RhythmSpacing.sm) {
                        Text(isToday ? "Today’s Schedule" : "Schedule")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        DayTimelineView(day: day, now: now)
                    }
                }
            }

            if !day.issues.isEmpty {
                ScheduleIssuesNote(issues: day.issues)
            }

            FavoriteQuicklinksView()
        }
        .padding(.top, RhythmSpacing.sm)
        .animation(RhythmMotion.animation(RhythmMotion.stateChange, reduceMotion: reduceMotion), value: displayedDate)
    }
}

/// Previous/next day buttons around a compact date picker, plus a "Today" shortcut.
private struct DateNavigator: View {
    @Environment(AppModel.self) private var model
    let date: LocalDate
    let isToday: Bool
    let source: DaySource

    var body: some View {
        let calendar = model.calendar
        VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
            HStack(spacing: RhythmSpacing.sm) {
                Button {
                    model.router.todayDate = date.adding(days: -1, calendar: calendar)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: RhythmLayout.minimumTouchTarget, height: RhythmLayout.minimumTouchTarget)
                }
                .accessibilityLabel("Previous day")

                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { date.noon(in: calendar) },
                        set: { model.router.todayDate = LocalDate($0, calendar: calendar) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Button {
                    model.router.todayDate = date.adding(days: 1, calendar: calendar)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: RhythmLayout.minimumTouchTarget, height: RhythmLayout.minimumTouchTarget)
                }
                .accessibilityLabel("Next day")

                Spacer(minLength: 0)

                if !isToday {
                    Button("Today") { model.router.todayDate = nil }
                        .buttonStyle(.glass)
                        .accessibilityHint("Returns to today’s live schedule")
                }
            }
            if let label = scheduleLabel {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Shown only when it helps: a special day, or when more than one template exists.
    private var scheduleLabel: String? {
        switch source {
        case .template(_, let name):
            return model.configuration.templates.count > 1 ? name : nil
        case .customOverride(_, let title, _):
            return title.isEmpty ? "Special Schedule" : title
        default:
            return nil
        }
    }
}

/// A calm note about a clearly labelled sample timetable, with a one-tap removal.
private struct SampleBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RhythmSpacing.md) {
            Image(systemName: "sparkles").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                Text("You’re exploring a sample schedule.")
                    .font(.subheadline.weight(.semibold))
                Text("Edit it in Schedule, or remove it to start fresh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Remove", role: .destructive) { model.removeSample() }
                .font(.subheadline)
                .accessibilityIdentifier("removeSampleButton")
        }
        .padding(RhythmSpacing.lg)
        .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
    }
}

/// Shown when no schedule exists at all.
private struct ScheduleNeededView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Set Up Your Schedule", systemImage: "calendar.badge.plus")
        } description: {
            Text("Add your periods once and Rhythm will show what’s happening now and what’s next.")
        } actions: {
            Button("Create Schedule") {
                model.router.selectedTab = .schedule
                model.router.isCreatingTemplate = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("createScheduleButton")
            Button("Explore a Sample") { model.insertSample() }
        }
        .accessibilityIdentifier("scheduleNeeded")
    }
}

/// Shown on days without school, explaining why and offering a fix where relevant.
private struct NoSchoolView: View {
    @Environment(AppModel.self) private var model
    let source: DaySource
    let date: LocalDate

    var body: some View {
        VStack(alignment: .leading, spacing: RhythmSpacing.md) {
            Label(title, systemImage: "sun.max")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
            if let next = model.engine.nextPeriod(after: model.now(), configuration: model.configuration) {
                Text("Next: \(next.period.title), \(next.day.date.formatted(in: model.calendar, style: .dateTime.weekday(.wide))) at \(next.period.startDate.shortTime)")
                    .font(.subheadline)
            }
            if case .unassigned = source {
                Button("Assign a Schedule") {
                    model.router.scheduleDate = date
                    model.router.selectedTab = .schedule
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RhythmSpacing.xl)
        .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.module, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("noSchool")
    }

    private var title: String {
        if case .noSchoolOverride(_, let title) = source, !title.isEmpty { return title }
        return "No School"
    }

    private var message: String {
        switch source {
        case .unassigned(let weekday):
            "No schedule is assigned to \(weekday.name(in: model.calendar))."
        case .noSchoolOverride:
            "This date is marked as no school."
        default:
            "There are no periods on this schedule."
        }
    }
}

/// A non-live summary used when reviewing another date.
private struct DaySummaryView: View {
    @Environment(AppModel.self) private var model
    let day: ResolvedDay

    var body: some View {
        if let first = day.periods.first, let last = day.periods.last {
            VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
                Text("\(day.periods.count) periods")
                    .font(.title2.weight(.semibold))
                Text("\(first.startDate.shortTime) – \(last.endDate.shortTime)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RhythmSpacing.xl)
            .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.module, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Recoverable data problems (e.g. overlapping imported periods) shown without blocking.
private struct ScheduleIssuesNote: View {
    let issues: [ScheduleIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: RhythmSpacing.xs) {
            Label("Some periods were skipped", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            ForEach(issues.prefix(3)) { issue in
                Text(issue.message).font(.footnote).foregroundStyle(.secondary)
            }
            Text("Fix them in Schedule.").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(RhythmSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
