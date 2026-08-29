//
//  PlanBlurb.swift
//  PhaseTraining
//
//  One human sentence for the Today header.
//
//  The header used to render `DayPlan.generatedReason`, which PlanStore fills
//  from `GeneratedWorkout.provenance` — a machine trace built for debugging
//  ("snow-sports · inbounds · Convert to eccentric + power + lactate ·
//  demands: eccentricLeg/legEndurance/power/maxStrength"). Accurate, and the
//  most prominent copy on the screen was reading like a log line.
//
//  Provenance is untouched: the coach prompt reads `generatedReason` to
//  explain planner decisions and CoachPolishedExplanationSheet displays it.
//  The precise thing stays in the data and the readable thing goes on screen,
//  the same split the exercise shorthand uses.
//
//  Deterministic on purpose. No model call, so it costs nothing, needs no
//  consent, renders offline, and is testable.
//

import Foundation

enum PlanBlurb {

    /// A short sentence for today, or nil when the plan says nothing worth a
    /// line. nil is a real answer: a header with no caption is calmer than a
    /// header with a filler one.
    static func sentence(kind: DayKind,
                         phase: SeasonPhase,
                         sportLabel: String?,
                         weekInPhase: Int?) -> String? {
        switch kind {
        case .rest:
            return "Rest. Nothing scheduled."
        case .sport:
            guard let sport = sportLabel else { return nil }
            return "\(sport) today. Log it when you're back."
        case .lift:
            return liftSentence(phase: phase, sportLabel: sportLabel, weekInPhase: weekInPhase)
        case .event:
            return sportLabel.map { "Event day. \($0)." } ?? "Event day."
        }
    }

    private static func liftSentence(phase: SeasonPhase,
                                     sportLabel: String?,
                                     weekInPhase: Int?) -> String? {
        let forSport = sportLabel.map { " for \($0.lowercased())" } ?? ""
        let week = weekInPhase.map { " Week \($0)." } ?? ""
        switch phase {
        case .offSeason:
            return "Off-season\(forSport). Building the engine while there's time.\(week)"
        case .preSeason:
            return "Pre-season\(forSport). Sharpening what the season will ask for.\(week)"
        case .inSeason:
            return "In-season\(forSport). Enough to hold your strength, not enough to cost you.\(week)"
        case .eventPrep:
            return "Event prep\(forSport). Staying fresh and holding the peak.\(week)"
        case .maintenance:
            return "Staying strong, year-round.\(week)"
        }
    }
}
