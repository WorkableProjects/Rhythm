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
    /// The four copyable bell schedule templates.
    public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
        case regular, advisory, collaboration, finals

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .regular: "Monday, Wednesday & Friday"
            case .advisory: "Tuesday & Thursday (Advisory)"
            case .collaboration: "Collaboration Day"
            case .finals: "Finals"
            }
        }

        public var summary: String {
            switch self {
            case .regular: "Regular schedule, 8:30 AM – 3:30 PM"
            case .advisory: "Advisory schedule, 8:30 AM – 3:30 PM"
            case .collaboration: "Collaboration and minimum days, 8:30 AM – 12:55 PM"
            case .finals: "Finals days, 8:30 AM – 1:00 PM"
            }
        }

        /// Whether the times differ between A and B lunch.
        public var dependsOnLunch: Bool { self == .regular || self == .advisory }

        /// Weekdays the schedule normally repeats on; empty for date-only schedules.
        public var defaultWeekdays: [Weekday] {
            switch self {
            case .regular: [.monday, .wednesday, .friday]
            case .advisory: [.tuesday, .thursday]
            case .collaboration, .finals: []
            }
        }

        /// The template's name when copied, e.g. "Mon/Wed/Fri (A Lunch)".
        public func templateName(lunch: LunchGroup) -> String {
            switch self {
            case .regular: "Mon/Wed/Fri (\(lunch.displayName))"
            case .advisory: "Tue/Thu Advisory (\(lunch.displayName))"
            case .collaboration: "Collaboration Day"
            case .finals: "Finals"
            }
        }

        public func template(lunch: LunchGroup) -> TemplateDefinition {
            switch self {
            case .regular: BellSchedulePreset.regular(lunch: lunch)
            case .advisory: BellSchedulePreset.advisory(lunch: lunch)
            case .collaboration: BellSchedulePreset.collaboration()
            case .finals: BellSchedulePreset.finals()
            }
        }
    }

    /// A template and the weekdays it should be assigned to (empty for date-only schedules).
    public struct Entry: Hashable, Sendable {
        public var kind: Kind
        public var template: TemplateDefinition
        public var weekdays: [Weekday]
    }

    /// All four templates, with the weekdays the recurring ones repeat on.
    public static func entries(lunch: LunchGroup) -> [Entry] {
        Kind.allCases.map { Entry(kind: $0, template: $0.template(lunch: lunch), weekdays: $0.defaultWeekdays) }
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
        return template(Kind.regular.templateName(lunch: lunch), rows)
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
        return template(Kind.advisory.templateName(lunch: lunch), rows)
    }

    /// Collaboration days and minimum days. Senior Seminar is included but switched off; seniors
    /// can turn it on in the period editor.
    public static func collaboration() -> TemplateDefinition {
        var definition = template(Kind.collaboration.templateName(lunch: .a), [
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
        template(Kind.finals.templateName(lunch: .a), [
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
