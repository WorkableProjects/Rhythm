import Foundation

/// The compact, versioned payload the app writes for its widget extension.
///
/// It contains only display-safe data (titles, categories, symbols, colour keys, and times) for a
/// short horizon. Room/teacher details, reminders, and Quicklinks are deliberately excluded.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public struct Period: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var kind: PeriodKind
        public var symbolName: String
        public var colorKey: String?
        public var startDate: Date
        public var endDate: Date

        public init(id: UUID, title: String, kind: PeriodKind, symbolName: String, colorKey: String?, startDate: Date, endDate: Date) {
            self.id = id
            self.title = title
            self.kind = kind
            self.symbolName = symbolName
            self.colorKey = colorKey
            self.startDate = startDate
            self.endDate = endDate
        }

        public init(_ period: ResolvedPeriod) {
            self.init(id: period.id, title: period.title, kind: period.kind, symbolName: period.symbolName,
                      colorKey: period.colorKey, startDate: period.startDate, endDate: period.endDate)
        }
    }

    public struct Day: Codable, Hashable, Sendable {
        public var date: LocalDate
        public var isSchoolDay: Bool
        public var periods: [Period]

        public init(date: LocalDate, isSchoolDay: Bool, periods: [Period]) {
            self.date = date
            self.isSchoolDay = isSchoolDay
            self.periods = periods
        }
    }

    public var version: Int
    public var generatedAt: Date
    /// After this instant the snapshot no longer covers "now" and must be refreshed by the app.
    public var validThrough: Date
    public var scheduleConfigured: Bool
    public var accentKey: String
    public var days: [Day]

    public init(version: Int = WidgetSnapshot.currentVersion, generatedAt: Date, validThrough: Date,
                scheduleConfigured: Bool, accentKey: String, days: [Day]) {
        self.version = version
        self.generatedAt = generatedAt
        self.validThrough = validThrough
        self.scheduleConfigured = scheduleConfigured
        self.accentKey = accentKey
        self.days = days
    }

    /// Builds a snapshot covering `horizonDays` days starting with the day containing `now`.
    public static func make(engine: ScheduleEngine, configuration: ScheduleConfiguration, now: Date,
                            accentKey: String, horizonDays: Int = 3) -> WidgetSnapshot {
        let today = LocalDate(now, calendar: engine.calendar)
        let resolved = engine.resolveDays(from: today, count: max(1, horizonDays), configuration: configuration)
        let days = resolved.map { Day(date: $0.date, isSchoolDay: $0.isSchoolDay, periods: $0.periods.map(Period.init)) }
        let end = today.adding(days: max(1, horizonDays), calendar: engine.calendar).startDate(in: engine.calendar)
            ?? now.addingTimeInterval(TimeInterval(horizonDays) * 86_400)
        return WidgetSnapshot(generatedAt: now, validThrough: end, scheduleConfigured: configuration.hasAnySchedule,
                              accentKey: accentKey, days: days)
    }

    /// Instants at which the displayed status changes, after `now`, capped at `limit`.
    public func transitionDates(after now: Date, limit: Int = 40) -> [Date] {
        var dates = Set<Date>()
        for day in days {
            for period in day.periods {
                if period.startDate > now { dates.insert(period.startDate) }
                if period.endDate > now { dates.insert(period.endDate) }
            }
        }
        return Array(dates.sorted().prefix(limit))
    }

    /// The status to display at `instant`, computed without the main app.
    public func status(at instant: Date, calendar: Calendar) -> WidgetStatus {
        guard scheduleConfigured else { return WidgetStatus(state: .scheduleNeeded) }
        guard instant < validThrough else { return WidgetStatus(state: .scheduleNeeded, isStale: true) }

        let date = LocalDate(instant, calendar: calendar)
        guard let today = days.first(where: { $0.date == date }) else {
            return WidgetStatus(state: .noSchool, isStale: true)
        }

        let laterPeriods = days.filter { $0.date > date }.flatMap(\.periods)
        let active = today.periods.first { $0.startDate <= instant && instant < $0.endDate }
        let nextToday = today.periods.first { $0.startDate > instant }
        let previous = today.periods.last { $0.endDate <= instant }
        let next = nextToday ?? laterPeriods.first

        let state: DayState
        if !today.isSchoolDay {
            state = .noSchool
        } else if active != nil {
            state = .inProgress
        } else if nextToday != nil {
            state = previous == nil ? .upcoming : .freeTime
        } else {
            state = .dayComplete
        }
        return WidgetStatus(state: state, active: active, next: next, previous: previous,
                            nextIsToday: nextToday != nil, todayPeriods: today.periods)
    }
}

/// What a widget shows at a given instant.
public struct WidgetStatus: Hashable, Sendable {
    public var state: DayState
    public var active: WidgetSnapshot.Period?
    public var next: WidgetSnapshot.Period?
    public var previous: WidgetSnapshot.Period?
    /// `false` when `next` is on a later day.
    public var nextIsToday: Bool
    public var todayPeriods: [WidgetSnapshot.Period]
    /// The snapshot no longer covers this instant; the app needs to be opened to refresh it.
    public var isStale: Bool

    public init(state: DayState, active: WidgetSnapshot.Period? = nil, next: WidgetSnapshot.Period? = nil,
                previous: WidgetSnapshot.Period? = nil, nextIsToday: Bool = false,
                todayPeriods: [WidgetSnapshot.Period] = [], isStale: Bool = false) {
        self.state = state
        self.active = active
        self.next = next
        self.previous = previous
        self.nextIsToday = nextIsToday
        self.todayPeriods = todayPeriods
        self.isStale = isStale
    }
}

/// Why a stored snapshot could not be used.
public enum WidgetSnapshotError: Error, Hashable, Sendable {
    case missing
    case corrupt
    case unsupportedVersion(Int)
}

/// Encodes and safely decodes `WidgetSnapshot`.
public enum WidgetSnapshotCodec {
    public static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Decodes a snapshot, rejecting corrupt data and versions newer than this build understands.
    public static func decode(_ data: Data?) -> Result<WidgetSnapshot, WidgetSnapshotError> {
        guard let data, !data.isEmpty else { return .failure(.missing) }
        struct VersionProbe: Decodable { var version: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { return .failure(.corrupt) }
        guard probe.version == WidgetSnapshot.currentVersion else { return .failure(.unsupportedVersion(probe.version)) }
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else { return .failure(.corrupt) }
        return .success(snapshot)
    }
}
