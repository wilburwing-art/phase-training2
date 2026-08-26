// WeeklyReminderScheduler.swift — local notification that nudges the user to
// set the upcoming week's availability + events on Sunday evening.
//
// Wiring:
//   - Profile "Weekly plan reminder" toggle calls enable()/disable()
//   - enable() requests UNAuthorizationOptions [.alert, .badge, .sound] and
//     schedules a UNCalendarNotificationTrigger for Sunday 6:00 PM, repeating
//   - Tap → NotificationDelegate opens phasetraining://plan-week →
//     PhaseTrainingApp .onOpenURL pops the WeeklyCheckInFlow on top of the
//     Today tab so the user walks through intent → days off → events →
//     feedback → preview before the planner regenerates next week's plan
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
    /// Internal so MemoryStore.wipeAllUserData can cancel it by name rather
    /// than repeating the string literal.
    static let identifier = "pt.weekly_reminder"
    private static let enabledKey = "pt_weekly_reminder_enabled"
    /// D1 — quick-action category for the Sunday push. Day-count buttons set
    /// memory.liftDaysPerWeek + regenerate via the `set-lift-days` deep link;
    /// "Open to edit" falls back to the full planning flow.
    static let categoryId = "pt.weekly_reminder.actions"
    private static let actionPrefix = "pt.lift_days."
    private static let liftDayChoices = [2, 3, 4]

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
        content.body = "How many days can you train this week?"
        content.sound = .default
        content.userInfo = ["deepLink": "phasetraining://plan-week"]
        content.categoryIdentifier = categoryId

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
        UNUserNotificationCenter.current().setNotificationCategories([makeCategory()])
    }

    /// D1 — day-count quick actions ("2 days" … "4 days" + "Open to edit").
    private static func makeCategory() -> UNNotificationCategory {
        var actions = liftDayChoices.map { n in
            UNNotificationAction(identifier: "\(actionPrefix)\(n)",
                                 title: "\(n) days", options: [.foreground])
        }
        actions.append(UNNotificationAction(identifier: "\(actionPrefix)open",
                                            title: "Open to edit", options: [.foreground]))
        return UNNotificationCategory(identifier: categoryId, actions: actions,
                                      intentIdentifiers: [], options: [])
    }

    /// Map a quick-action identifier to its deep link. Day-count actions →
    /// `set-lift-days?n=N`; "open" → the full planning flow. nil for anything
    /// not one of our actions (caller falls back to the notification's
    /// userInfo deepLink). Pure + static for unit testing.
    static func deepLink(forAction actionId: String) -> String? {
        guard actionId.hasPrefix(actionPrefix) else { return nil }
        let suffix = String(actionId.dropFirst(actionPrefix.count))
        if let n = Int(suffix) { return "phasetraining://set-lift-days?n=\(n)" }
        return "phasetraining://plan-week"   // "open"
    }

    /// Parse the lift-day count out of a `set-lift-days?n=N` deep link. nil if
    /// the URL isn't that link or has no integer `n`. Pure + static for tests
    /// and the .onOpenURL handler.
    static func liftDays(fromDeepLink url: URL) -> Int? {
        guard url.scheme == "phasetraining", url.host == "set-lift-days",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "n" })?.value else { return nil }
        return Int(raw)
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
        // D1 — a day-count quick action maps to its own deep link; a plain tap
        // (UNNotificationDefaultActionIdentifier) falls back to the
        // notification's userInfo deepLink.
        let raw = WeeklyReminderScheduler.deepLink(forAction: response.actionIdentifier)
            ?? (response.notification.request.content.userInfo["deepLink"] as? String)
        if let raw, let url = URL(string: raw) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}
