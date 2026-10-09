import Foundation

// MARK: - Date/time policy
//
// Rhythm distinguishes two kinds of time values:
//
// * **Recurring wall-clock times** (`ClockTime`) such as "08:15". These are stored as minutes
//   after local midnight and carry no date or time zone. They are turned into real `Date`
//   values only at resolution time, for a specific `LocalDate`, using the user's current
//   `Calendar` (and therefore the current time zone and daylight-saving rules).
// * **Calendar dates** (`LocalDate`) such as 2026-10-09, used for one-off overrides and
//   one-off reminders. They are a year/month/day triple, not an instant, so they keep
//   meaning "that school day" even if the user travels across time zones.
//
// Absolute instants (`Date`) are produced by `ScheduleEngine` and are never persisted for
// recurring data.

/// A wall-clock time within a single local day, stored as minutes after local midnight.
public struct ClockTime: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// Minutes after local midnight. Valid values are `0...1440`; 1440 represents the end of the day.
    public var minutesAfterMidnight: Int

    public init(minutesAfterMidnight: Int) {
        self.minutesAfterMidnight = minutesAfterMidnight
    }

    public init(hour: Int, minute: Int) {
        self.minutesAfterMidnight = hour * 60 + minute
    }

    public var hour: Int { minutesAfterMidnight / 60 }
    public var minute: Int { minutesAfterMidnight % 60 }

    /// Whether the value lies within a single local day (`00:00` through `24:00`).
    public var isWithinDay: Bool { (0...ClockTime.endOfDayMinutes).contains(minutesAfterMidnight) }

    public static let endOfDayMinutes = 24 * 60

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesAfterMidnight < rhs.minutesAfterMidnight
    }

    /// A locale-independent `HH:mm` representation, used for debugging and export.
    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.minutesAfterMidnight = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(minutesAfterMidnight)
    }
}

/// A calendar day (year, month, day) independent of time zone.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local calendar day that contains `date` in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Parses a `yyyy-MM-dd` key. Returns `nil` for malformed or impossible dates.
    public init?(key: String) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC") ?? gregorian.timeZone
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = gregorian.date(from: components),
              gregorian.component(.day, from: date) == day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// A stable `yyyy-MM-dd` key used for persistence and notification identifiers.
    public var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { key }

    /// Local midnight at the start of this day in `calendar`.
    public func startDate(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { calendar.startOfDay(for: $0) }
    }

    /// The real instant for `time` on this day. Uses `Calendar` so days that are 23 or 25 hours
    /// long (daylight-saving transitions) are handled; a wall time that does not exist on this
    /// day (inside a spring-forward gap) resolves to the next valid instant.
    public func date(at time: ClockTime, in calendar: Calendar) -> Date? {
        if time.minutesAfterMidnight >= ClockTime.endOfDayMinutes {
            return adding(days: 1, calendar: calendar).startDate(in: calendar)
        }
        guard let start = startDate(in: calendar) else { return nil }
        return calendar.date(
            bySettingHour: time.hour,
            minute: time.minute,
            second: 0,
            of: start,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    /// The day `days` after this one (negative values go back).
    public func adding(days: Int, calendar: Calendar) -> LocalDate {
        // Anchor on noon to avoid any DST ambiguity around midnight.
        guard let start = startDate(in: calendar),
              let noon = calendar.date(byAdding: .hour, value: 12, to: start),
              let shifted = calendar.date(byAdding: .day, value: days, to: noon) else { return self }
        return LocalDate(shifted, calendar: calendar)
    }

    /// The weekday of this date.
    public func weekday(in calendar: Calendar) -> Weekday {
        guard let start = startDate(in: calendar) else { return .monday }
        return Weekday(rawValue: calendar.component(.weekday, from: start)) ?? .monday
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let key = try container.decode(String.self)
        guard let value = LocalDate(key: key) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date key \(key)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

/// A weekday using `Calendar`'s numbering (Sunday = 1 … Saturday = 7).
public enum Weekday: Int, CaseIterable, Codable, Sendable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var id: Int { rawValue }

    /// Weekdays ordered for display, starting at `calendar.firstWeekday`.
    public static func ordered(for calendar: Calendar) -> [Weekday] {
        let first = calendar.firstWeekday
        return (0..<7).compactMap { Weekday(rawValue: ((first - 1 + $0) % 7) + 1) }
    }

    /// Monday through Friday.
    public static let schoolWeek: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// The localized full weekday name from `calendar`.
    public func name(in calendar: Calendar) -> String {
        let symbols = calendar.weekdaySymbols
        return symbols.indices.contains(rawValue - 1) ? symbols[rawValue - 1] : "\(rawValue)"
    }

    /// The localized short weekday name from `calendar`.
    public func shortName(in calendar: Calendar) -> String {
        let symbols = calendar.shortWeekdaySymbols
        return symbols.indices.contains(rawValue - 1) ? symbols[rawValue - 1] : "\(rawValue)"
    }
}
