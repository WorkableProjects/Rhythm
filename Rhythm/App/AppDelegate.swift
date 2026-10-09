import UIKit
import UserNotifications

/// Handles notification presentation and taps. Tapping a reminder opens its `rhythm://` deep
/// link, which SwiftUI routes through `onOpenURL`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if let id = (userInfo["reminderID"] as? String).flatMap(UUID.init(uuidString:)) {
            switch response.actionIdentifier {
            case ReminderNotifications.completeActionIdentifier:
                await ReminderActions.complete(id)
                return
            case ReminderNotifications.snoozeActionIdentifier:
                await ReminderActions.snooze(id)
                return
            default:
                break
            }
        }
        guard let link = userInfo["deepLink"] as? String,
              let url = URL(string: link) else { return }
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
}
