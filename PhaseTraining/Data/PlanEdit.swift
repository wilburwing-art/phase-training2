// PlanEdit.swift — the single seam through which the WeekPlan mutates.
//
// PlanStore.propose([PlanEdit]) -> PlanDiff builds a before/after pair without
// mutating. UI presents the diff (PlanDiffSheet) and calls PlanStore.apply(diff)
// when the user confirms. Phase 13 (coach) reuses the same protocol.

import Foundation

enum PlanEdit: Hashable {
    /// Move the day at dayId to a new calendar date. If that date already has
    /// a day in the plan, the two swap positions (so the week stays 7 contiguous).
    case move(dayId: UUID, toDate: Date)

    /// Change a day's kind in place. routineId only meaningful for .lift.
    case swapKind(dayId: UUID, to: DayKind, title: String, routineId: Int?)

    /// Convert a day to a protected event. Locks `protected = true` so the
    /// planner won't auto-move it on next regen.
    case protectDay(dayId: UUID, eventTitle: String)

    /// Override durationMinutes on a day. nil restores planner default.
    case shorten(dayId: UUID, toMinutes: Int)

    /// Insert a new session on an existing day (replaces it).
    case addSession(date: Date, kind: DayKind, title: String, routineId: Int?)

    /// Drop a day back to .rest.
    case removeSession(dayId: UUID)

    /// Short human label for the diff sheet's edit list.
    var label: String {
        switch self {
        case .move:           return "Move"
        case .swapKind:       return "Change kind"
        case .protectDay:     return "Protect"
        case .shorten:        return "Shorten"
        case .addSession:     return "Add session"
        case .removeSession:  return "Remove session"
        }
    }
}

struct PlanDiff: Hashable {
    let before: WeekPlan
    let after: WeekPlan
    let edits: [PlanEdit]
    /// Coach-supplied in Phase 13. nil for hand edits.
    let reasoning: String?

    /// True when nothing actually changed (edits referenced nonexistent days,
    /// or no-op kind swap). UI hides the apply button when this is true.
    var isNoop: Bool { before == after }
}
