import Foundation
import RhythmCore

// Conversions between persisted SwiftData models and RhythmCore value types. The engine and
// export format only ever see the value types.

extension SchedulePeriod {
    var definition: PeriodDefinition {
        PeriodDefinition(id: id, title: title, kind: kind, start: start, end: end, detail: detail,
                         colorKey: colorKey, symbolName: symbolName, isEnabled: isEnabled, sortOrder: sortOrder)
    }

    func apply(_ definition: PeriodDefinition) {
        title = definition.title
        kind = definition.kind
        start = definition.start
        end = definition.end
        detail = definition.detail
        colorKey = definition.colorKey
        symbolName = definition.symbolName
        isEnabled = definition.isEnabled
        sortOrder = definition.sortOrder
    }

    convenience init(_ definition: PeriodDefinition) {
        self.init(id: definition.id, title: definition.title, kind: definition.kind, start: definition.start,
                  end: definition.end, detail: definition.detail, colorKey: definition.colorKey,
                  symbolName: definition.symbolName, sortOrder: definition.sortOrder, isEnabled: definition.isEnabled)
    }
}

extension ScheduleTemplate {
    var definition: TemplateDefinition {
        TemplateDefinition(id: id, name: name, periods: periods.map(\.definition))
    }
}

extension ScheduleOverride {
    /// `nil` when the stored date key is corrupt; such records are skipped.
    var definition: OverrideDefinition? {
        guard let date else { return nil }
        return OverrideDefinition(id: id, date: date, kind: kind, title: title, templateID: templateID,
                                  periods: periods.map(\.definition))
    }
}

extension ReminderRule {
    /// `nil` when trigger data is invalid.
    var definition: ReminderDefinition? {
        guard let trigger else { return nil }
        return ReminderDefinition(
            id: id,
            periodID: period?.id,
            title: title,
            body: body,
            trigger: trigger,
            isEnabled: isEnabled,
            status: status,
            priority: priority,
            dueDate: dueDate,
            dueTime: dueTime,
            snoozedUntil: snoozedUntil,
            completedAt: completedAt
        )
    }
}

extension Quicklink {
    var definition: QuicklinkDefinition {
        QuicklinkDefinition(id: id, title: title, urlString: urlString, kind: kind, symbolName: symbolName,
                            category: category, note: note, isFavorite: isFavorite, sortOrder: sortOrder)
    }

    convenience init(_ definition: QuicklinkDefinition) {
        self.init(id: definition.id, title: definition.title, urlString: definition.urlString, kind: definition.kind,
                  symbolName: definition.symbolName, category: definition.category, note: definition.note,
                  isFavorite: definition.isFavorite, sortOrder: definition.sortOrder)
    }
}
