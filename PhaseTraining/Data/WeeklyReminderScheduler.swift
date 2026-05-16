// WeeklyReminderScheduler.swift — local notification that nudges the user to
// set the upcoming week's availability + events on Sunday evening.
//
// Wiring:
//   - Profile "Weekly plan reminder" toggle calls enable()/disable()
//   - enable() requests UNAuthorizationOptions [.alert, .badge, .sound] and
//     schedules a UNCalendarNotificationTrigger for Sunday 6:00 PM, repeating
//   - Tap → NotificationDelegate opens phasetraining://week → PhaseTrainingApp
//     .onOpenURL flips RootTabView's selected tab to .week
//   - URL scheme registered via Project.yml info.properties CFBundleURLTypes
//
// `isEnabled` reads a UserDefaults flag (synchronous) instead of calling
// `getPendingNotificationRequests` (async) so the toggle row can render
// without waiting. The flag is set true only on a successful auth+schedule
// and cleared on disable / denial.

import Foundation
import UserNotifications
import UIKit

enum WeeklyReminderScheduler {
    private static let identifier = "pt.weekly_reminder"
    private static let enabledKey = "pt_weekly_reminder_enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Request authorization, then schedule a weekly Sunday 6 PM reminder.
    /// Returns true if scheduled, false if the user denied or scheduling failed.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            granted = false
        }
        guard granted else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Plan your week"
        content.body = "Mark unavailable days and add events for the week ahead."
        content.sound = .default
        content.userInfo = ["deepLink": "phasetraining://week"]

        // weekday: 1 == Sunday in Apple's Gregorian Calendar. Repeats weekly.
        var when = DateComponents()
        when.weekday = 1
        when.hour = 18
        when.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await center.add(request)
            UserDefaults.standard.set(true, forKey: enabledKey)
            return true
        } catch {
            UserDefaults.standard.set(false, forKey: enabledKey)
            return false
        }
    }

    /// Remove the scheduled reminder + clear the flag. Authorization is not
    /// revoked (only the user can do that in Settings).
    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UserDefaults.standard.set(false, forKey: enabledKey)
    }

    /// Attach the shared delegate. Called once from PhaseTrainingApp.init() so
    /// taps that launch the app cold still route through .onOpenURL.
    static func registerDelegate() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show the banner + sound when the app is already in the foreground —
    /// otherwise iOS silently suppresses it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Route the tap through UIApplication.open so the deep link lands on the
    /// single .onOpenURL handler in PhaseTrainingApp.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let raw = response.notification.request.content.userInfo["deepLink"] as? String,
           let url = URL(string: raw) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}
