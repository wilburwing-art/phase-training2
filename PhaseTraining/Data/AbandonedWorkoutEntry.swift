// AbandonedWorkoutEntry.swift — PR 9 of the weekly-coach roadmap.
//
// One log entry per abandoned workout: a session ended via the "Stop
// early" affordance (distinct from "Finish") at less than 70% of its
// planned sets completed, with a typed reason captured in
// AbandonReasonSheet.
//
// Persisted on PlanStore under `pt_abandoned_workouts`. Rolling 90-day
// window, mirroring MissedWorkoutEntry — entries older than that drop
// off so the coach context doesn't keep referencing a bad day from
// 8 months ago.
//
// The SavedSession itself is written through the normal
// `saveCompleted` path (partial work is real history — sets logged
// before the stop count for PRs and volume). This entry is the
// plan-layer signal the rules engine and coach read.
//
// Spec: PLAN-weekly-coach.md §2.3, §5.

import Foundation

/// Why the user stopped early. Typed set from spec §2.3; the raw set
/// order matches the sheet's presentation order.
enum AbandonReason: String, Codable, CaseIterable, Hashable {
    case equipmentUnavailable
    case feltOff
    case timeOut
    case pain
    case motivation
    case other

    /// Sheet label. Kept in sync with AbandonReasonSheet's row order.
    var label: String {
        switch self {
        case .equipmentUnavailable: return "Equipment unavailable"
        case .feltOff:              return "Felt off"
        case .timeOut:              return "Time ran out"
        case .pain:                 return "Pain"
        case .motivation:           return "Lost motivation"
        case .other:                return "Other"
        }
    }
}

struct AbandonedWorkoutEntry: Codable, Identifiable, Hashable {
    var id: UUID
    /// Start-of-day of the workout's start time.
    var date: Date
    /// Session name the user was logging against.
    var plannedTitle: String?
    var reason: AbandonReason
    /// Done sets / total sets, 0.0–1.0, computed at save time from
    /// SavedSession.exercises[].sets[]. Warmup sets count in both —
    /// the ratio measures "how much of the planned work happened",
    /// not training load.
    var completionRatio: Double
    /// Free-text note from the "Other" path (or an optional note on
    /// any reason). Trimmed; nil when empty.
    var note: String?
    var loggedAt: Date

    init(date: Date, plannedTitle: String?, reason: AbandonReason,
         completionRatio: Double, note: String? = nil, loggedAt: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.plannedTitle = plannedTitle
        self.reason = reason
        self.completionRatio = min(max(completionRatio, 0), 1)
        self.note = note
        self.loggedAt = loggedAt
    }
}

extension AbandonedWorkoutEntry {
    /// Spec §5: a session below this share of planned sets done, ended
    /// via Stop early, is an abandonment. Above it, the session is a
    /// completed (if short) workout and no entry is recorded.
    static let abandonmentThreshold = 0.70
}
