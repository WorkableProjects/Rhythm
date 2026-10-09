import Foundation

/// Which lunch a student has. The bell schedule differs only around lunch.
public enum LunchGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    case a, b

    public var id: String { rawValue }
    public var displayName: String { self == .a ? "A Lunch" : "B Lunch" }
}

/// The school's published bell schedule, offered as Rhythm's default timetable.
///
/// - Regular schedule: Monday, Wednesday, Friday.
/// - Advisory schedule: Tuesday, Thursday.
/// - Collaboration / Minimum Day and Finals: not tied to a weekday; applied to specific dates with
///   "Change This Date".
public enum BellSchedulePreset {
    public static let regularName = "Regular (Mon/Wed/Fri)"
    public static let advisoryName = "Advisory (Tue/Thu)"
    public static let collaborationName = "Collaboration / Minimum Day"
    public static let finalsName = "Finals"

    /// A template and the weekdays it should be assigned to (empty for date-only schedules).
    public struct Entry: Hashable, Sendable {
        public var template: TemplateDefinition
        public var weekdays: [Weekday]
    }

    public static func entries(lunch: LunchGroup) -> [Entry] {
        [
            Entry(template: regular(lunch: lunch), weekdays: [.monday, .wednesday, .friday]),
            Entry(template: advisory(lunch: lunch), weekdays: [.tuesday, .thursday]),
            Entry(template: collaboration(), weekdays: []),
            Entry(template: finals(), weekdays: [])
        ]
    }

    /// Monday, Wednesday & Friday.
    public static func regular(lunch: LunchGroup) -> TemplateDefinition {
        let rows: [Row] = switch lunch {
        case .a: [
            ("Period 1", .classPeriod, "8:30", "9:28"),
            ("Period 2", .classPeriod, "9:34", "10:32"),
            ("Period 3", .classPeriod, "10:38", "11:36"),
            ("Lunch", .lunch, "11:36", "12:18"),
            ("Period 4", .classPeriod, "12:24", "13:22"),
            ("Period 5", .classPeriod, "13:28", "14:26"),
            ("Period 6", .classPeriod, "14:32", "15:30")
        ]
        case .b: [
            ("Period 1", .classPeriod, "8:30", "9:28"),
            ("Period 2", .classPeriod, "9:34", "10:32"),
            ("Period 3", .classPeriod, "10:38", "11:36"),
            ("Period 4", .classPeriod, "11:42", "12:40"),
            ("Lunch", .lunch, "12:40", "13:22"),
            ("Period 5", .classPeriod, "13:28", "14:26"),
            ("Period 6", .classPeriod, "14:32", "15:30")
        ]
        }
        return template(regularName, rows)
    }

    /// Advisory Tuesday & Thursday.
    public static func advisory(lunch: LunchGroup) -> TemplateDefinition {
        let rows: [Row] = switch lunch {
        case .a: [
            ("Period 1", .classPeriod, "8:30", "9:23"),
            ("Period 2 / Advisory", .classPeriod, "9:29", "10:52"),
            ("Period 3", .classPeriod, "10:58", "11:51"),
            ("Lunch", .lunch, "11:51", "12:33"),
            ("Period 4", .classPeriod, "12:39", "13:32"),
            ("Period 5", .classPeriod, "13:38", "14:31"),
            ("Period 6", .classPeriod, "14:37", "15:30")
        ]
        case .b: [
            ("Period 1", .classPeriod, "8:30", "9:23"),
            ("Period 2 / Advisory", .classPeriod, "9:29", "10:52"),
            ("Period 3", .classPeriod, "10:58", "11:51"),
            ("Period 4", .classPeriod, "11:57", "12:50"),
            ("Lunch", .lunch, "12:50", "13:32"),
            ("Period 5", .classPeriod, "13:38", "14:31"),
            ("Period 6", .classPeriod, "14:37", "15:30")
        ]
        }
        return template(advisoryName, rows)
    }

    /// Collaboration days and minimum days. Senior Seminar is included but switched off; seniors
    /// can turn it on in the period editor.
    public static func collaboration() -> TemplateDefinition {
        var definition = template(collaborationName, [
            ("Period 1", .classPeriod, "8:30", "9:05"),
            ("Period 2", .classPeriod, "9:11", "9:46"),
            ("Period 3", .classPeriod, "9:52", "10:27"),
            ("Period 4", .classPeriod, "10:33", "11:08"),
            ("Period 5", .classPeriod, "11:14", "11:49"),
            ("Period 6", .classPeriod, "11:55", "12:30"),
            ("Lunch", .lunch, "12:35", "12:55"),
            ("Senior Seminar", .other, "13:30", "15:00")
        ])
        if let index = definition.periods.firstIndex(where: { $0.title == "Senior Seminar" }) {
            definition.periods[index].isEnabled = false
        }
        return definition
    }

    /// Finals days.
    public static func finals() -> TemplateDefinition {
        template(finalsName, [
            ("Periods 1/2/3", .classPeriod, "8:30", "10:30"),
            ("Periods 4/5/6", .classPeriod, "10:40", "12:40"),
            ("Lunch", .lunch, "12:40", "13:00")
        ])
    }

    // MARK: Helpers

    private typealias Row = (title: String, kind: PeriodKind, start: String, end: String)

    private static func template(_ name: String, _ rows: [Row]) -> TemplateDefinition {
        let periods = rows.enumerated().map { index, row in
            PeriodDefinition(title: row.title, kind: row.kind, start: clock(row.start), end: clock(row.end), sortOrder: index)
        }
        return TemplateDefinition(name: name, periods: periods)
    }

    /// Parses 24-hour "H:mm".
    private static func clock(_ text: String) -> ClockTime {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return ClockTime(hour: parts[0], minute: parts[1])
    }
}
