// PlanStore+MissedWorkoutAutopilot.swift
//
// Extracted from PlanStore.swift (Tier-3 god-object split). Missed-workout detection + reshuffle autopilot (PR 8).
// Lifecycle (init/reload), generation-context plumbing, PlanEdit/regeneration,
// and persistence stay in PlanStore.swift.

import Foundation

extension PlanStore {
    /// All planned-but-not-completed days in the current plan that
    /// haven't already been logged into `missedWorkouts`. The caller
    /// (typically the Today screen) shows a banner per result; once
    /// the user acts, `applyMissedReshuffle` / `dismissMissed`
    /// records the entry so we don't re-banner the same date.
    func pendingMissedWorkouts(now: Date = Date()) -> [DayPlan] {
        guard let plan, let sessions = sessionStore?.savedSessions else { return [] }
        let detected = MissedWorkoutAutopilot.detect(
            plan: plan,
            sessions: sessions,
            overrides: overrides,
            now: now
        )
        let calendar = Calendar.current
        // Skip days we've already logged a MissedWorkoutEntry for.
        let loggedDates = Set(missedWorkouts.map { calendar.startOfDay(for: $0.date) })
        return detected.filter { day in
            !loggedDates.contains(calendar.startOfDay(for: day.date))
        }
    }

    /// Propose a reshuffle for the given missed date using the
    /// autopilot rules. Returns nil when budget is exhausted, the
    /// drop-rule fires, or no valid target exists — caller in that
    /// case should call `dismissMissed(_:asDropped:)` to log the
    /// outcome.
    func proposeMissedReshuffle(missedDate: Date,
                                now: Date = Date()) -> PlanDiff? {
        guard plan != nil else { return nil }
        let remainingBudget = max(0, Self.weeklyReshuffleCap - midWeekReshuffleCount)
        let edits = MissedWorkoutAutopilot.proposeReshuffle(
            missedDate: missedDate,
            plan: plan!,
            overrides: overrides,
            remainingBudget: remainingBudget,
            now: now
        )
        guard !edits.isEmpty else { return nil }
        return propose(edits, reasoning: "Missed workout — moved to keep coverage")
    }

    /// D3 — whether the missed-workout banner should offer a CONSOLIDATE option
    /// (vs the reshuffle / drop affordance). True only when the autopilot says
    /// reshuffle found no clean slot for a non-budget reason, the 1/week
    /// consolidation cap has room, AND there are ≥2 future lift days with a
    /// recoverable focus to actually reduce (so `consolidateWeek` would apply).
    func shouldOfferConsolidation(missedDate: Date, now: Date = Date()) -> Bool {
        guard let plan else { return false }
        guard midWeekConsolidationCount < Self.weeklyConsolidationCap else { return false }
        let remainingReshuffleBudget = max(0, Self.weeklyReshuffleCap - midWeekReshuffleCount)
        guard MissedWorkoutAutopilot.shouldOfferConsolidation(
            missedDate: missedDate, plan: plan, overrides: overrides,
            remainingBudget: remainingReshuffleBudget, now: now) else { return false }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let futureLifts = plan.days.filter {
            $0.kind == .lift && cal.startOfDay(for: $0.date) >= todayStart
                && !$0.protected && $0.generatedWorkout?.focus != nil
        }
        return futureLifts.count >= 2
    }

    /// Apply the autopilot's proposed reshuffle, log the resolution,
    /// and bump the per-week counter.
    func applyMissedReshuffle(_ diff: PlanDiff,
                              missedDate: Date,
                              now: Date = Date()) {
        guard let day = plan?.days.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: missedDate)
        }) else { return }
        // The move targets the date that day-id now lives at, which is
        // the "to" date of the .move edit in the diff. Pull it out so
        // we can record the resolution.
        let newDate: Date? = diff.edits.compactMap { edit -> Date? in
            if case .move(_, let toDate) = edit { return toDate }
            return nil
        }.first

        apply(diff)
        let resolution: MissResolution = newDate.map { .reshuffledTo($0) } ?? .dropped
        recordMiss(date: day.date, kind: day.kind, title: day.title,
                   resolution: resolution, now: now)
        midWeekReshuffleCount += 1
        saveReshuffleCount(now: now)
    }

    /// Log a miss without applying any plan changes. Used for the
    /// drop-rule fire and the user-dismissed paths. `asDropped`
    /// distinguishes the two — autopilot-dropped vs user-dismissed —
    /// so the coach can tell the difference.
    func dismissMissed(date: Date, asDropped: Bool, now: Date = Date()) {
        guard let day = plan?.days.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }) else { return }
        recordMiss(date: day.date, kind: day.kind, title: day.title,
                   resolution: asDropped ? .dropped : .userDismissed, now: now)
    }

    /// Persist a MissedWorkoutEntry. Removes any existing entry for
    /// the same date (idempotent on re-detection).
    private func recordMiss(date: Date,
                            kind: DayKind,
                            title: String,
                            resolution: MissResolution,
                            now: Date = Date()) {
        var next = missedWorkouts.filter {
            !Calendar.current.isDate($0.date, inSameDayAs: date)
        }
        next.append(MissedWorkoutEntry(
            date: Calendar.current.startOfDay(for: date),
            plannedKind: kind,
            plannedTitle: title,
            resolution: resolution,
            loggedAt: now
        ))
        // Trim 90-day window
        let cutoff = now.addingTimeInterval(-Double(Self.planOverridesRetentionDays) * 86_400)
        missedWorkouts = next
            .filter { $0.loggedAt >= cutoff }
            .sorted { $0.date > $1.date }
        saveMissedWorkouts()
    }
}
