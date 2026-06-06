// PlanStore+History.swift
//
// Extracted from PlanStore.swift (Tier-3 god-object split). Plan history: rollover snapshots + 'typical week' shape adoption (PR 4 / PR 6).
// Lifecycle (init/reload), generation-context plumbing, PlanEdit/regeneration,
// and persistence stay in PlanStore.swift.

import Foundation

extension PlanStore {
    /// Capture a snapshot of the active plan into `pastPlans`. Idempotent
    /// by `weekStart`: re-snapshotting the same week replaces the prior
    /// entry, preserving the latest captured shape (so a Wednesday edit
    /// is what history records, not the empty-Monday baseline). Trimmed
    /// to the rolling 12-week cap after each insert.
    func snapshotCurrentPlan(now: Date = Date()) {
        guard let plan else { return }
        let sessions = sessionStore?.savedSessions ?? []
        let snap = WeekPlanSnapshot.capture(plan, sessions: sessions, now: now)
        var next = pastPlans.filter { !Calendar.current.isDate($0.weekStart, inSameDayAs: snap.weekStart) }
        next.insert(snap, at: 0)
        pastPlans = WeekPlanSnapshot.trim(next, limit: Self.pastPlansLimit)
        savePastPlans()
    }

    /// Derive the "actual shape" for a given week's start date. Combines
    /// the persisted snapshot (the planned shape) with current
    /// `SessionStore.savedSessions` (the actual sessions). Returns nil
    /// when no snapshot exists for that week — caller can decide whether
    /// to render a "no data" state or fall back to live data.
    func shape(forWeek weekStart: Date) -> WeekShape? {
        let normalized = weekStart.startOfTrainingWeek()
        guard let snap = pastPlans.first(where: {
            Calendar.current.isDate($0.weekStart, inSameDayAs: normalized)
        }) else { return nil }
        let sessions = sessionStore?.savedSessions ?? []
        return WeekShape(snapshot: snap, sessions: sessions)
    }

    /// True when a PRIOR week's snapshot exists to copy a shape from.
    var hasPriorWeekShape: Bool {
        let thisWeek = Date().startOfTrainingWeek()
        return pastPlans.contains { $0.weekStart < thisWeek }
    }

    func adoptLastWeekShape(memory: TrainingMemory,
                            today: Date = Date(),
                            calendar: Calendar = .current) -> Bool {
        let thisWeekStart = today.startOfTrainingWeek(calendar: calendar)
        guard let snap = pastPlans.first(where: { $0.weekStart < thisWeekStart })
        else { return false }
        updateOverrides(memory: memory, today: today) { o in
            for (i, day) in snap.plan.days.enumerated() where i < 7 {
                guard let target = calendar.date(byAdding: .day, value: i, to: thisWeekStart)
                else { continue }
                let key = calendar.startOfDay(for: target)
                switch day.kind {
                case .lift:
                    o.dayOverrides[key] = .lift(
                        routineId: day.routineId,
                        focus: Self.liftFocus(from: day.generatedWorkout?.focus))
                case .sport:
                    o.dayOverrides[key] = .sport(sportSlug: day.sport?.slug)
                case .rest, .event:
                    o.dayOverrides[key] = .rest
                }
            }
        }
        return true
    }

    /// Map the generator's WorkoutFocus back to the override LiftFocus (the two
    /// full-body variants collapse to .fullBody).
    private static func liftFocus(from wf: WorkoutFocus?) -> LiftFocus? {
        switch wf {
        case .push: return .push
        case .pull: return .pull
        case .legs: return .legs
        case .upper: return .upper
        case .lower: return .lower
        case .fullBodyA, .fullBodyB: return .fullBody
        case nil: return nil
        }
    }
}
