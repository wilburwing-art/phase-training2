// MissedWorkoutAutopilot.swift — PR 8 of the weekly-coach roadmap.
//
// Pure deterministic rule engine for missed-workout handling. Two
// public entry points:
//
//   1. `detect(plan:sessions:overrides:now:)` — returns the list of
//      planned-but-not-completed dates that warrant a banner. A day
//      qualifies as missed when:
//        * its planned kind was .lift or .sport
//        * its date is fully in the past (strictly before today)
//        * the user didn't mark the day as unavailable
//        * the user didn't override it to .rest
//        * SessionStore has no SavedSession whose calendar day matches
//
//   2. `proposeReshuffle(missedDate:plan:memory:overrides:budget:now:)`
//      — returns a `[PlanEdit]` (possibly empty) that moves the missed
//      workout to the best available future day this week. Honors the
//      spec §3 rules:
//
//        Rule 1. Drop if 4+ lift days planned this week
//        Rule 2. Body-part priority — preserve coverage when possible
//        Rule 3. No stacking — never reschedule onto the day after
//                another hard day
//        Rule 4. Respect user intent — skip user-protected / rest
//                overrides / event days
//        Rule 5. Reshuffle budget — caller passes the remaining slots
//                (cap is 2/week, enforced by PlanStore)
//
//      When no valid target exists, returns `[]`. Caller logs a
//      `MissedWorkoutEntry` with `.dropped` resolution in that case.
//
// All pure functions. No state. Easy to test against synthetic plans.

import Foundation

enum MissedWorkoutAutopilot {

    // MARK: - Detection

