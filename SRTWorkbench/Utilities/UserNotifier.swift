import AppKit
import Foundation
import UserNotifications

/// Posts macOS user notifications for long-running work (alignment runs take
/// minutes; users switch away). Notifications are only shown when the app is
/// in the background — when it's frontmost the in-app UI already says it all.
enum UserNotifier {
    private static var authorizationRequested = false

    /// Ask once, lazily, right before the first long-running job.
    static func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logWarn(.app, "notification authorization failed: \(error.localizedDescription)")
            } else {
                log(.app, "notification authorization granted: \(granted)")
            }
        }
    }

    /// Post a notification, but only if the app isn't frontmost.
    @MainActor
    static func notifyIfInBackground(title: String, body: String) {
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logWarn(.app, "failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}
