import Foundation
import RhythmCore
import UserNotifications
import WidgetKit

/// Reminder operations that must work from any process: the app, a widget button, a Shortcut, or
/// a notification action. Each one edits the shared file, re-plans notifications, and reloads
/// the reminder widgets.
enum ReminderActions {
    static var store: NativeReminderFileStore { NativeReminderFileStore(url: SharedStorage.remindersURL) }

    /// Completes (or advances, for a repeating reminder) the reminder with `id`.
    @discardableResult
    static func complete(_ id: UUID, now: Date = .now) async -> CompletionOutcome? {
        var outcome: CompletionOutcome?
        await apply { library in
            guard let reminder = library.reminder(id), !reminder.isCompleted else { return }
            outcome = library.toggleCompletion(of: id, now: now, calendar: .autoupdatingCurrent)
        }
        return outcome
    }

    /// Moves a reminder's due time `minutes` from now (snooze).
    static func snooze(_ id: UUID, minutes: Int = 60, now: Date = .now) async {
        let calendar = Calendar.autoupdatingCurrent
        let target = now.addingTimeInterval(TimeInterval(minutes * 60))
        let components = calendar.dateComponents([.hour, .minute], from: target)
        await apply { library in
            library.reschedule(id, to: LocalDate(target, calendar: calendar),
                               time: ClockTime(hour: components.hour ?? 9, minute: components.minute ?? 0))
        }
    }

    @discardableResult
    static func add(title: String, dueDate: LocalDate? = nil, dueTime: ClockTime? = nil, listID: UUID? = nil) async -> NativeReminder? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var created: NativeReminder?
        await apply { library in
            let reminder = NativeReminder(title: trimmed, listID: listID ?? library.defaultListID, dueDate: dueDate, dueTime: dueTime)
            library.add(reminder)
            created = reminder
        }
        return created
    }

    /// Applies `change` to the stored library, then refreshes notifications and widgets.
    static func apply(_ change: (inout NativeReminderLibrary) -> Void) async {
        guard let library = try? store.mutate(change) else { return }
        await ReminderNotifications.reconcile(library: library)
        reloadWidgets()
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.remindersWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.addReminderWidgetKind)
    }
}

/// Keeps pending notifications for native reminders in line with the library. Uses its own
/// identifier prefix, so it never touches the schedule-linked reminder notifications.
enum ReminderNotifications {
    static let categoryIdentifier = "rhythm.task"
    static let completeActionIdentifier = "rhythm.task.complete"
    static let snoozeActionIdentifier = "rhythm.task.snooze"
    private static let enabledKey = "nativeReminderAlertsEnabled"

    private static var defaults: UserDefaults {
        SharedStorage.appGroupIdentifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The user's switch for due-date alerts. Stored in the App Group so widgets and Shortcuts see it.
    static var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// Registers the "Complete" and "Snooze" actions shown on reminder notifications.
    static func registerCategory() {
        let complete = UNNotificationAction(identifier: completeActionIdentifier, title: "Complete", options: [])
        let snooze = UNNotificationAction(identifier: snoozeActionIdentifier, title: "Snooze 1 Hour", options: [])
        let category = UNNotificationCategory(identifier: categoryIdentifier, actions: [complete, snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var categories = existing.filter { $0.identifier != categoryIdentifier }
            categories.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(categories)
        }
    }

    static func reconcile(library: NativeReminderLibrary, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(ReminderNotificationPlan.identifierPrefix) }

        let settings = await center.notificationSettings()
        let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        guard isEnabled, allowed else {
            if !pending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: pending) }
            return
        }

        let plan = NativeReminderPlanner(calendar: .autoupdatingCurrent).plan(library: library, now: now)
        let wanted = Set(plan.map(\.id))
        let stale = pending.filter { !wanted.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        let existing = Set(pending)
        for item in plan where !existing.contains(item.id) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = "rhythm.tasks"
            content.categoryIdentifier = categoryIdentifier
            content.userInfo = ["deepLink": item.deepLink.absoluteString, "reminderID": item.reminderID.uuidString]
            let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}
