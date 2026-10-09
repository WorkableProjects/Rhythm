import Foundation
import SwiftData

// MARK: - Schema versions and migration plan
//
// Rhythm's persisted shape is versioned from the first release.
//
// To change a model:
// 1. Copy the current model classes into a nested namespace for the old version
//    (e.g. `enum RhythmSchemaV1 { @Model final class ScheduleTemplate { … } }`) so the old
//    shape stays compilable.
// 2. Add `RhythmSchemaV2` listing the new top-level models.
// 3. Append it to `RhythmMigrationPlan.schemas` and add a `MigrationStage` (lightweight when
//    SwiftData can infer it, custom otherwise).
// 4. Bump `RhythmExport.currentSchemaVersion` only if the *export* DTO changes; the export
//    format is versioned independently of the database.

enum RhythmSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ScheduleTemplate.self, SchedulePeriod.self, WeekdayAssignment.self, ScheduleOverride.self, ReminderRule.self, Quicklink.self]
    }
}

enum RhythmMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RhythmSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Creates the app's single `ModelContainer`.
enum PersistenceController {
    /// Launch argument used by UI tests to run against an empty in-memory store.
    static let uiTestingArgument = "-RhythmUITesting"

    struct Loaded: Sendable {
        let container: ModelContainer
        /// A user-facing description when the on-disk store could not be opened and Rhythm fell
        /// back to a temporary in-memory store.
        let recoveryMessage: String?
    }

    static let shared: Loaded = load(inMemory: ProcessInfo.processInfo.arguments.contains(uiTestingArgument))

    static func load(inMemory: Bool) -> Loaded {
        let schema = Schema(versionedSchema: RhythmSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: RhythmMigrationPlan.self, configurations: [configuration])
            return Loaded(container: container, recoveryMessage: nil)
        } catch {
            // Never crash on a damaged or partially migrated store. Run with a temporary store
            // and tell the user; their file is left untouched for a later fix.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                let container = try ModelContainer(for: schema, configurations: [fallback])
                return Loaded(container: container, recoveryMessage: "Rhythm couldn’t open its saved data, so changes won’t be kept this session. (\(error.localizedDescription))")
            } catch {
                fatalError("Unable to create even an in-memory store: \(error)")
            }
        }
    }
}
