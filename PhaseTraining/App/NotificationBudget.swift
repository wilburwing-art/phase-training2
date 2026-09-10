// NotificationBudget.swift — PR 12 of the weekly-coach roadmap:
// notification governance.
//
// Before this module, every notification source scheduled its pushes
// independently. A heavy day could stack a weekly-plan nudge + a
// missed-workout push + a coach milestone + a rest-timer alert — four
// interruptions in an afternoon, and the user's finger drifts toward
// Settings → Notifications → Off. The budget exists to keep the app
// sounding AT MOST 3 times per day, spend the budget on the most
// important pushes first, and stop firing a class the user keeps
// dismissing.
//
// Design (spec PLAN-weekly-coach.md §7):
//   - Hard cap: 3 delivered pushes per calendar day.
//   - Priority order on overflow: missed-workout > weekly plan > coach
//     milestone. In-app banners are unaffected (they don't count — the
//     cap exists to protect the user's attention OFF the screen).
//   - Suppression: 3 dismissals of the same class within 14 days stops
//     that class firing (the user has voted with their swipes).
//   - Per-class kill switch from Settings.
//
// Pure decision logic + UserDefaults persistence. UNUserNotificationCenter
// is NOT referenced here — callers pass what they want to send and this
// module answers "may I, and what should be dropped". That keeps it fully
// unit-testable (the center has no test double) and keeps the one side
// effect (recording a send) explicit at the call site.
//
// Integration contract: every push-notification call site asks
// `NotificationBudget.authorize(class:)` BEFORE scheduling and calls
// `recordDelivered(class:)` after `center.add` succeeds. Dismissal
// recording happens in NotificationDelegate.willPresent/
// didReceive via `recordDismissal(class:)`.

import Foundation

enum NotificationBudget {

    /// Push notification classes. Order matters: this is the priority
    /// order used to spend the daily budget (most important first).
    enum Class: String, Codable, CaseIterable {
        case missedWorkout   // autopilot found a missed day — action needed
        case weeklyPlan      // Sunday "plan your week" nudge
        case coachMilestone  // PRs, goal progress, streak celebrations
        case operational     // rest-timer expiry, inactivity nudge — session-scoped

        var label: String {
            switch self {
            case .missedWorkout:  return "Missed workout alerts"
            case .weeklyPlan:     return "Weekly plan reminder"
            case .coachMilestone: return "Coach milestones"
            case .operational:    return "Workout timers"
            }
        }

        /// Priority for daily-budget overflow. Lower = spent first.
        /// Operational (rest timer / inactivity) is always allowed — it
        /// only fires while a workout is literally in flight, and
        /// suppressing it would break the workout UX the user chose.
        var priority: Int {
            switch self {
            case .operational:    return 0
            case .missedWorkout:  return 1
            case .weeklyPlan:     return 2
            case .coachMilestone: return 3
            }
        }
    }

    /// Hard cap on delivered pushes per calendar day (operational class
    /// exempt — see priority above).
    static let dailyCap = 3

    /// Dismissals of the same class within the suppression window that
    /// stop that class from firing.
    static let dismissalThreshold = 3
    /// How far back dismissals are counted.
    static let suppressionWindowDays = 14

    // MARK: - Persistence keys (UserDefaults, app group-safe)

    static func deliveredKey(for day: Date, calendar: Calendar = .current) -> String {
        let dayStart = calendar.startOfDay(for: day)
        return "pt_notif_delivered_\(Int(dayStart.timeIntervalSince1970))"
    }
    static let dismissalsKey = "pt_notif_dismissals"
    static let disabledClassesKey = "pt_notif_disabled_classes"

    // MARK: - Authorization (the ask)

    /// May a push of `cls` be delivered right now?
    ///
    /// Checks, in order: class not user-disabled, not suppressed by
    /// dismissals, under the daily cap (operational exempt).
    static func authorize(cls: Class,
                          now: Date = Date(),
                          defaults: UserDefaults = .standard,
                          calendar: Calendar = .current) -> Bool {
        // 1. User disabled the class entirely (Settings toggle).
        if disabledClasses(defaults: defaults).contains(cls) { return false }
        // 2. Suppression: user dismissed this class 3+ times in window.
        let dismissals = recentDismissals(of: cls, now: now, defaults: defaults, calendar: calendar)
        if dismissals >= dismissalThreshold { return false }
        // 3. Daily cap — operational notifications bypass (session-scoped).
        if cls != .operational {
            let delivered = deliveredCount(now: now, defaults: defaults, calendar: calendar)
            guard delivered < dailyCap else { return false }
        }
        return true
    }

