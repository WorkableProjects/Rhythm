import Foundation

/// A continuous stretch of the school day: a period, a passing period between two periods, or
/// the lead-up to the first period. Live Activities and widgets describe the day as segments so
/// every moment from shortly before the first bell to the last bell has something to show.
public struct ScheduleSegment: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// A period is in progress.
        case period
        /// A short gap between two periods (at most `ScheduleSegments.passingThreshold`).
        case passing
        /// A longer gap between two periods.
        case freeTime
        /// Before the first period of the day.
        case beforeSchool
    }

    public var kind: Kind
    /// The period this segment is about: the active period, or the period being waited for.
    public var period: ResolvedPeriod
    public var startDate: Date
    public var endDate: Date

    public init(kind: Kind, period: ResolvedPeriod, startDate: Date, endDate: Date) {
        self.kind = kind
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Half-open containment, like periods.
    public func contains(_ instant: Date) -> Bool {
        startDate <= instant && instant < endDate
    }
}

/// Splits resolved days into segments and decides what a Live Activity should show.
public enum ScheduleSegments {
    /// Gaps up to this long are passing periods ("4:12 until Period 2"); longer gaps are free time.
    public static let passingThreshold: TimeInterval = 15 * 60
    /// How long before the first period a day's Live Activity appears.
    public static let beforeSchoolLeadTime: TimeInterval = 60 * 60

    /// Whether a gap between two periods counts as a passing period.
    public static func isPassing(gap: TimeInterval) -> Bool {
        gap > 0 && gap <= passingThreshold
    }

    /// The day's segments in order, from `beforeSchoolLeadTime` before the first period to the end
    /// of the last period.
    public static func segments(for day: ResolvedDay) -> [ScheduleSegment] {
        guard let first = day.periods.first else { return [] }
        var result = [ScheduleSegment(kind: .beforeSchool, period: first,
                                      startDate: first.startDate.addingTimeInterval(-beforeSchoolLeadTime),
                                      endDate: first.startDate)]
        for (index, period) in day.periods.enumerated() {
            if index > 0 {
                let previous = day.periods[index - 1]
                let gap = period.startDate.timeIntervalSince(previous.endDate)
                if gap > 0 {
                    result.append(ScheduleSegment(kind: isPassing(gap: gap) ? .passing : .freeTime, period: period,
                                                  startDate: previous.endDate, endDate: period.startDate))
                }
            }
            result.append(ScheduleSegment(kind: .period, period: period, startDate: period.startDate, endDate: period.endDate))
        }
        return result
    }

    /// What a Live Activity shows at `now`: the current segment and the one after it. The second
    /// lets the Live Activity stay correct for one more boundary without the app running (the
    /// system re-renders it when the first segment ends).
    public static func liveFrame(at now: Date, day: ResolvedDay) -> LiveFrame? {
        let all = segments(for: day)
        guard let index = all.firstIndex(where: { $0.contains(now) }) else { return nil }
        let following = all.indices.contains(index + 1) ? all[index + 1] : nil
        return LiveFrame(date: day.date, current: all[index], following: following)
    }

    /// The first frame of the next school day after `now` whose before-school segment starts in
    /// the future, searching up to `searchDays` days. Used to schedule a Live Activity that starts
    /// automatically before the first bell.
    public static func nextAutomaticStart(after now: Date, engine: ScheduleEngine,
                                          configuration: ScheduleConfiguration, searchDays: Int = 14) -> LiveFrame? {
        let today = LocalDate(now, calendar: engine.calendar)
        for day in engine.resolveDays(from: today, count: searchDays, configuration: configuration) {
            let all = segments(for: day)
            guard let first = all.first, first.startDate > now else { continue }
            return LiveFrame(date: day.date, current: first, following: all.count > 1 ? all[1] : nil)
        }
        return nil
    }
}

/// The current segment plus the next one.
public struct LiveFrame: Hashable, Sendable {
    public var date: LocalDate
    public var current: ScheduleSegment
    public var following: ScheduleSegment?

    public init(date: LocalDate, current: ScheduleSegment, following: ScheduleSegment?) {
        self.date = date
        self.current = current
        self.following = following
    }
}

extension ScheduleSnapshot {
    /// `true` during a short gap between two periods.
    public var isPassingPeriod: Bool {
        guard state == .freeTime, let previous = previousPeriod, let next = nextPeriod else { return false }
        return ScheduleSegments.isPassing(gap: next.startDate.timeIntervalSince(previous.endDate))
    }

    /// The label for the current state, distinguishing passing periods from longer free time.
    public var stateLabel: String {
        isPassingPeriod ? "Passing Period" : state.displayName
    }
}
