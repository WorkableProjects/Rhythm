import Foundation
import RhythmCore
import SwiftData

/// Loads and saves Rhythm's persisted data and converts it into engine inputs.
///
/// All writes go through this type so related records stay consistent (for example, deleting a
/// template also removes its weekday assignments).
@MainActor
final class ScheduleRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reads

    func templates() -> [ScheduleTemplate] {
        let descriptor = FetchDescriptor<ScheduleTemplate>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func assignments() -> [WeekdayAssignment] {
        (try? context.fetch(FetchDescriptor<WeekdayAssignment>())) ?? []
    }

    func overrides() -> [ScheduleOverride] {
        let descriptor = FetchDescriptor<ScheduleOverride>(sortBy: [SortDescriptor(\.dateKey)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func override(on date: LocalDate) -> ScheduleOverride? {
        let key = date.key
        var descriptor = FetchDescriptor<ScheduleOverride>(predicate: #Predicate { $0.dateKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func reminders() -> [ReminderRule] {
        (try? context.fetch(FetchDescriptor<ReminderRule>())) ?? []
    }

    func quicklinks() -> [Quicklink] {
        let descriptor = FetchDescriptor<Quicklink>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func period(id: UUID) -> SchedulePeriod? {
        var descriptor = FetchDescriptor<SchedulePeriod>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func template(id: UUID) -> ScheduleTemplate? {
        var descriptor = FetchDescriptor<ScheduleTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func quicklink(id: UUID) -> Quicklink? {
        var descriptor = FetchDescriptor<Quicklink>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Engine input built from persisted data. Corrupt records are skipped.
    func configuration() -> ScheduleConfiguration {
        var weekdayAssignments: [Weekday: UUID] = [:]
        for assignment in assignments() {
            guard let weekday = assignment.weekday else { continue }
            weekdayAssignments[weekday] = assignment.templateID
        }
        return ScheduleConfiguration(
            templates: templates().map(\.definition),
            weekdayAssignments: weekdayAssignments,
            overrides: overrides().compactMap(\.definition)
        )
    }

    func reminderDefinitions() -> [ReminderDefinition] {
        reminders().compactMap(\.definition)
    }

    var hasSampleData: Bool {
        templates().contains(where: \.isSample)
    }

    // MARK: Templates and assignments

    @discardableResult
    func createTemplate(name: String, weekdays: Set<Weekday> = []) -> ScheduleTemplate {
        let template = ScheduleTemplate(name: name)
        context.insert(template)
        for weekday in weekdays { assign(weekday, to: template.id) }
        return template
    }

    /// Assigns a weekday to a template, or clears it when `templateID` is `nil`.
    func assign(_ weekday: Weekday, to templateID: UUID?) {
        let existing = assignments().filter { $0.weekdayRaw == weekday.rawValue }
        if let templateID {
            if let first = existing.first {
                first.templateID = templateID
                existing.dropFirst().forEach { context.delete($0) }
            } else {
                context.insert(WeekdayAssignment(weekday: weekday, templateID: templateID))
            }
        } else {
            existing.forEach { context.delete($0) }
        }
    }

    func weekdays(assignedTo templateID: UUID) -> [Weekday] {
        assignments().filter { $0.templateID == templateID }.compactMap(\.weekday).sorted { $0.rawValue < $1.rawValue }
    }

    func deleteTemplate(_ template: ScheduleTemplate) {
        let id = template.id
        assignments().filter { $0.templateID == id }.forEach { context.delete($0) }
        for override in overrides() where override.templateID == id {
            override.templateID = nil
        }
        context.delete(template)
    }

    /// Creates a copy of a template with new ids (reminders are not copied).
    @discardableResult
    func duplicateTemplate(_ template: ScheduleTemplate) -> ScheduleTemplate {
        let copy = ScheduleTemplate(name: "\(template.name) Copy")
        context.insert(copy)
        for period in template.periods {
            var definition = period.definition
            definition.id = UUID()
            let newPeriod = SchedulePeriod(definition)
            copy.periods.append(newPeriod)
        }
        return copy
    }

    // MARK: Periods

    /// Inserts or updates a period in a template or override from a validated definition.
    @discardableResult
    func upsertPeriod(_ definition: PeriodDefinition, in template: ScheduleTemplate) -> SchedulePeriod {
        template.updatedAt = .now
        if let existing = template.periods.first(where: { $0.id == definition.id }) {
            existing.apply(definition)
            return existing
        }
        let period = SchedulePeriod(definition)
        template.periods.append(period)
        return period
    }

    @discardableResult
    func upsertPeriod(_ definition: PeriodDefinition, in override: ScheduleOverride) -> SchedulePeriod {
        override.updatedAt = .now
        if let existing = override.periods.first(where: { $0.id == definition.id }) {
            existing.apply(definition)
            return existing
        }
        let period = SchedulePeriod(definition)
        override.periods.append(period)
        return period
    }

    func deletePeriod(_ period: SchedulePeriod) {
        context.delete(period)
    }

    /// Replaces a period's reminder rules with `definitions`, keeping ids stable.
    func setReminders(_ definitions: [ReminderDefinition], for period: SchedulePeriod) {
        let keep = Set(definitions.map(\.id))
        for rule in period.reminders where !keep.contains(rule.id) {
            context.delete(rule)
        }
        for definition in definitions {
            if let rule = period.reminders.first(where: { $0.id == definition.id }) {
                rule.title = definition.title
                rule.body = definition.body
                rule.trigger = definition.trigger
                rule.isEnabled = definition.isEnabled
            } else {
                let rule = ReminderRule(id: definition.id, title: definition.title, body: definition.body,
                                        trigger: definition.trigger, isEnabled: definition.isEnabled)
                period.reminders.append(rule)
            }
        }
    }

    // MARK: Overrides

    /// Creates or updates the single override for `date`.
    @discardableResult
    func setOverride(on date: LocalDate, kind: OverrideKind, title: String, templateID: UUID?) -> ScheduleOverride {
        if let existing = override(on: date) {
            existing.kind = kind
            existing.title = title
            existing.templateID = templateID
            existing.updatedAt = .now
            if kind == .noSchool { existing.periods.forEach { context.delete($0) } }
            return existing
        }
        let created = ScheduleOverride(date: date, kind: kind, title: title, templateID: templateID)
        context.insert(created)
        return created
    }

    func deleteOverride(_ override: ScheduleOverride) {
        context.delete(override)
    }

    // MARK: Quicklinks

    @discardableResult
    func addQuicklink(_ definition: QuicklinkDefinition) -> Quicklink {
        var definition = definition
        definition.sortOrder = (quicklinks().map(\.sortOrder).max() ?? -1) + 1
        let link = Quicklink(definition)
        context.insert(link)
        return link
    }

    @discardableResult
    func duplicateQuicklink(_ link: Quicklink) -> Quicklink {
        var definition = link.definition
        definition.id = UUID()
        definition.title = "\(link.title) Copy"
        return addQuicklink(definition)
    }

    /// Persists a new order after a move in the list.
    func reorderQuicklinks(_ ordered: [Quicklink]) {
        for (index, link) in ordered.enumerated() where link.sortOrder != index {
            link.sortOrder = index
        }
    }

    // MARK: Sample data

    /// Inserts the clearly labelled sample timetable (Monday–Friday). Only allowed when the user
    /// has no schedule yet.
    func insertSampleTimetable() {
        guard templates().isEmpty else { return }
        let definition = SampleTimetable.template()
        let template = ScheduleTemplate(id: definition.id, name: definition.name, isSample: true)
        context.insert(template)
        for period in definition.periods {
            template.periods.append(SchedulePeriod(period))
        }
        for weekday in Weekday.schoolWeek { assign(weekday, to: template.id) }
    }

    /// Adds the school's bell schedule: Regular (Mon/Wed/Fri), Advisory (Tue/Thu), and the
    /// Collaboration/Minimum Day and Finals schedules for use on specific dates. Existing schedules
    /// are kept; the weekdays are reassigned to the new templates.
    @discardableResult
    func insertBellSchedule(lunch: LunchGroup) -> [ScheduleTemplate] {
        BellSchedulePreset.entries(lunch: lunch).map { entry in
            let template = ScheduleTemplate(id: entry.template.id, name: entry.template.name)
            context.insert(template)
            for period in entry.template.periods {
                template.periods.append(SchedulePeriod(period))
            }
            for weekday in entry.weekdays { assign(weekday, to: template.id) }
            return template
        }
    }

    func removeSampleTimetable() {
        for template in templates() where template.isSample {
            deleteTemplate(template)
        }
    }

    // MARK: Whole-store operations

    func deleteAllData() {
        overrides().forEach { context.delete($0) }
        templates().forEach { context.delete($0) }
        assignments().forEach { context.delete($0) }
        reminders().forEach { context.delete($0) }
        quicklinks().forEach { context.delete($0) }
        // Orphaned periods, if any survived earlier bugs.
        ((try? context.fetch(FetchDescriptor<SchedulePeriod>())) ?? []).forEach { context.delete($0) }
    }

    func makeExport(now: Date = .now) -> RhythmExport {
        RhythmExport(
            exportedAt: now,
            templates: templates().map(\.definition),
            assignments: assignments().compactMap { assignment in
                assignment.weekday.map { RhythmExport.Assignment(weekday: $0, templateID: assignment.templateID) }
            },
            overrides: overrides().compactMap(\.definition),
            quicklinks: quicklinks().map(\.definition),
            reminders: reminderDefinitions()
        )
    }

    /// Replaces all data with a validated import. If writing fails, the previous data is restored.
    func replaceAll(with export: RhythmExport) throws {
        let backup = makeExport()
        do {
            deleteAllData()
            try context.save()
            insert(export)
            try context.save()
        } catch {
            context.rollback()
            deleteAllData()
            insert(backup)
            try? context.save()
            throw error
        }
    }

    private func insert(_ export: RhythmExport) {
        var periodsByID: [UUID: SchedulePeriod] = [:]
        for definition in export.templates {
            let template = ScheduleTemplate(id: definition.id, name: definition.name)
            context.insert(template)
            for period in definition.periods {
                let model = SchedulePeriod(period)
                template.periods.append(model)
                periodsByID[period.id] = model
            }
        }
        for assignment in export.assignments {
            context.insert(WeekdayAssignment(weekday: assignment.weekday, templateID: assignment.templateID))
        }
        for definition in export.overrides {
            let override = ScheduleOverride(id: definition.id, date: definition.date, kind: definition.kind,
                                            title: definition.title, templateID: definition.templateID)
            context.insert(override)
            for period in definition.periods {
                let model = SchedulePeriod(period)
                override.periods.append(model)
                periodsByID[period.id] = model
            }
        }
        for reminder in export.reminders {
            guard let period = periodsByID[reminder.periodID] else { continue }
            let rule = ReminderRule(id: reminder.id, title: reminder.title, body: reminder.body,
                                    trigger: reminder.trigger, isEnabled: reminder.isEnabled)
            period.reminders.append(rule)
        }
        for link in export.quicklinks {
            context.insert(Quicklink(link))
        }
    }

    func save() throws {
        if context.hasChanges { try context.save() }
    }
}
