import Foundation

/// The category of a period. Always presented with text and a symbol, never colour alone.
public enum PeriodKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case classPeriod = "class"
    case lunch
    case breakTime = "break"
    case passing
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classPeriod: "Class"
        case .lunch: "Lunch"
        case .breakTime: "Break"
        case .passing: "Passing"
        case .other: "Other"
        }
    }

    /// The default SF Symbol for the category.
    public var defaultSymbolName: String {
        switch self {
        case .classPeriod: "book.closed"
        case .lunch: "fork.knife"
        case .breakTime: "cup.and.saucer"
        case .passing: "figure.walk"
        case .other: "circle.dashed"
        }
    }

    /// Decodes unknown raw values as `.other` so newer data never crashes older builds.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PeriodKind(rawValue: raw) ?? .other
    }
}

/// A value-type description of one period inside a template or a custom-day override.
///
/// SwiftData models in the app are mapped to these values before the engine runs, so the engine
/// stays pure and testable.
public struct PeriodDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: PeriodKind
    public var start: ClockTime
    public var end: ClockTime
    /// Optional lightweight label such as a room or teacher name.
    public var detail: String?
    public var colorKey: String?
    public var symbolName: String?
    public var isEnabled: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        title: String,
        kind: PeriodKind = .classPeriod,
        start: ClockTime,
        end: ClockTime,
        detail: String? = nil,
        colorKey: String? = nil,
        symbolName: String? = nil,
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.start = start
        self.end = end
        self.detail = detail
        self.colorKey = colorKey
        self.symbolName = symbolName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    /// Duration in minutes (may be zero or negative for invalid data).
    public var durationMinutes: Int { end.minutesAfterMidnight - start.minutesAfterMidnight }

    /// The symbol to display: the custom one if set, otherwise the category default.
    public var resolvedSymbolName: String { symbolName ?? kind.defaultSymbolName }
}

/// A full, ordered day schedule that can be assigned to one or more weekdays.
public struct TemplateDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var periods: [PeriodDefinition]

    public init(id: UUID = UUID(), name: String, periods: [PeriodDefinition]) {
        self.id = id
        self.name = name
        self.periods = periods
    }
}

/// The type of a date-specific change.
public enum OverrideKind: String, CaseIterable, Codable, Sendable, Identifiable {
    /// No school on this date. Takes priority over everything else.
    case noSchool
    /// A different schedule on this date: either another template or custom periods.
    case customSchedule

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .noSchool: "No School"
        case .customSchedule: "Special Schedule"
        }
    }
}

/// A change that applies to exactly one calendar date.
public struct OverrideDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var date: LocalDate
    public var kind: OverrideKind
    /// A short label such as "Assembly" or "Minimum Day".
    public var title: String
    /// For `.customSchedule`: use this template's periods. Ignored when `periods` is non-empty.
    public var templateID: UUID?
    /// For `.customSchedule`: one-off periods for this date only.
    public var periods: [PeriodDefinition]

    public init(
        id: UUID = UUID(),
        date: LocalDate,
        kind: OverrideKind,
        title: String = "",
        templateID: UUID? = nil,
        periods: [PeriodDefinition] = []
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.templateID = templateID
        self.periods = periods
    }
}

/// Everything the engine needs to resolve any date. Built from persisted data by the app.
public struct ScheduleConfiguration: Hashable, Sendable {
    public var templates: [UUID: TemplateDefinition]
    public var weekdayAssignments: [Weekday: UUID]
    public var overrides: [LocalDate: OverrideDefinition]

    public init(
        templates: [TemplateDefinition] = [],
        weekdayAssignments: [Weekday: UUID] = [:],
        overrides: [OverrideDefinition] = []
    ) {
        self.templates = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.weekdayAssignments = weekdayAssignments
        // If two overrides share a date (invalid data), the first wins deterministically by id.
        let sorted = overrides.sorted { $0.id.uuidString < $1.id.uuidString }
        self.overrides = Dictionary(sorted.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public static let empty = ScheduleConfiguration()

    /// Whether the user has created any schedule template at all.
    public var hasAnySchedule: Bool { !templates.isEmpty }

    /// Every period definition known to the configuration, keyed by id.
    public var allPeriods: [UUID: PeriodDefinition] {
        var result: [UUID: PeriodDefinition] = [:]
        for template in templates.values {
            for period in template.periods { result[period.id] = period }
        }
        for override in overrides.values {
            for period in override.periods { result[period.id] = period }
        }
        return result
    }
}
