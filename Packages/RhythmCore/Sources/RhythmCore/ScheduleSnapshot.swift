import Foundation

/// A period placed on a real day with absolute start and end instants.
public struct ResolvedPeriod: Identifiable, Hashable, Sendable {
    /// The id of the underlying `PeriodDefinition`.
    public var id: UUID
    public var title: String
    public var kind: PeriodKind
    public var detail: String?
    public var colorKey: String?
    public var symbolName: String
    public var startTime: ClockTime
    public var endTime: ClockTime
    public var startDate: Date
    public var endDate: Date

    public init(definition: PeriodDefinition, startDate: Date, endDate: Date) {
        self.id = definition.id
        self.title = definition.title
        self.kind = definition.kind
        self.detail = definition.detail
        self.colorKey = definition.colorKey
        self.symbolName = definition.resolvedSymbolName
        self.startTime = definition.start
        self.endTime = definition.end
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Half-open containment: active from `startDate` up to, but not including, `endDate`.
    public func contains(_ instant: Date) -> Bool {
        startDate <= instant && instant < endDate
    }

    public var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    /// Time left until the end, never negative.
    public func remaining(at now: Date) -> TimeInterval {
        max(0, endDate.timeIntervalSince(now))
    }

    /// Elapsed fraction clamped to `0...1`.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(startDate) / duration))
    }
}

/// Where a day's schedule came from.
public enum DaySource: Hashable, Sendable {
    /// No templates exist at all.
    case noScheduleConfigured
    /// Templates exist but none is assigned to this weekday.
    case unassigned(Weekday)
    /// The ordinary weekday template.
    case template(id: UUID, name: String)
    /// A no-school override for this date.
    case noSchoolOverride(id: UUID, title: String)
    /// A custom-schedule override for this date (optionally based on a template).
    case customOverride(id: UUID, title: String, templateID: UUID?)

    public var templateID: UUID? {
        switch self {
        case .template(let id, _): id
        case .customOverride(_, _, let templateID): templateID
        default: nil
        }
    }

    public var overrideID: UUID? {
        switch self {
        case .noSchoolOverride(let id, _), .customOverride(let id, _, _): id
        default: nil
        }
    }
}

/// A fully resolved calendar day.
public struct ResolvedDay: Hashable, Sendable {
    public var date: LocalDate
    public var source: DaySource
    /// Valid, enabled, non-overlapping periods in chronological order.
    public var periods: [ResolvedPeriod]
    /// Problems found in stored data. Invalid records are skipped, never crash the app.
    public var issues: [ScheduleIssue]

    public init(date: LocalDate, source: DaySource, periods: [ResolvedPeriod], issues: [ScheduleIssue]) {
        self.date = date
        self.source = source
        self.periods = periods
        self.issues = issues
    }

    public var isSchoolDay: Bool {
        switch source {
        case .template, .customOverride: !periods.isEmpty
        default: false
        }
    }
}

/// The live status shown by Today, widgets, and the Live Activity.
public enum DayState: String, Hashable, Sendable, Codable {
    /// The user has not created any schedule.
    case scheduleNeeded
    /// No school today: an override, an unassigned weekday, or an empty template.
    case noSchool
    /// Before the first period of the day.
    case upcoming
    /// A period is active.
    case inProgress
    /// Between two periods.
    case freeTime
    /// All periods for the day have ended.
    case dayComplete

    public var displayName: String {
        switch self {
        case .scheduleNeeded: "Schedule Needed"
        case .noSchool: "No School"
        case .upcoming: "Up Next"
        case .inProgress: "In Progress"
        case .freeTime: "Free Time"
        case .dayComplete: "Day Complete"
        }
    }
}

/// A point-in-time view of the schedule. Remaining time and progress are derived from `now`
/// on demand; nothing here is a ticking counter.
public struct ScheduleSnapshot: Hashable, Sendable {
    public var now: Date
    public var day: ResolvedDay
    public var state: DayState
    public var activePeriod: ResolvedPeriod?
    public var nextPeriod: ResolvedPeriod?
    public var previousPeriod: ResolvedPeriod?

    public init(
        now: Date,
        day: ResolvedDay,
        state: DayState,
        activePeriod: ResolvedPeriod?,
        nextPeriod: ResolvedPeriod?,
        previousPeriod: ResolvedPeriod?
    ) {
        self.now = now
        self.day = day
        self.state = state
        self.activePeriod = activePeriod
        self.nextPeriod = nextPeriod
        self.previousPeriod = previousPeriod
    }

    /// The instant the current countdown targets: the active period's end, or the next start.
    public var countdownTarget: Date? {
        activePeriod?.endDate ?? nextPeriod?.startDate
    }

    /// Seconds until `countdownTarget`, never negative.
    public var remaining: TimeInterval? {
        countdownTarget.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Progress through the active period, or through the gap before the next period when
    /// in free time. `nil` when there is nothing meaningful to measure.
    public var progress: Double? {
        if let activePeriod { return activePeriod.progress(at: now) }
        if state == .freeTime, let previousPeriod, let nextPeriod {
            let gap = nextPeriod.startDate.timeIntervalSince(previousPeriod.endDate)
            guard gap > 0 else { return nil }
            return min(1, max(0, now.timeIntervalSince(previousPeriod.endDate) / gap))
        }
        return nil
    }

    /// The next instant at which `state` or the active/next period changes.
    public var nextTransition: Date? {
        if let activePeriod { return activePeriod.endDate }
        return nextPeriod?.startDate
    }
}
