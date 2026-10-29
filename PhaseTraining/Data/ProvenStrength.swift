// ProvenStrength.swift — what the lifter can do now, from what they logged.
//
// One estimate per exercise behind both weight suggestions: the generator's
// "target: X lb" note (through `GeneratorContext.priorBest`) and the Log /
// Today "SUGGESTED" pill when the exercise has no previous native session.
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

    // MARK: - Index over native sessions + imported sets

    /// Estimates keyed like every per-exercise map (`ExerciseKey`): the raw
    /// lowercased name for native entries plus `id:<catalogId>` when the
    /// catalog resolves it. Native and imported evidence for the same
    /// catalog exercise pool together. Imported sets count only when their
    /// name resolved to a catalog id.
    static func index(sessions: [SavedSession], imported: [ImportedSet],
                      now: Date) -> [String: PriorBest] {
        let kgToLb = 1 / ImportUnitCorrection.kgPerLb
        var evidence: [String: [Evidence]] = [:]
        var rawNames: [String: Set<String>] = [:]

        for session in sessions {
            for ex in session.exercises {
                let key = ExerciseKey.id(for: ex.name) ?? ExerciseKey.raw(ex.name)
                rawNames[key, default: []].insert(ExerciseKey.raw(ex.name))
                for set in ex.sets where set.done && !set.isWarmup {
                    guard let w = set.weightValue, let r = set.repsValue else { continue }
                    evidence[key, default: []].append(Evidence(date: session.startTime, weightLb: w, reps: r))
                }
            }
        }
        for set in imported {
            guard let id = set.exerciseId, let kg = set.weight, let r = set.reps else { continue }
            evidence["id:\(id)", default: []].append(Evidence(date: set.performedAt, weightLb: kg * kgToLb, reps: r))
        }

        var out: [String: PriorBest] = [:]
        for (key, ev) in evidence {
            guard let best = estimate(ev, now: now) else { continue }
            if key.hasPrefix("id:") {
                out[key] = best
                // An imported-only exercise has no native name; key it by its
                // catalog name too, as the old imported-peak fill did.
                if rawNames[key] == nil, let id = Int(key.dropFirst(3)),
                   let name = CoachDatabase.shared.exercise(id: id)?.name {
                    out[ExerciseKey.raw(name)] = out[ExerciseKey.raw(name)] ?? best
                }
            }
            for raw in rawNames[key] ?? [] { out[raw] = best }
        }
        return out
    }
}
