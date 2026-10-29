// ProvenStrength.swift — what the lifter can do now, from what they logged.
//
// One estimate per exercise behind both weight suggestions: the generator's
// "target: X lb" note (through `GeneratorContext.priorBest`) and the Log /
// Today "SUGGESTED" pill when the exercise has no previous native session.
// `HistoryProfile` gathers and cleans the evidence and calls `estimate`.
//
// The rule, chosen to fail safe (the constants are judgment calls, not fits):
//   1. Evidence is every working set with weight > 0 and 1-12 reps (Epley
//      drifts past ~12), native and imported in one pool, in lb.
//   2. Each workout contributes its best estimated 1RM.
//   3. The estimate is the MEDIAN of the 3 most recent workouts (mean of 2,
//      or the one), each discounted for age: nothing for 4 weeks, then 1% a
//      week, never below 75%.
// So a peak from years ago can never come back (the old lifetime-peak fill
// suggested 365 lb for a lifter benching 135), one typo or one light day
// can't move the number, and a long layoff starts lighter.

import Foundation

enum ProvenStrength {

    /// One working set.
    struct Evidence: Equatable {
        let date: Date
        let weightLb: Double
        let reps: Int
    }

    static let workoutsConsidered = 3
    static let graceWeeks = 4.0
    static let discountPerWeek = 0.01
    static let floor = 0.75
    static let repRange = 1...12

    /// Multiplier for evidence `days` old.
    static func ageFactor(days: Double) -> Double {
        let weeksPastGrace = max(0, days / 7 - graceWeeks)
        return max(floor, 1 - discountPerWeek * weeksPastGrace)
    }

    /// The estimate as a `PriorBest`: a set at the most recent workout's best
    /// rep count whose Epley 1RM equals the estimate, so the existing rep
    /// mapping (`WorkoutGenerator.targetLb`) and progression decision read it
    /// unchanged. Nil without usable evidence.
    static func estimate(_ evidence: [Evidence], now: Date) -> PriorBest? {
        let usable = evidence.filter { $0.weightLb > 0 && repRange.contains($0.reps) }
        let workouts = Dictionary(grouping: usable, by: \.date)
            .map { date, sets -> (date: Date, best: Evidence, e1rm: Double) in
                let best = sets.max { epley($0) < epley($1) }!
                return (date, best, epley(best))
            }
            .sorted { $0.date > $1.date }
            .prefix(workoutsConsidered)
        guard let latest = workouts.first else { return nil }

        let discounted = workouts.map { w in
            w.e1rm * ageFactor(days: now.timeIntervalSince(w.date) / 86_400)
        }
        let e1rm = median(discounted)
        let reps = latest.best.reps
        // Inverse of StrengthStandards.epley1RM, which treats 1 rep as the 1RM.
        let weight = reps == 1 ? e1rm : e1rm / (1 + Double(reps) / 30)
        return PriorBest(weight: weight, reps: reps, date: latest.date)
    }

    private static func epley(_ e: Evidence) -> Double {
        StrengthStandards.epley1RM(weight: e.weightLb, reps: e.reps)
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
