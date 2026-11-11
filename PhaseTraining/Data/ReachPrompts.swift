// ReachPrompts.swift — one-time flags behind the prompts that point at
// features otherwise reachable only from Profile.
//
// Both flags live in UserDefaults under `pt_` keys, so "Erase all data"
// (MemoryStore.wipeAllUserData sweeps the prefix) clears them and the prompts
// can fire again for a fresh start.

import Foundation

enum ReachPrompts {
    /// Set once the user has opened the injuries editor. An empty list is a
    /// legitimate answer, so opening the editor counts as answering.
    static let injuriesAnsweredKey = "pt_injuries_answered"
    /// Set when the weekly-reminder offer has been shown, whatever the answer.
    static let reminderOfferedKey = "pt_weekly_reminder_offered"

    // MARK: Injuries

    /// An injury answer exists when the user listed one, kept a free-text
    /// note, or opened the editor and left it empty.
    static func injuriesAnswered(memory: TrainingMemory,
                                 defaults: UserDefaults = .standard) -> Bool {
        !memory.userInjuries.isEmpty
            || !memory.constraints.isEmpty
            || defaults.bool(forKey: injuriesAnsweredKey)
    }

    static func markInjuriesAnswered(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: injuriesAnsweredKey)
    }

    // MARK: Weekly reminder

    /// Offer the reminder once, when a check-in is the user's first and the
    /// reminder is not already on.
    static func shouldOfferReminder(priorCheckInCount: Int,
                                    reminderEnabled: Bool,
                                    defaults: UserDefaults = .standard) -> Bool {
        priorCheckInCount == 0
            && !reminderEnabled
            && !defaults.bool(forKey: reminderOfferedKey)
    }

    static func markReminderOffered(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: reminderOfferedKey)
    }
}