    // MARK: - Recording (the bookkeeping)

    /// Record that a push of `cls` was delivered (call AFTER center.add
    /// succeeds). Prunes the previous day's counter lazily.
    static func recordDelivered(cls: Class,
                                now: Date = Date(),
                                defaults: UserDefaults = .standard,
                                calendar: Calendar = .current) {
        guard cls != .operational else { return }  // exempt from cap bookkeeping
        let key = deliveredKey(for: now, calendar: calendar)
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
        pruneOldDeliveryCounters(now: now, defaults: defaults, calendar: calendar)
    }

    /// Record a user dismissal of a push of `cls`. Called from
    /// NotificationDelegate.didReceive when the user dismissed/tapped-
    /// cleared without acting, and from the banner swipe paths.
    static func recordDismissal(cls: Class,
                                now: Date = Date(),
                                defaults: UserDefaults = .standard) {
        var log = dismissalLog(defaults: defaults)
        log.append((cls: cls, at: now))
        let entries: [Entry] = log.map { Entry(cls: $0.cls.rawValue, at: $0.at) }
        let data = try? JSONEncoder().encode(entries)
        defaults.set(data, forKey: dismissalsKey)
    }

    /// Toggle a class on/off from Settings. Persists the choice.
    static func setEnabled(_ enabled: Bool, for cls: Class,
                           defaults: UserDefaults = .standard) {
        var set = disabledClasses(defaults: defaults)
        if enabled {
            set.remove(cls)
        } else {
            set.insert(cls)
        }
        let raw = set.map(\.rawValue)
        defaults.set(raw, forKey: disabledClassesKey)
    }

    // MARK: - Queries (for the Settings screen)

    static func isEnabled(_ cls: Class, defaults: UserDefaults = .standard) -> Bool {
        !disabledClasses(defaults: defaults).contains(cls)
    }

    static func deliveredCount(now: Date, defaults: UserDefaults = .standard,
                               calendar: Calendar = .current) -> Int {
        defaults.integer(forKey: deliveredKey(for: now, calendar: calendar))
    }

    static func recentDismissals(of cls: Class, now: Date,
                                 defaults: UserDefaults = .standard,
                                 calendar: Calendar = .current) -> Int {
        let cutoff = now.addingTimeInterval(-Double(suppressionWindowDays) * 86_400)
        return dismissalLog(defaults: defaults)
            .filter { $0.cls == cls && $0.at >= cutoff }
            .count
    }

    /// Dismissal entries within the suppression window. 14 days — a
    /// user who dismissed 3 pushes this fortnight is done hearing them.
    // MARK: - Internals

    static func disabledClasses(defaults: UserDefaults = .standard) -> Set<Class> {
        guard let raw = defaults.stringArray(forKey: disabledClassesKey) else { return [] }
        return Set(raw.compactMap(Class.init(rawValue:)))
    }

    struct Entry: Codable {
        let cls: String
        let at: Date
    }

    static func dismissalLog(defaults: UserDefaults = .standard) -> [(cls: Class, at: Date)] {
        guard let data = defaults.data(forKey: dismissalsKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.compactMap { e in
            guard let cls = Class(rawValue: e.cls) else { return nil }
            return (cls, e.at)
        }
    }

    private static func pruneOldDeliveryCounters(now: Date,
                                                 defaults: UserDefaults,
                                                 calendar: Calendar) {
        // Keep today + yesterday (timezone edges); drop everything older.
        let keep: Set<String> = [
            deliveredKey(for: now, calendar: calendar),
            deliveredKey(for: now.addingTimeInterval(-86_400), calendar: calendar),
        ]
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pt_notif_delivered_") {
            if !keep.contains(key) { defaults.removeObject(forKey: key) }
        }
    }
}
