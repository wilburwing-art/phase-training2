// WeeklyReminderScheduler.swift — stub for the weekly "set this week's
// availability" push notification.
//
// The user wants a Sunday-evening (or similar) reminder that opens directly
// to the Week tab so they can mark unavailable days + add events for the
// upcoming week. Wiring this requires:
//
//   1. UNUserNotificationCenter permission request (UNAuthorizationOptions:
//      .alert, .badge, .sound). Trigger from a Profile-level "Reminders"
//      toggle, not on launch.
//   2. UNTimeIntervalNotificationTrigger or UNCalendarNotificationTrigger for
//      the Sunday 6pm cadence (TimeZone-aware via Calendar).
//   3. Notification payload userInfo: { "deepLink": "phasetraining://week" }
//      so PhaseTrainingApp can switch to .week on tap.
//   4. URL scheme registration in Info.plist (CFBundleURLTypes).
//   5. .onOpenURL handler in PhaseTrainingApp that maps phasetraining://week
//      → RootTabView.selected = .week.
//
// All deferred until the next round; this file exists to make the wire-up
// surface explicit.

import Foundation

enum WeeklyReminderScheduler {
    /// Permission gate. Returns true if reminders are currently scheduled.
    /// TODO: wire to UNUserNotificationCenter.current().notificationSettings().
    static var isEnabled: Bool { false }

    /// TODO: request authorization + schedule a weekly Sunday reminder.
    static func enable() {
        // No-op stub.
    }

    /// TODO: cancel any scheduled weekly reminder.
    static func disable() {
        // No-op stub.
    }
}
