// PermissionPrePrompt.swift — one-time offers that come before Apple's
// permission sheets. Pure decisions over UserDefaults so they test without UI.
//
// Either button on an offer marks it answered, so each card shows once.

import Foundation
import UserNotifications

enum NotificationPrePrompt {
    static let answeredKey = "pt.prePrompt.notifications.answered"

    static func shouldOffer(completedSessions: Int,
                            status: UNAuthorizationStatus,
                            defaults: UserDefaults = .standard) -> Bool {
        completedSessions >= 1
            && status == .notDetermined
            && !defaults.bool(forKey: answeredKey)
    }

    static func markAnswered(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: answeredKey)
    }
}

enum RecoveryCapturePrePrompt {
    static let answeredKey = "pt.prePrompt.recovery.answered"

    static func shouldOffer(captureEnabled: Bool,
                            defaults: UserDefaults = .standard) -> Bool {
        !captureEnabled && !defaults.bool(forKey: answeredKey)
    }

    static func markAnswered(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: answeredKey)
    }
}
