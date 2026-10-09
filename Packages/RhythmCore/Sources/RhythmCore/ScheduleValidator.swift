import Foundation

/// A problem found in schedule data. Each issue has user-facing copy.
public enum ScheduleIssue: Hashable, Sendable {
    case emptyTitle(periodID: UUID)
    case endNotAfterStart(periodID: UUID, title: String)
    case outsideDay(periodID: UUID, title: String)
    /// `first` starts no later than `second` and they share `minutes` minutes.
    case overlap(firstID: UUID, firstTitle: String, secondID: UUID, secondTitle: String, minutes: Int)
    case duplicateWeekdayAssignment(Weekday)
    case unknownTemplate(UUID)

    /// The periods this issue concerns, for highlighting in editors.
    public var periodIDs: [UUID] {
        switch self {
        case .emptyTitle(let id), .endNotAfterStart(let id, _), .outsideDay(let id, _): [id]
        case .overlap(let first, _, let second, _, _): [first, second]
        case .duplicateWeekdayAssignment, .unknownTemplate: []
        }
    }

    /// Specific, actionable copy, e.g. "Biology overlaps Lunch by 5 minutes."
    public var message: String {
        switch self {
        case .emptyTitle:
            return "Every period needs a title."
        case .endNotAfterStart(_, let title):
            return "\(Self.name(title)) must end after it starts."
        case .outsideDay(_, let title):
            return "\(Self.name(title)) must start and end on the same day."
        case .overlap(_, let first, _, let second, let minutes):
            let unit = minutes == 1 ? "minute" : "minutes"
            return "\(Self.name(second)) overlaps \(Self.name(first)) by \(minutes) \(unit)."
        case .duplicateWeekdayAssignment(let weekday):
            return "\(weekday.name(in: Calendar.current)) has more than one schedule assigned."
        case .unknownTemplate:
            return "A schedule refers to a template that no longer exists."
        }
    }

    private static func name(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled period" : trimmed
    }
}

/// Validates schedule data. Pure and deterministic.
public enum ScheduleValidator {
    /// Validates a set of periods that belong to one day. Disabled periods are ignored for
    /// overlap checks (they never appear in a resolved day) but still need valid times.
    /// Gaps and periods that touch at a boundary are valid.
    public static func validate(periods: [PeriodDefinition]) -> [ScheduleIssue] {
        var issues: [ScheduleIssue] = []
        var rangeValid: [PeriodDefinition] = []

        for period in periods {
            if period.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.emptyTitle(periodID: period.id))
            }
            if !period.start.isWithinDay || !period.end.isWithinDay {
                issues.append(.outsideDay(periodID: period.id, title: period.title))
            } else if period.end <= period.start {
                issues.append(.endNotAfterStart(periodID: period.id, title: period.title))
            } else if period.isEnabled {
                rangeValid.append(period)
            }
        }

        let sorted = rangeValid.sorted(by: chronological)
        for (index, period) in sorted.enumerated() {
            for later in sorted[(index + 1)...] {
                if later.start >= period.end { break }
                let overlapEnd = min(period.end.minutesAfterMidnight, later.end.minutesAfterMidnight)
                let minutes = overlapEnd - later.start.minutesAfterMidnight
                issues.append(.overlap(
                    firstID: period.id, firstTitle: period.title,
                    secondID: later.id, secondTitle: later.title,
                    minutes: minutes
                ))
            }
        }
        return issues
    }

    /// Validates weekday-to-template assignments supplied as a list (as they come from storage
    /// or an import), detecting duplicate weekdays and references to unknown templates.
    public static func validate(
        assignments: [(weekday: Weekday, templateID: UUID)],
        knownTemplateIDs: Set<UUID>
    ) -> [ScheduleIssue] {
        var seen = Set<Weekday>()
        var issues: [ScheduleIssue] = []
        for assignment in assignments {
            if !seen.insert(assignment.weekday).inserted {
                issues.append(.duplicateWeekdayAssignment(assignment.weekday))
            }
            if !knownTemplateIDs.contains(assignment.templateID) {
                issues.append(.unknownTemplate(assignment.templateID))
            }
        }
        return issues
    }

    /// Stable chronological ordering: start, then end, then user sort order, then id.
    public static func chronological(_ lhs: PeriodDefinition, _ rhs: PeriodDefinition) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
