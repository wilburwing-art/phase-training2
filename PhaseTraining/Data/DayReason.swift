//
//  DayReason.swift
//  PhaseTraining
//
//  The "why this day" line on Week rows and the day sheet.
//
//  `DayPlan.generatedReason` mixes two kinds of text. The planner writes
//  sentences for the user ("You moved this workout here", "Rest. Seven
//  training days leaves no time to recover, ..."). Lift days also carry the
//  generator's provenance trace ("snow-sports · inbounds · demands: ...") and
//  shape bookkeeping ("Rest slot from 3L/2S/2R"), and the deconflict pass
//  appends load notes to either with " · ". The coach reads all of it.
//
//  This keeps only the sentences. A segment shows when it opens with one of
//  the planner's sentence openers; anything else stays hidden, so a new trace
//  string never reaches the screen by default. A new planner sentence needs
//  its opener added here (PlannerTests pins the common ones).
//

import Foundation

enum DayReason {

    /// Openers of the sentences the planner writes for the user
    /// (`Planner.swift`, `CNSBudgetEngine.swift`, `PlanStore+*`).
    static let sentenceOpeners: [String] = [
        "You ", "Your ", "Rest. ", "Recovery day", "Couldn't fit",
        "Event you scheduled", "Tapering before", "Easing into",
        "Recovering from", "Going light before", "A sample of",
    ]

    /// The readable part of `day.generatedReason`, or nil when none is.
    static func line(for day: DayPlan) -> String? {
        guard var raw = day.generatedReason, !raw.isEmpty else { return nil }
        if let provenance = day.generatedWorkout?.provenance, !provenance.isEmpty,
           raw.hasPrefix(provenance) {
            raw.removeFirst(provenance.count)
        }
        let kept = raw.components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(isSentence)
        return kept.isEmpty ? nil : kept.joined(separator: ". ")
    }

    static func isSentence(_ segment: String) -> Bool {
        sentenceOpeners.contains { segment.hasPrefix($0) }
            || segment.contains(" is in-season, so ")
    }
}
