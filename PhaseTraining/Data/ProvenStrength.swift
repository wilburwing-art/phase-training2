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
//      week, never below 75%. A lifter whose history holds enough past
//      breaks gets their own weekly rate instead (`DetrainingRate`), bounded
//      to 0.5-1.5% so thin evidence can't swing a suggestion far.
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

    /// The weekly discount past `graceWeeks`, measured from the lifter's own
    /// comebacks by `HistoryProfile` when there are enough of them.
    struct DetrainingRate: Equatable {
        /// The rate estimates use.
        let perWeek: Double
        /// The unclamped median of the comeback pairs; nil when none counted.
        let measured: Double?
        let breaks: Int
        let pairs: Int

        var isPersonal: Bool { breaks >= Self.minBreaks && pairs >= Self.minPairs }

        static let standard = DetrainingRate(perWeek: discountPerWeek, measured: nil, breaks: 0, pairs: 0)

        /// Thresholds are judgment calls. A rough pass over a real 2016-2026
        /// export found 16 pairs over 5 breaks returning at a median 93%, with
        /// a 70-122% spread, so one break is never enough and the bound keeps
        /// a noisy median from suggesting much heavier after time off.
        static let minBreaks = 3
        static let minPairs = 10
        static let range = 0.005...0.015

        /// Gated and clamped; `.standard` when the evidence is too thin.
        static func from(pairRates: [Double], breaks: Int) -> DetrainingRate {
            guard !pairRates.isEmpty else { return .standard }
            let s = pairRates.sorted()
            let m = s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
            let candidate = DetrainingRate(perWeek: min(max(m, range.lowerBound), range.upperBound),
                                           measured: m, breaks: breaks, pairs: pairRates.count)
            return candidate.isPersonal
                ? candidate
                : DetrainingRate(perWeek: discountPerWeek, measured: m, breaks: breaks, pairs: pairRates.count)
        }
    }

    /// Multiplier for evidence `days` old.
    static func ageFactor(days: Double, perWeek: Double = discountPerWeek) -> Double {
        let weeksPastGrace = max(0, days / 7 - graceWeeks)
        return max(floor, 1 - perWeek * weeksPastGrace)
    }

    /// The estimate as a `PriorBest`: a set at the most recent workout's best
    /// rep count whose Epley 1RM equals the estimate, so the existing rep
    /// mapping (`WorkoutGenerator.targetLb`) and progression decision read it
    /// unchanged. Nil without usable evidence.
    static func estimate(_ evidence: [Evidence], now: Date, perWeek: Double = discountPerWeek) -> PriorBest? {
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
            w.e1rm * ageFactor(days: now.timeIntervalSince(w.date) / 86_400, perWeek: perWeek)
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
