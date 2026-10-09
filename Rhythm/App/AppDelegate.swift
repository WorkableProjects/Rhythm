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
        guard let link = response.notification.request.content.userInfo["deepLink"] as? String,
              let url = URL(string: link) else { return }
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
}
