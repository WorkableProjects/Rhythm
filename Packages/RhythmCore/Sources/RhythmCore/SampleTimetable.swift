import Foundation

/// The clearly labelled sample timetable offered during onboarding ("Explore a sample"),
/// also used by tests. It is inserted only when the user explicitly chooses it.
public enum SampleTimetable {
    public static let templateName = "Sample Schedule"

    /// Six classes plus lunch, 8:00 AM to 2:55 PM, with passing gaps.
    public static func template(id: UUID = UUID()) -> TemplateDefinition {
        let entries: [(String, PeriodKind, Int, Int, Int, Int)] = [
            ("English", .classPeriod, 8, 0, 8, 55),
            ("Biology", .classPeriod, 9, 0, 9, 55),
            ("Algebra II", .classPeriod, 10, 0, 10, 55),
            ("Lunch", .lunch, 10, 55, 11, 30),
            ("World History", .classPeriod, 11, 35, 12, 30),
            ("Spanish", .classPeriod, 12, 35, 13, 30),
            ("Physical Education", .classPeriod, 13, 35, 14, 55)
        ]
        let periods = entries.enumerated().map { index, entry in
            PeriodDefinition(
                title: entry.0,
                kind: entry.1,
                start: ClockTime(hour: entry.2, minute: entry.3),
                end: ClockTime(hour: entry.4, minute: entry.5),
                sortOrder: index
            )
        }
        return TemplateDefinition(id: id, name: templateName, periods: periods)
    }
}