    /// Surface every planned lift/sport day in this week that's
    /// already passed without a logged session. Days are returned in
    /// chronological order. Only dates the caller hasn't already
    /// logged into `MissedWorkoutEntry[]` should be acted on — this
    /// function doesn't dedupe against history.
    static func detect(
        plan: WeekPlan,
        sessions: [SavedSession],
        overrides: WeekOverrides,
        /// Logged sport sessions. A `.sport` day qualifies as missed below, but
        /// only LIFT history was consulted — so a user who planned Tuesday
        /// climbing, went climbing, and logged it through SportLogSheet still
        /// got a "you missed Tuesday" banner the next morning, offering a
        /// reshuffle for a workout they had completed.
        sportLogs: [SportLogEntry] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayPlan] {
        let today = calendar.startOfDay(for: now)
        // Set of calendar days that already have a logged session
        let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0.startTime) })
            .union(sportLogs.map { calendar.startOfDay(for: $0.date) })

        return plan.days.filter { day in
            guard day.kind == .lift || day.kind == .sport else { return false }
            let dayStart = calendar.startOfDay(for: day.date)
            // Strictly in the past — today still has time to complete.
            guard dayStart < today else { return false }
            // User-marked unavailable for this weekday → not missed.
            let weekday = Weekday.from(date: day.date, calendar: calendar)
            if overrides.unavailableDays.contains(weekday) { return false }
            // User overrode the day to rest → intentional skip, not missed.
            if let ov = overrides.override(on: day.date, calendar: calendar),
               ov.asKind == .rest {
                return false
            }
            // Already logged a session on this day → completed.
            if sessionDays.contains(dayStart) { return false }
            return true
        }
    }

    // MARK: - Reshuffle proposal

    /// Threshold for the drop-rule (spec §3 rule 1). When the week
    /// has ≥4 planned lift days, missing one doesn't trigger a
    /// reshuffle — the rest of the week stays uncrowded.
    static let dropThresholdLiftDaysPerWeek = 4

    /// Returns either `[.move(dayId: missedId, toDate: targetDate)]`
    /// or `[]` when the autopilot decided not to reshuffle (drop rule,
    /// budget exhausted, or no valid target).
    static func proposeReshuffle(
        missedDate: Date,
        plan: WeekPlan,
        overrides: WeekOverrides,
        remainingBudget: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlanEdit] {
        // Budget guard: caller's reshuffle counter has already hit 2/week.
        guard remainingBudget > 0 else { return [] }

        // Drop rule: if the user planned 4+ lift days this week, don't
        // crowd the rest. We still log the miss; we just don't move it.
        let plannedLifts = plan.days.filter { $0.kind == .lift }.count
        if plannedLifts >= dropThresholdLiftDaysPerWeek { return [] }

        // Find the missed day's metadata in the plan.
        let missedDay = plan.days.first { calendar.isDate($0.date, inSameDayAs: missedDate) }
        guard let missedDay else { return [] }

        // Candidate target: future rest day this week, not user-locked,
        // not stacked next to another hard day.
        let today = calendar.startOfDay(for: now)
        let candidates = plan.days.enumerated().compactMap { idx, day -> (Int, DayPlan)? in
            guard day.kind == .rest else { return nil }
            let d = calendar.startOfDay(for: day.date)
            // Today and beyond — past rest days can't host a future workout.
            guard d >= today else { return nil }
            // User-protected (locked) → respect.
            if day.protected { return nil }
            // Unavailable weekday → respect.
            let weekday = Weekday.from(date: day.date, calendar: calendar)
            if overrides.unavailableDays.contains(weekday) { return nil }
            // Day override forces .rest → respect.
            if let ov = overrides.override(on: day.date, calendar: calendar),
               ov.asKind == .rest {
                return nil
            }
            return (idx, day)
        }

        // No-stacking filter: drop candidates where the prior day is
        // also a hard day. The missed date itself isn't "hard" — the
        // user didn't actually train it — so we treat it as rest when
        // checking the prior day. Otherwise reshuffling a missed
        // Tuesday to Wednesday would falsely look like stacking.
        let validCandidates = candidates.filter { idx, _ in
            guard idx > 0 else { return true }
            let prior = plan.days[idx - 1]
            // The missed day is "actually rest" for the purpose of
            // this check, even though planned as lift/sport.
            if calendar.isDate(prior.date, inSameDayAs: missedDate) { return true }
            return !(prior.kind == .lift || prior.kind == .sport)
        }

        // No valid target → drop.
        guard let pick = validCandidates.first else { return [] }

        return [.move(dayId: missedDay.id, toDate: pick.1.date)]
    }

    // MARK: - Consolidation eligibility (D3 / PRD §6 Q4)

    /// Whether a missed workout should escalate to a CONSOLIDATION offer
    /// (re-plan the rest of the week at fewer lift days) rather than a
    /// reshuffle. Consolidation is the escalation path used only when reshuffle
    /// can't find a clean slot for a *non-budget* reason:
    ///
    ///   - the week is full (≥4 lift days), or
    ///   - there's no valid future rest day to host the workout.
    ///
    /// It is NOT offered when the reshuffle budget is exhausted (the user
    /// already reshuffled their 2/week cap — consolidation has its own 1/week
    /// cap, but offering it on top of an exhausted reshuffle budget is the
    /// decision-fatigue case Q4 rejects), nor when the missed date isn't in the
    /// plan. Pure; composes `proposeReshuffle` so the "is there a clean slot?"
    /// logic stays in one place.
    static func shouldOfferConsolidation(
        missedDate: Date,
        plan: WeekPlan,
        overrides: WeekOverrides,
        remainingBudget: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        // Budget exhaustion is not a consolidation trigger.
        guard remainingBudget > 0 else { return false }
        // The missed day must actually be in the plan (guards the data-error
        // branch of proposeReshuffle, which also returns []).
        guard plan.days.contains(where: { calendar.isDate($0.date, inSameDayAs: missedDate) })
        else { return false }
        // A clean reshuffle slot exists → reshuffle handles it; don't escalate.
        let reshuffle = proposeReshuffle(
            missedDate: missedDate, plan: plan, overrides: overrides,
            remainingBudget: remainingBudget, now: now, calendar: calendar
        )
        guard reshuffle.isEmpty else { return false }
        // proposeReshuffle returned [] for a non-budget, non-data reason —
        // week-full or no-valid-rest-day. Both warrant a consolidation offer.
        return true
    }
}
