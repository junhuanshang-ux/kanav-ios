import Foundation
import UserNotifications

/// 本地通知：每日更新提醒
final class NotificationManager {

    static let shared = NotificationManager()

    private let identifier = "kanav.daily.update"
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// 每天固定时间提醒
    func scheduleDaily(hour: Int, minute: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "博客 · 今日更新"
        content.body = "新片已经上线，来看看今天有什么"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
