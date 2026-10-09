import Foundation

/// Deterministic schedule resolution.
///
/// The engine has no clock, database, or UI dependencies: callers pass `now`, the calendar
/// (which carries the time zone), and a `ScheduleConfiguration`. Given the same inputs it
/// always produces the same output.
public struct ScheduleEngine: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    // MARK: Day resolution

    /// Resolves the schedule for a calendar date.
    ///
    /// Priority: a no-school override, then a custom-schedule override, then the weekday's
    /// template. Periods are validated; invalid or overlapping records are skipped and reported
    /// in `issues` so a single bad record cannot crash the app or create two active periods.
    public func resolveDay(_ date: LocalDate, configuration: ScheduleConfiguration) -> ResolvedDay {
        let source: DaySource
        let definitions: [PeriodDefinition]

        if let override = configuration.overrides[date] {
            switch override.kind {
            case .noSchool:
                return ResolvedDay(
                    date: date,
                    source: .noSchoolOverride(id: override.id, title: override.title),
                    periods: [],
                    issues: []
                )
            case .customSchedule:
                source = .customOverride(id: override.id, title: override.title, templateID: override.templateID)
                if !override.periods.isEmpty {
                    definitions = override.periods
                } else if let templateID = override.templateID, let template = configuration.templates[templateID] {
                    definitions = template.periods
                } else {
                    definitions = []
                }
            }
        } else if !configuration.hasAnySchedule {
            return ResolvedDay(date: date, source: .noScheduleConfigured, periods: [], issues: [])
        } else {
            let weekday = date.weekday(in: calendar)
            guard let templateID = configuration.weekdayAssignments[weekday],
                  let template = configuration.templates[templateID] else {
                return ResolvedDay(date: date, source: .unassigned(weekday), periods: [], issues: [])
            }
            source = .template(id: template.id, name: template.name)
            definitions = template.periods
        }

        let (periods, issues) = buildPeriods(definitions, on: date)
        return ResolvedDay(date: date, source: source, periods: periods, issues: issues)
    }

    /// Converts definitions to absolute periods, skipping disabled, invalid, and overlapping ones.
    private func buildPeriods(_ definitions: [PeriodDefinition], on date: LocalDate) -> ([ResolvedPeriod], [ScheduleIssue]) {
        let issues = ScheduleValidator.validate(periods: definitions)
        let sorted = definitions
            .filter { $0.isEnabled && $0.start.isWithinDay && $0.end.isWithinDay && $0.end > $0.start }
            .sorted(by: ScheduleValidator.chronological)

        var result: [ResolvedPeriod] = []
        for definition in sorted {
            guard let start = date.date(at: definition.start, in: calendar),
                  let end = date.date(at: definition.end, in: calendar),
                  end > start else { continue }
            // Keep the earlier period when two overlap; the validator already reported it.
            if let last = result.last, start < last.endDate { continue }
            result.append(ResolvedPeriod(definition: definition, startDate: start, endDate: end))
        }
        return (result, issues)
    }

    // MARK: Live snapshot

    /// The live status at `now`.
    public func snapshot(at now: Date, configuration: ScheduleConfiguration) -> ScheduleSnapshot {
        let day = resolveDay(LocalDate(now, calendar: calendar), configuration: configuration)
        return snapshot(at: now, day: day)
    }

    /// The live status at `now` for an already-resolved day.
    public func snapshot(at now: Date, day: ResolvedDay) -> ScheduleSnapshot {
        switch day.source {
        case .noScheduleConfigured:
            return ScheduleSnapshot(now: now, day: day, state: .scheduleNeeded, activePeriod: nil, nextPeriod: nil, previousPeriod: nil)
        case .noSchoolOverride, .unassigned:
            return ScheduleSnapshot(now: now, day: day, state: .noSchool, activePeriod: nil, nextPeriod: nil, previousPeriod: nil)
        case .template, .customOverride:
            break
        }

        guard !day.periods.isEmpty else {
            return ScheduleSnapshot(now: now, day: day, state: .noSchool, activePeriod: nil, nextPeriod: nil, previousPeriod: nil)
        }

        let activeIndex = day.periods.firstIndex { $0.contains(now) }
        let nextIndex = day.periods.firstIndex { $0.startDate > now }
        let previousIndex = day.periods.lastIndex { $0.endDate <= now }

        let active = activeIndex.map { day.periods[$0] }
        let next = nextIndex.map { day.periods[$0] }
        let previous = previousIndex.map { day.periods[$0] }

        let state: DayState
        if active != nil {
            state = .inProgress
        } else if next != nil {
            state = previous == nil ? .upcoming : .freeTime
        } else {
            state = .dayComplete
        }

        return ScheduleSnapshot(now: now, day: day, state: state, activePeriod: active, nextPeriod: next, previousPeriod: previous)
    }

    /// Resolves `count` consecutive days starting at `start`.
    public func resolveDays(from start: LocalDate, count: Int, configuration: ScheduleConfiguration) -> [ResolvedDay] {
        (0..<max(0, count)).map { resolveDay(start.adding(days: $0, calendar: calendar), configuration: configuration) }
    }

    /// The next period that starts after `now`, searching up to `searchDays` days ahead.
    /// Useful when today is finished and the user asks "what's next?".
    public func nextPeriod(after now: Date, configuration: ScheduleConfiguration, searchDays: Int = 14) -> (day: ResolvedDay, period: ResolvedPeriod)? {
        let today = LocalDate(now, calendar: calendar)
        for day in resolveDays(from: today, count: searchDays, configuration: configuration) {
            if let period = day.periods.first(where: { $0.startDate > now }) {
                return (day, period)
            }
        }
        return nil
    }
}
