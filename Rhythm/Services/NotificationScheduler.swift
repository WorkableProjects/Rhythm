import Foundation
import Observation
import RhythmCore
import UIKit
import UserNotifications

/// `NotificationCenterClient` backed by `UNUserNotificationCenter`.
struct SystemNotificationCenter: NotificationCenterClient {
    func authorization() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: return .authorized
        case .provisional: return .provisional
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func add(_ notification: PlannedNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = "rhythm.reminders"
        content.userInfo = ["deepLink": notification.deepLink.absoluteString]
        content.interruptionLevel = .active

        // A calendar trigger keeps the wall-clock meaning if the device clock is adjusted.
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notification.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePending(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Owns reminder permission state and keeps pending notifications in sync with the schedule.
@MainActor
@Observable
final class NotificationScheduler {
    private(set) var authorization: NotificationAuthorization = .notDetermined
    private(set) var lastResult: ReminderReconciliation?

    @ObservationIgnored private let client: any NotificationCenterClient
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?

    init(client: any NotificationCenterClient = SystemNotificationCenter()) {
        self.client = client
    }

    func refreshAuthorization() async {
        authorization = await client.authorization()
    }

    /// Asks for permission only if the user has never been asked. Call this when the user turns
    /// on a reminder, never at launch.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> NotificationAuthorization {
        await refreshAuthorization()
        if authorization == .notDetermined {
            _ = try? await client.requestAuthorization()
            await refreshAuthorization()
        }
        return authorization
    }

    /// Recomputes the plan and reconciles pending requests. Calls are serialized; a newer call
    /// supersedes one that has not started yet.
    func reconcile(reminders: [ReminderDefinition], configuration: ScheduleConfiguration, engine: ScheduleEngine, featureEnabled: Bool) {
        let previous = reconcileTask
        let client = client
        reconcileTask = Task { [weak self] in
            await previous?.value
            let plan = ReminderPlanner(engine: engine).plan(reminders: reminders, configuration: configuration, now: .now)
            let result = await ReminderReconciler(client: client).reconcile(plan: plan, featureEnabled: featureEnabled)
            let status = await client.authorization()
            self?.lastResult = result
            self?.authorization = status
        }
    }

    /// Opens Rhythm's page in the Settings app so the user can change notification permission.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
