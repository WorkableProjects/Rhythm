import Foundation
import Observation
import RhythmCore

/// The in-app view of native reminders. The JSON file in the App Group is the source of truth
/// (widgets and Shortcuts edit it too); this model mirrors it for SwiftUI, and every edit goes
/// through the file so it can never overwrite a change made elsewhere.
@MainActor
@Observable
final class RemindersModel {
    private(set) var library: NativeReminderLibrary
    var errorMessage: String?

    @ObservationIgnored private let store: NativeReminderFileStore
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    /// Asks for notification permission the first time a dated reminder is saved.
    @ObservationIgnored var requestAuthorization: () async -> Void = {}

    init(store: NativeReminderFileStore = ReminderActions.store) {
        self.store = store
        library = store.load()
    }

    /// Picks up changes made by a widget, Shortcut, or notification action.
    func reload() {
        let latest = store.load()
        if latest != library { library = latest }
    }

    /// Re-plans notifications and reloads widgets from the current library.
    func sync(requestingAuthorization: Bool = false) {
        let library = library
        let previous = syncTask
        let authorize = requestAuthorization
        syncTask = Task {
            await previous?.value
            if requestingAuthorization, ReminderNotifications.isEnabled { await authorize() }
            await ReminderNotifications.reconcile(library: library)
            ReminderActions.reloadWidgets()
        }
    }

    /// Applies an edit through the file. Returns `false` (and reports) if it could not be saved.
    @discardableResult
    func edit(requestingAuthorization: Bool = false, _ change: (inout NativeReminderLibrary) -> Void) -> Bool {
        do {
            library = try store.mutate(change)
            errorMessage = nil
            sync(requestingAuthorization: requestingAuthorization)
            return true
        } catch {
            errorMessage = "Rhythm couldn’t save your reminders. \(error.localizedDescription)"
            reload()
            return false
        }
    }

    // MARK: Convenience edits

    func save(_ reminder: NativeReminder) {
        edit(requestingAuthorization: reminder.dueDate != nil) { $0.update(reminder) }
    }

    func toggle(_ id: UUID, now: Date, calendar: Calendar) {
        edit { $0.toggleCompletion(of: id, now: now, calendar: calendar) }
    }

    func toggleFlag(_ id: UUID) {
        edit { library in
            guard var reminder = library.reminder(id) else { return }
            reminder.isFlagged.toggle()
            library.update(reminder)
        }
    }

    func toggleSubtask(_ subtaskID: UUID, in id: UUID) {
        edit { $0.toggleSubtask(subtaskID, in: id) }
    }

    func delete(_ ids: Set<UUID>) {
        edit { $0.deleteReminders(ids) }
    }

    func saveList(_ list: NativeReminderList) {
        edit { $0.addList(list) }
    }

    func deleteList(_ id: UUID) {
        edit { $0.deleteList(id) }
    }

    func clearCompleted(in listID: UUID? = nil) {
        edit { $0.deleteCompleted(in: listID) }
    }

    /// Adds a reminder from a typed phrase ("Essay tomorrow 3pm !high #Homework").
    @discardableResult
    func quickAdd(_ text: String, defaultListID: UUID?, defaultDate: LocalDate? = nil, defaultFlagged: Bool = false,
                  today: LocalDate, calendar: Calendar) -> NativeReminder? {
        let parsed = ReminderQuickAdd.parse(text, today: today, calendar: calendar)
        guard !parsed.title.isEmpty else { return nil }
        var created: NativeReminder?
        let dueDate = parsed.dueDate ?? defaultDate
        edit(requestingAuthorization: dueDate != nil) { library in
            let named = parsed.listName.flatMap { name in
                library.lists.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
            }
            let reminder = NativeReminder(title: parsed.title,
                                          listID: named?.id ?? defaultListID ?? library.defaultListID,
                                          dueDate: dueDate, dueTime: parsed.dueTime,
                                          priority: parsed.priority, isFlagged: parsed.isFlagged || defaultFlagged)
            library.add(reminder)
            created = reminder
        }
        return created
    }

    /// Removes every reminder and list ("Delete All Data").
    func deleteAll() {
        store.remove()
        library = .empty
        sync()
    }
}
