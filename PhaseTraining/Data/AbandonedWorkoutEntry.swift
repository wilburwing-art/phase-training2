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
    /// Joints picked on the sheet for a Pain stop, from
    /// `FeedbackEntry.hurtAreaOptions`. Optional so entries stored before
    /// 11c 3.2 decode (synthesized Codable reads a missing key as nil).
    var hurtAreas: [String]?

    init(date: Date, plannedTitle: String?, reason: AbandonReason,
         completionRatio: Double, note: String? = nil, hurtAreas: [String] = [],
         loggedAt: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.plannedTitle = plannedTitle
        self.reason = reason
        self.completionRatio = min(max(completionRatio, 0), 1)
        self.note = note
        let areas = reason == .pain ? Array(Set(hurtAreas)).sorted() : []
        self.hurtAreas = areas.isEmpty ? nil : areas
        self.loggedAt = loggedAt
    }
}

extension AbandonedWorkoutEntry {
    /// Spec §5: a session below this share of planned sets done, ended
    /// via Stop early, is an abandonment. Above it, the session is a
    /// completed (if short) workout and no entry is recorded.
    static let abandonmentThreshold = 0.70

    /// The hurt report a Pain stop with areas adds to `TrainingMemory.feedback`,
    /// where `MuscleRecovery.status` eases the muscles around each joint for
    /// its 36 hour hurt window. Written for every Pain stop, above the
    /// abandonment threshold too: the joint hurts either way. Difficulty
    /// stays nil, so the planner's too-hard trim never counts a pain stop.
    static func painFeedback(reason: AbandonReason, hurtAreas: [String],
                             sessionId: String?, at date: Date) -> FeedbackEntry? {
        let areas = Array(Set(hurtAreas)).sorted()
        guard reason == .pain, !areas.isEmpty else { return nil }
        return FeedbackEntry(date: date, sessionId: sessionId, difficulty: nil,
                             hurtAreas: areas, notes: nil)
    }
}
