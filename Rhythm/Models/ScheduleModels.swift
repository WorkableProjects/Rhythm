import Foundation
import RhythmCore
import SwiftData

// Persisted SwiftData models (schema V1). Recurring times are stored as minutes after local
// midnight; one-off dates are stored as `yyyy-MM-dd` keys. Real `Date`s are produced only by
// `ScheduleEngine` at resolution time. See `RhythmSchema.swift` before changing any shape here.

/// A full, ordered day schedule (e.g. "Regular Day") that weekdays can be assigned to.
@Model
final class ScheduleTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// `true` for the onboarding sample timetable so it can be removed in one step.
    var isSample: Bool

    @Relationship(deleteRule: .cascade, inverse: \SchedulePeriod.template)
    var periods: [SchedulePeriod] = []

    init(id: UUID = UUID(), name: String, isSample: Bool = false, now: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = now
        self.updatedAt = now
        self.isSample = isSample
    }

    /// Periods in chronological order (stable for equal start times).
    var sortedPeriods: [SchedulePeriod] {
        periods.sorted { ScheduleValidator.chronological($0.definition, $1.definition) }
    }
}

/// One period in a template, or in a date-specific custom schedule.
@Model
final class SchedulePeriod {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    var startMinute: Int
    var endMinute: Int
    /// Optional lightweight label (room or teacher).
    var detail: String?
    var colorKey: String?
    var symbolName: String?
    var sortOrder: Int
    var isEnabled: Bool

    /// Set when the period belongs to a template.
    var template: ScheduleTemplate?
    /// Set when the period belongs to a date-specific custom schedule.
    var dateOverride: ScheduleOverride?

    @Relationship(deleteRule: .cascade, inverse: \ReminderRule.period)
    var reminders: [ReminderRule] = []

    init(id: UUID = UUID(), title: String, kind: PeriodKind, start: ClockTime, end: ClockTime,
         detail: String? = nil, colorKey: String? = nil, symbolName: String? = nil,
         sortOrder: Int = 0, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.startMinute = start.minutesAfterMidnight
        self.endMinute = end.minutesAfterMidnight
        self.detail = detail
        self.colorKey = colorKey
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
    }

