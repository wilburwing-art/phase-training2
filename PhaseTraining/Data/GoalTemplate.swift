// GoalTemplate.swift — PR 11 of the weekly-coach roadmap: long-term goals.
//
// The Progress tab used to show history without direction — a user could
// see WHAT they did but not whether it was TOWARD anything. Goals close
// that loop: the user picks 1-2 from a curated set, the Progress tab
// renders a progress bar against the goal's metric, and tagged sessions
// (Test day, Max attempt) anchor the strength charts.
//
// The template set is deliberately small and measurable — every goal
// computes its progress from data the app ALREADY stores (best e1RM per
// exercise via UserDatabase, 5k time via sport logs). No new ingestion.
//
// Spec: PLAN-weekly-coach.md §8.

import Foundation

enum GoalTemplate: String, Codable, CaseIterable, Identifiable {
    case benchBodyweight
    case pullUpUnweighted
    case deadliftTwoXBodyweight
    case squatOnePointFiveXBodyweight
    case ohpThreeQuartersBodyweight
    case fiveKUnder25
    case climbsHundredPerMonth

    var id: String { rawValue }

    /// User-facing label.
    var label: String {
        switch self {
        case .benchBodyweight:             return "Bench your bodyweight"
        case .pullUpUnweighted:            return "First unweighted pull-up"
        case .deadliftTwoXBodyweight:      return "Deadlift 2× bodyweight"
        case .squatOnePointFiveXBodyweight: return "Squat 1.5× bodyweight"
        case .ohpThreeQuartersBodyweight:  return "OHP 0.75× bodyweight"
        case .fiveKUnder25:                return "5k under 25 minutes"
        case .climbsHundredPerMonth:       return "100 climbs a month"
        }
    }

    /// One-line description for the picker.
    var subtitle: String {
        switch self {
        case .benchBodyweight:             return "1RM bench ≥ current body weight"
        case .pullUpUnweighted:            return "One strict rep, no assistance"
        case .deadliftTwoXBodyweight:      return "1RM deadlift ≥ 2× body weight"
        case .squatOnePointFiveXBodyweight: return "1RM squat ≥ 1.5× body weight"
        case .ohpThreeQuartersBodyweight:  return "1RM overhead press ≥ 0.75× body weight"
        case .fiveKUnder25:                return "A 5k run timed under 25:00"
        case .climbsHundredPerMonth:       return "Averaging 25 climbing sessions a week is a lot — this is total climbs logged"
        }
    }

    /// Which exercise's e1RM the strength goals read. nil for non-strength.
    var exerciseName: String? {
        switch self {
        case .benchBodyweight:             return "Bench Press"
        case .pullUpUnweighted:            return "Pull-Up"
        case .deadliftTwoXBodyweight:      return "Deadlift"
        case .squatOnePointFiveXBodyweight: return "Squat"
        case .ohpThreeQuartersBodyweight:  return "Overhead Press"
        default:                           return nil
        }
    }

    /// Load multiplier against bodyweight (strength goals). nil otherwise.
    var loadMultiplier: Double? {
        switch self {
        case .benchBodyweight:             return 1.0
        case .pullUpUnweighted:            return 0.0   // bodyweight itself
        case .deadliftTwoXBodyweight:      return 2.0
        case .squatOnePointFiveXBodyweight: return 1.5
        case .ohpThreeQuartersBodyweight:  return 0.75
        default:                           return nil
        }
    }
}

/// One active user goal. `templateId` keys the metric; `createdAt` lets
/// the Progress tab show "since May" on the bar.
struct UserGoal: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let templateId: GoalTemplate
    let createdAt: Date

    var template: GoalTemplate { templateId }
}

extension UserGoal {
    /// Compute progress toward this goal, 0.0–1.0 (values above 1.0
    /// clamped — the bar shows "done").
    ///
    /// - Strength goals: best e1RM for the exercise (from `bestE1RM`,
    ///   keyed by lowercased exercise name) ÷ (bodyweight × multiplier).
    /// - 5k: fastest logged 5k (seconds, from `fastestFiveKSeconds`)
    ///   vs the 25:00 target — sub-target = done.
    /// - Climbs: `climbsLast30Days` ÷ 100.
    ///
    /// `bodyweightKg` is the latest logged body weight; nil bodyweight
    /// → strength goals return nil (unknown, not zero — the bar shows
    /// "log your weight to track this" rather than an empty bar).
    func progress(bestE1RM: [String: Double],
                  bodyweightKg: Double?,
                  fastestFiveKSeconds: Double?,
                  climbsLast30Days: Int) -> Double? {
        switch templateId {
        case .benchBodyweight, .deadliftTwoXBodyweight,
             .squatOnePointFiveXBodyweight, .ohpThreeQuartersBodyweight,
             .pullUpUnweighted:
            guard let bw = bodyweightKg, let mult = templateId.loadMultiplier,
                  let exName = templateId.exerciseName,
                  let e1rm = bestE1RM[exName.lowercased()] else { return nil }
            // Pull-up: the bar is bodyweight itself (a BW-level pull).
            let targetKg = templateId == .pullUpUnweighted ? bw : bw * mult
            guard targetKg > 0 else { return nil }
            return min(1.0, e1rm / targetKg)
        case .fiveKUnder25:
            guard let fastest = fastestFiveKSeconds else { return nil }
            let target = 25.0 * 60.0
            // Faster than target → 1.0; scale linearly from 2× target.
            return min(1.0, max(0.0, (2 * target - fastest) / target))
        case .climbsHundredPerMonth:
            return min(1.0, Double(climbsLast30Days) / 100.0)
        }
    }
}
