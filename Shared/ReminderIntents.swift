import AppIntents
import Foundation
import RhythmCore
import WidgetKit

// Intents for native reminders that run in the widget extension as well as the app, so a tap on a
// widget changes the shared file without launching Rhythm.

/// Completes one reminder. Used by the checkmark buttons in Rhythm's reminder widgets.
struct CompleteReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Reminder"
    static let description = IntentDescription("Marks a Rhythm reminder as complete.")
    static let isDiscoverable = false

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {}

    init(reminderID: UUID) {
        self.reminderID = reminderID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: reminderID) {
            await ReminderActions.complete(id)
        }
        return .result()
    }
}

/// A reminder list, for choosing what a widget or Shortcut shows.
struct ReminderListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Reminder List"
    static var defaultQuery: ReminderListQuery { ReminderListQuery() }

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ReminderListQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ReminderListEntity] {
        let wanted = Set(identifiers)
        return ReminderActions.store.load().sortedLists.filter { wanted.contains($0.id) }.map { ReminderListEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [ReminderListEntity] {
        ReminderActions.store.load().sortedLists.map { ReminderListEntity(id: $0.id, name: $0.name) }
    }
}

/// Configuration for the Reminders widget: which list to show.
struct RemindersWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Reminders"
    static let description = IntentDescription("Choose a list, or leave it empty to show what’s due today.")

    @Parameter(title: "List")
    var list: ReminderListEntity?

    init() {}
}
