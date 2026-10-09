import Foundation
@testable import RhythmCore

/// Shared fixtures for deterministic tests. Every test uses an explicit calendar and time zone.
enum Fixtures {
    static func calendar(_ identifier: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Friday, 9 October 2026.
    static let friday = LocalDate(year: 2026, month: 10, day: 9)
    /// Saturday, 10 October 2026.
    static let saturday = LocalDate(year: 2026, month: 10, day: 10)

    static func instant(_ date: LocalDate, _ hour: Int, _ minute: Int, second: Int = 0, calendar: Calendar = calendar()) -> Date {
        calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: hour, minute: minute, second: second))!
    }

    static func period(_ title: String, _ kind: PeriodKind = .classPeriod, _ sh: Int, _ sm: Int, _ eh: Int, _ em: Int,
                       enabled: Bool = true, id: UUID = UUID()) -> PeriodDefinition {
        PeriodDefinition(id: id, title: title, kind: kind, start: ClockTime(hour: sh, minute: sm),
                         end: ClockTime(hour: eh, minute: em), isEnabled: enabled)
    }

    /// The six-classes-plus-lunch sample assigned Monday–Friday.
    static func weekConfiguration(overrides: [OverrideDefinition] = []) -> (ScheduleConfiguration, TemplateDefinition) {
        let template = SampleTimetable.template()
        let assignments = Dictionary(uniqueKeysWithValues: Weekday.schoolWeek.map { ($0, template.id) })
        return (ScheduleConfiguration(templates: [template], weekdayAssignments: assignments, overrides: overrides), template)
    }
}
