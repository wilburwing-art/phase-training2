// GoalMilestoneNotifier.swift — PR 11 (commit 4) of the weekly-coach roadmap.
//
// When a goal's progress crosses 100%, fire ONE celebratory push. Governed
// by the PR-12 budget (class .coachMilestone — lowest priority, first
// dropped on a busy day) plus its own 2-per-week cap: milestones are rare
// by nature, but a user picking two goals and hitting both in a week
// shouldn't stack three pushes with a PR the same Friday.
//
// Architecture mirrors NotificationBudget: pure decision logic (testable,
// no UNUserNotificationCenter), with the delivery side effect explicit in
// `notifyIfCrossed` at the call site. Crossing detection is edge-triggered:
// we persist each goal's best-seen progress and fire only when progress
// reaches 1.0 while the last seen value was BELOW 1.0. Re-achieving after
// a bodyweight change resetting the ratio can fire again — that's correct
// (the user earned it twice), but the persisted floor keeps a single
// achievement from re-firing on every app open.
//
// Call site: CompleteScreen after the session save (the moment new data —
// a new e1RM, a logged 5k — could tip a goal over the line).

import Foundation
import UserNotifications

enum GoalMilestoneNotifier {

    /// Best progress seen per goal id. Persisted so crossing detection
    /// survives app restarts.
    static let seenProgressKey = "pt_goal_progress_seen"
    /// Timestamps of milestones actually fired (delivery attempts that
    /// passed the budget gate). Drives the 2-per-week cap.
    static let firedKey = "pt_goal_milestone_fired"
    /// Milestone pushes allowed per rolling 7 days.
    static let weeklyCap = 2

    // MARK: - Decision (pure, unit-testable)

    /// Should a milestone fire for `goal` given its current progress?
    ///
    /// True exactly when progress >= 1.0 AND the persisted best-seen for
    /// this goal is below 1.0 (first crossing) AND the weekly cap allows.
    /// Callers still pass the result through NotificationBudget.authorize
    /// via `notifyIfCrossed`; this function does NOT record anything.
    static func shouldFire(goalId: UUID,
                           progress: Double,
                           now: Date = Date(),
                           defaults: UserDefaults = .standard,
                           calendar: Calendar = .current) -> Bool {
        guard progress >= 1.0 else { return false }
        let seen = seenProgress(defaults: defaults)[goalId.uuidString] ?? 0
        guard seen < 1.0 else { return false }
        return firedWithinWeek(now: now, defaults: defaults, calendar: calendar).count < weeklyCap
    }

    /// Persisted best-seen progress per goal id (goal uuid string → 0...1).
    static func seenProgress(defaults: UserDefaults = .standard) -> [String: Double] {
        guard let raw = defaults.dictionary(forKey: seenProgressKey) as? [String: Double] else {
            return [:]
        }
        return raw
    }

    /// Milestone fire timestamps within the trailing 7 days.
    static func firedWithinWeek(now: Date = Date(),
                                defaults: UserDefaults = .standard,
                                calendar: Calendar = .current) -> [Date] {
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        return firedLog(defaults: defaults).filter { $0 >= cutoff }
    }

    static func firedLog(defaults: UserDefaults = .standard) -> [Date] {
        guard let data = defaults.data(forKey: firedKey),
              let dates = try? JSONDecoder().decode([Date].self, from: data) else { return [] }
        return dates
    }

    // MARK: - Recording

    /// Record the best-seen progress for a goal (call whether or not a
    /// milestone fired — the floor must advance to keep a single
    /// achievement from re-firing on every open).
    static func recordSeen(goalId: UUID, progress: Double, defaults: UserDefaults = .standard) {
        var seen = seenProgress(defaults: defaults)
        let key = goalId.uuidString
        seen[key] = max(seen[key] ?? 0, progress)
        defaults.set(seen, forKey: seenProgressKey)
    }

    /// Record that a milestone push was sent (call only after a successful
    /// center.add, same contract as NotificationBudget.recordDelivered).
    static func recordFired(now: Date = Date(), defaults: UserDefaults = .standard) {
        var log = firedLog(defaults: defaults)
        log.append(now)
        if let data = try? JSONEncoder().encode(log) {
            defaults.set(data, forKey: firedKey)
        }
    }

    // MARK: - Delivery

    /// Evaluate every active goal after a save; for each that just crossed
    /// 100% (and passes the budget + weekly cap), send one push. Records
    /// best-seen progress for ALL goals regardless, so the crossing edge
    /// is always consumed.
    static func notifyIfCrossed(goals: [UserGoal],
                                progress: (UserGoal) -> Double?,
                                now: Date = Date(),
                                defaults: UserDefaults = .standard) async {
        for goal in goals {
            let p = progress(goal) ?? 0
            defer { recordSeen(goalId: goal.id, progress: p, defaults: defaults) }
            guard shouldFire(goalId: goal.id, progress: p, now: now, defaults: defaults),
                  NotificationBudget.authorize(cls: .coachMilestone, now: now, defaults: defaults)
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Goal reached"
            content.body = "\(goal.templateId.label) — you did it."
            content.sound = .default
            content.userInfo = ["deepLink": "phasetraining://progress"]

            let request = UNNotificationRequest(
                identifier: "pt.goal_milestone.\(goal.id.uuidString)",
                content: content,
                trigger: nil   // fire immediately
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                NotificationBudget.recordDelivered(cls: .coachMilestone, now: now, defaults: defaults)
                recordFired(now: now, defaults: defaults)
            } catch {
                // Delivery failed: don't record fired (cap not spent), but
                // the seen-floor already advanced — a failed push doesn't
                // re-fire later, which would be worse than missing one.
            }
        }
    }
}
