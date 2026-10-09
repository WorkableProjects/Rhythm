import Foundation

/// The versioned JSON format for exporting and importing a Rhythm timetable.
///
/// This is a stable DTO, deliberately independent of the app's SwiftData models, so the
/// persisted schema can evolve without breaking files users have saved.
public struct RhythmExport: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public struct Assignment: Codable, Hashable, Sendable {
        public var weekday: Weekday
        public var templateID: UUID

        public init(weekday: Weekday, templateID: UUID) {
            self.weekday = weekday
            self.templateID = templateID
        }
    }

    public var schemaVersion: Int
    public var exportedAt: Date
    public var templates: [TemplateDefinition]
    public var assignments: [Assignment]
    public var overrides: [OverrideDefinition]
    public var quicklinks: [QuicklinkDefinition]
    public var reminders: [ReminderDefinition]

    public init(schemaVersion: Int = RhythmExport.currentSchemaVersion, exportedAt: Date,
                templates: [TemplateDefinition], assignments: [Assignment], overrides: [OverrideDefinition],
                quicklinks: [QuicklinkDefinition], reminders: [ReminderDefinition]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.templates = templates
        self.assignments = assignments
        self.overrides = overrides
        self.quicklinks = quicklinks
        self.reminders = reminders
    }

    /// The engine configuration described by this export.
    public var configuration: ScheduleConfiguration {
        ScheduleConfiguration(
            templates: templates,
            weekdayAssignments: Dictionary(assignments.map { ($0.weekday, $0.templateID) }, uniquingKeysWith: { first, _ in first }),
            overrides: overrides
        )
    }
}

/// Why an import was rejected. Nothing is written when any of these occur.
public enum ImportError: Error, Hashable, Sendable {
    case malformed
    case unsupportedVersion(Int)
    case invalid([String])

    public var message: String {
        switch self {
        case .malformed:
            return "This file isn’t a Rhythm timetable, or it’s damaged."
        case .unsupportedVersion(let version):
            return "This file uses format version \(version), which this version of Rhythm can’t read."
        case .invalid(let problems):
            return "This file has problems:\n" + problems.prefix(8).map { "• \($0)" }.joined(separator: "\n")
        }
    }
}

/// A validated import, ready to show the user before committing.
public struct ImportPreview: Hashable, Sendable {
    public var export: RhythmExport
    public var templateCount: Int { export.templates.count }
    public var periodCount: Int { export.templates.reduce(0) { $0 + $1.periods.count } }
    public var overrideCount: Int { export.overrides.count }
    public var quicklinkCount: Int { export.quicklinks.count }
    public var reminderCount: Int { export.reminders.count }
}

/// Encodes exports and decodes/validates imports. Validation never mutates existing data.
public enum ExportImportCodec {
    public static func encode(_ export: RhythmExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    public static func decodeAndValidate(_ data: Data) -> Result<ImportPreview, ImportError> {
        struct VersionProbe: Decodable { var schemaVersion: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { return .failure(.malformed) }
        guard probe.schemaVersion == RhythmExport.currentSchemaVersion else {
            return .failure(.unsupportedVersion(probe.schemaVersion))
        }
        guard let export = try? decoder.decode(RhythmExport.self, from: data) else { return .failure(.malformed) }

        let problems = validate(export)
        return problems.isEmpty ? .success(ImportPreview(export: export)) : .failure(.invalid(problems))
    }

    /// Checks ids, relationships, and times. Returns user-facing problem descriptions.
    public static func validate(_ export: RhythmExport) -> [String] {
        var problems: [String] = []
        var seenIDs = Set<UUID>()
        func checkUnique(_ id: UUID, _ label: String) {
            if !seenIDs.insert(id).inserted { problems.append("Duplicate ID for \(label).") }
        }

        var periodIDs = Set<UUID>()
        for template in export.templates {
            checkUnique(template.id, "schedule “\(template.name)”")
            if template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append("A schedule has no name.")
            }
            for period in template.periods {
                checkUnique(period.id, "period “\(period.title)”")
                periodIDs.insert(period.id)
            }
            problems += ScheduleValidator.validate(periods: template.periods).map { "\(template.name): \($0.message)" }
        }

        let templateIDs = Set(export.templates.map(\.id))
        problems += ScheduleValidator.validate(
            assignments: export.assignments.map { ($0.weekday, $0.templateID) },
            knownTemplateIDs: templateIDs
        ).map(\.message)

        var overrideDates = Set<LocalDate>()
        for override in export.overrides {
            checkUnique(override.id, "date change on \(override.date.key)")
            if !overrideDates.insert(override.date).inserted {
                problems.append("More than one change for \(override.date.key).")
            }
            if let templateID = override.templateID, !templateIDs.contains(templateID) {
                problems.append("The change on \(override.date.key) refers to a missing schedule.")
            }
            for period in override.periods {
                checkUnique(period.id, "period “\(period.title)”")
                periodIDs.insert(period.id)
            }
            problems += ScheduleValidator.validate(periods: override.periods).map { "\(override.date.key): \($0.message)" }
        }

        for link in export.quicklinks {
            checkUnique(link.id, "Quicklink “\(link.title)”")
            if case .failure(let error) = QuicklinkURLValidator.validate(link.urlString) {
                problems.append("Quicklink “\(link.title)”: \(error.message)")
            }
        }

        for reminder in export.reminders {
            checkUnique(reminder.id, "reminder “\(reminder.title)”")
            if !periodIDs.contains(reminder.periodID) {
                problems.append("Reminder “\(reminder.title)” refers to a missing period.")
            }
            if case .beforeStart(let minutes) = reminder.trigger, !(0...720).contains(minutes) {
                problems.append("Reminder “\(reminder.title)” has an invalid offset.")
            }
            if case .oneOff(_, let time) = reminder.trigger, !time.isWithinDay || time.minutesAfterMidnight == ClockTime.endOfDayMinutes {
                problems.append("Reminder “\(reminder.title)” has an invalid time.")
            }
        }
        return problems
    }
}
