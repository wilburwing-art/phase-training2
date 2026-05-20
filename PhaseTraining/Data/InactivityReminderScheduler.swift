// InactivityReminderScheduler.swift — local notification that fires 30 min
// after the last logged-set activity in an in-flight workout.
//
// Hook points (SessionStore):
//   - saveActive — every mutation of the active session reschedules the timer
//   - saveCompleted / clearActive — cancel any pending notification
//   - init with restored active session — reschedule fresh (the old one may
//     have already fired or its scheduled time may be stale)
//
// Permission: silent. Piggybacks on the existing notification permission the
// user grants via the Profile "Weekly plan reminder" toggle. If they haven't
// granted permission, this scheduler no-ops — no surprise mid-workout prompt.
// Both notifications use the same UNUserNotificationCenter delegate
// registered by WeeklyReminderScheduler.

import Foundation
import UserNotifications

enum InactivityReminderScheduler {
    static let identifier = "pt.inactivity_reminder"
    /// Time-since-last-activity before the reminder fires. 30 min is the
    /// threshold the user agreed on — short enough to catch "forgot to mark
    /// finish" early, long enough to survive heavy-rest 1RM attempts.
    static let inactivityWindow: TimeInterval = 30 * 60

    /// Reset the inactivity clock to now + 30 min. Idempotent: each call
    /// removes any pending notification with this identifier and registers
    /// fresh, so calling on every saveActive is safe (and intentional — the
    /// timer should reflect the most recent activity).
    static func scheduleForActiveSession() {
        Task.detached(priority: .utility) {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Still training?"
            content.body = "It's been 30 minutes since your last set. Tap to finish up or keep going."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: inactivityWindow,
                repeats: false
            )
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            try? await center.add(request)
        }
    }

    /// Cancel any pending inactivity reminder. Called when the user completes
    /// or clears the active session, or on launch when there's no active
    /// session (drops a stale schedule from a previous run).
    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
