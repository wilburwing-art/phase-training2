// TrainingConstraints.swift — shared clamp ranges for the user's training
// availability knobs (session length, lift days per week).
//
// Two session-minute ranges exist ON PURPOSE — the divergence is intentional,
// not drift:
//   - sessionMinutesUIRange (15...120): what the user can dial in directly
//     (Profile editor, onboarding stepper). Conservative — most users land
//     between 30 and 60 min.
//   - sessionMinutesHardRange (15...180): the pipeline's safety clamp on
//     coach/LLM-supplied durations (GeneratorStrategy.durationMinutes,
//     CoachProposal "shorten" ops, week-tone compression). The coach may
//     legitimately stretch a session past the UI cap, so the hard bound is
//     wider; it only exists to stop a hallucinated 9999 from producing a
//     10-hour workout.

import Foundation

enum TrainingConstraints {
    /// Lift days per week. 0 is valid ("no lift slots" — sport/rest only).
    static let liftDaysRange: ClosedRange<Int> = 0...7

    /// Session minutes the user can set directly in the UI.
    static let sessionMinutesUIRange: ClosedRange<Int> = 15...120

    /// Session minutes the generator/planner/coach pipeline accepts.
    /// Wider than the UI range by design (see header).
    static let sessionMinutesHardRange: ClosedRange<Int> = 15...180
}