    var kind: PeriodKind {
        get { PeriodKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var start: ClockTime {
        get { ClockTime(minutesAfterMidnight: startMinute) }
        set { startMinute = newValue.minutesAfterMidnight }
    }

    var end: ClockTime {
        get { ClockTime(minutesAfterMidnight: endMinute) }
        set { endMinute = newValue.minutesAfterMidnight }
    }
}

/// Maps one weekday to one template. `weekdayRaw` is unique, so a weekday can never have two
/// effective templates.
@Model
final class WeekdayAssignment {
    @Attribute(.unique) var weekdayRaw: Int
    var templateID: UUID

    init(weekday: Weekday, templateID: UUID) {
        self.weekdayRaw = weekday.rawValue
        self.templateID = templateID
    }

    var weekday: Weekday? { Weekday(rawValue: weekdayRaw) }
}

/// A change for exactly one calendar date: no school, or a special schedule.
@Model
final class ScheduleOverride {
    @Attribute(.unique) var id: UUID
    /// `yyyy-MM-dd` local calendar date (not an instant).
    @Attribute(.unique) var dateKey: String
    var kindRaw: String
    var title: String
    /// For a special schedule based on another template.
    var templateID: UUID?
    var updatedAt: Date

    /// For a special schedule with its own one-off periods.
    @Relationship(deleteRule: .cascade, inverse: \SchedulePeriod.dateOverride)
    var periods: [SchedulePeriod] = []

    init(id: UUID = UUID(), date: LocalDate, kind: OverrideKind, title: String = "", templateID: UUID? = nil, now: Date = .now) {
        self.id = id
        self.dateKey = date.key
        self.kindRaw = kind.rawValue
        self.title = title
        self.templateID = templateID
        self.updatedAt = now
    }

    var date: LocalDate? { LocalDate(key: dateKey) }

    var kind: OverrideKind {
        get { OverrideKind(rawValue: kindRaw) ?? .noSchool }
        set { kindRaw = newValue.rawValue }
    }
}

/// A schedule-linked or standalone reminder item.
@Model
final class ReminderRule {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String?
    /// `beforeStart`, `oneOff`, or `standalone`.
    var triggerKindRaw: String
    var offsetMinutes: Int
    var oneOffDateKey: String?
    var oneOffMinute: Int?
    var isEnabled: Bool
    var createdAt: Date
    var period: SchedulePeriod?

    var statusRaw: String?
    var priorityRaw: String?
    var dueDateKey: String?
    var dueMinute: Int?
    var snoozedUntil: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        body: String? = nil,
        trigger: ReminderTrigger,
        isEnabled: Bool = true,
        status: ReminderStatus = .active,
        priority: ReminderPriority = .medium,
        dueDate: LocalDate? = nil,
        dueTime: ClockTime? = nil,
        snoozedUntil: Date? = nil,
        completedAt: Date? = nil,
        now: Date = .now
    ) {
        self.id = id
        let fields = Self.storedFields(for: trigger)
        self.title = title
        self.body = body
        self.triggerKindRaw = fields.kind
        self.offsetMinutes = fields.offset
        self.oneOffDateKey = fields.dateKey
        self.oneOffMinute = fields.minute
        self.isEnabled = isEnabled
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.dueDateKey = dueDate?.key
        self.dueMinute = dueTime?.minutesAfterMidnight
        self.snoozedUntil = snoozedUntil
        self.completedAt = completedAt
        self.createdAt = now
    }

    private static func storedFields(for trigger: ReminderTrigger) -> (kind: String, offset: Int, dateKey: String?, minute: Int?) {
        switch trigger {
        case .beforeStart(let minutes): ("beforeStart", minutes, nil, nil)
        case .oneOff(let date, let time): ("oneOff", 0, date.key, time.minutesAfterMidnight)
        case .standalone(let date, let time): ("standalone", 0, date?.key, time?.minutesAfterMidnight)
        }
    }

    var status: ReminderStatus {
        get { statusRaw.flatMap(ReminderStatus.init(rawValue:)) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var priority: ReminderPriority {
        get { priorityRaw.flatMap(ReminderPriority.init(rawValue:)) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var dueDate: LocalDate? {
        get { dueDateKey.flatMap(LocalDate.init(key:)) }
        set { dueDateKey = newValue?.key }
    }

    var dueTime: ClockTime? {
        get { dueMinute.map { ClockTime(minutesAfterMidnight: $0) } }
        set { dueMinute = newValue?.minutesAfterMidnight }
    }

    /// Returns `nil` when stored trigger data is invalid; such rules are skipped, never crash.
    var trigger: ReminderTrigger? {
        get {
            switch triggerKindRaw {
            case "oneOff":
                guard let key = oneOffDateKey, let date = LocalDate(key: key), let minute = oneOffMinute else { return nil }
                return .oneOff(date: date, time: ClockTime(minutesAfterMidnight: minute))
            case "standalone":
                let date = oneOffDateKey.flatMap(LocalDate.init(key:))
                let time = oneOffMinute.map { ClockTime(minutesAfterMidnight: $0) }
                return .standalone(date: date, time: time)
            default:
                return .beforeStart(minutes: offsetMinutes)
            }
        }
        set {
            guard let newValue else { return }
            let fields = Self.storedFields(for: newValue)
            triggerKindRaw = fields.kind
            offsetMinutes = fields.offset
            oneOffDateKey = fields.dateKey
            oneOffMinute = fields.minute
        }
    }
}

/// A launcher for an existing app, website, or Shortcut.
@Model
final class Quicklink {
    @Attribute(.unique) var id: UUID
    var title: String
    var urlString: String
    var kindRaw: String
    var symbolName: String?
    var categoryRaw: String?
    var note: String?
    var isFavorite: Bool
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, kind: QuicklinkKind, symbolName: String? = nil,
         category: QuicklinkCategory? = nil, note: String? = nil, isFavorite: Bool = false, sortOrder: Int = 0, now: Date = .now) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.kindRaw = kind.rawValue
        self.symbolName = symbolName
        self.categoryRaw = category?.rawValue
        self.note = note
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
        self.createdAt = now
    }

    var kind: QuicklinkKind {
        get { QuicklinkKind(rawValue: kindRaw) ?? .app }
        set { kindRaw = newValue.rawValue }
    }

    var category: QuicklinkCategory? {
        get { categoryRaw.flatMap(QuicklinkCategory.init(rawValue:)) }
        set { categoryRaw = newValue?.rawValue }
    }

    var resolvedSymbolName: String { symbolName ?? kind.defaultSymbolName }
}
