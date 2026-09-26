// TrainingLoadModel.swift — B1a of PLAN-predictive-recommendations.md.
//
// A shadow "digital twin": a fitness–fatigue (Banister impulse-response)
// model per movement pattern, fitted to logged working sets. It exists to
// answer one question before anything user-facing is built on it: does it
// predict the next session's top set better than "same as last time"?
// Nothing reads it except TwinPrediction (frozen on each DayOutcome) and the
// DEBUG scorecard.
//
// Model, per pattern p and day t (whole UTC days, sessions before t only):
//   impulse(d)  = sum over working sets on day d of reps * intensity, where
//                 intensity = set e1RM / the exercise's best e1RM before d,
//                 clipped to 0...1.5 (0.7 before any reference exists).
//                 Bodyweight sets (weight 0) count reps * 0.5.
//   normalised  by the pattern's median non-zero daily impulse before t, so
//               a typical session is ~1 whatever the pattern's volume.
//   F(t) = sum impulse(d) * exp(-(t-d)/tauFitness)
//   G(t) = sum impulse(d) * exp(-(t-d)/tauFatigue)
//   P(t) = F(t) - fatigueWeight * G(t)
// Prediction for an exercise last trained on day L:
//   predicted = lastTopE1RM * (1 + gain * (P(t) - P(L)))
// With gain 0 the model IS the last-value baseline, so a fit can never do
// worse than the baseline on the data it was fitted to; the holdout decides.
//
// Pure: inputs in, numbers out. Units: pounds, by the caller's contract.

import Foundation

/// One working set, in pounds. Weight 0 = bodyweight.
struct LoadSet: Equatable {
    var date: Date
    var exercise: String
    var weight: Double
    var reps: Int

    var e1RM: Double { StrengthStandards.epley1RM(weight: weight, reps: reps) }
}

struct TwinParams: Codable, Equatable, Hashable {
    var tauFitness: Double = 42
    var tauFatigue: Double = 7
    var fatigueWeight: Double = 2
    var gain: Double = 0.02

    /// Banister's published time constants and 2:1 fatigue weight. The gain
    /// has no published value for this e1RM mapping; 0.02 is a placeholder
    /// until a per-user fit replaces it.
    static let defaults = TwinParams()

    static let fitGrid: [TwinParams] = {
        var out: [TwinParams] = []
        for tf in [28.0, 42, 56] {
            for tg in [4.0, 7, 11] {
                for w in [1.0, 2, 3] {
                    for g in [0.0, 0.01, 0.02, 0.04, 0.08] {
                        out.append(TwinParams(tauFitness: tf, tauFatigue: tg, fatigueWeight: w, gain: g))
                    }
                }
            }
        }
        return out
    }()
}

struct TwinPairScore: Equatable {
    var n: Int
    var maeModel: Double
    var maeBaseline: Double
    /// Positive = the model's error is this fraction lower than the baseline's.
    var improvement: Double { maeBaseline > 0 ? (maeBaseline - maeModel) / maeBaseline : 0 }
}

final class TrainingLoadModel {

    let params: TwinParams
    private let patternFor: (String) -> String

    /// exercise -> ascending (day, topE1RM) for days with a loaded set.
    private var topByDay: [String: [(day: Int, top: Double)]] = [:]
    /// pattern -> ascending (day, raw impulse).
    private var impulses: [String: [(day: Int, impulse: Double)]] = [:]

    static func day(_ d: Date) -> Int { Int((d.timeIntervalSince1970 / 86_400).rounded(.down)) }

    init(sets: [LoadSet], params: TwinParams = .defaults, patternFor: @escaping (String) -> String) {
        self.params = params
        self.patternFor = patternFor
        build(sets)
    }

    private func build(_ sets: [LoadSet]) {
        let ordered = sets.filter { $0.reps > 0 }.sorted { $0.date < $1.date }
        var bestBefore: [String: Double] = [:]      // best e1RM from days strictly before
        var dayImpulse: [String: [Int: Double]] = [:]
        var dayTop: [String: [Int: Double]] = [:]
        var i = 0
        while i < ordered.count {
            let d = Self.day(ordered[i].date)
            var j = i
            var bestToday: [String: Double] = [:]
            while j < ordered.count, Self.day(ordered[j].date) == d {
                let s = ordered[j]
                let key = s.exercise.lowercased()
                let pattern = patternFor(key)
                let impulse: Double
                if s.weight <= 0 {
                    impulse = Double(s.reps) * 0.5
                } else if let ref = bestBefore[key], ref > 0 {
                    impulse = Double(s.reps) * min(max(s.e1RM / ref, 0), 1.5)
                } else {
                    impulse = Double(s.reps) * 0.7
                }
                dayImpulse[pattern, default: [:]][d, default: 0] += impulse
                if s.weight > 0 {
                    dayTop[key, default: [:]][d] = max(dayTop[key]?[d] ?? 0, s.e1RM)
                    bestToday[key] = max(bestToday[key] ?? 0, s.e1RM)
                }
                j += 1
            }
            for (k, v) in bestToday { bestBefore[k] = max(bestBefore[k] ?? 0, v) }
            i = j
        }
        impulses = dayImpulse.mapValues { $0.map { (day: $0.key, impulse: $0.value) }.sorted { $0.day < $1.day } }
        topByDay = dayTop.mapValues { $0.map { (day: $0.key, top: $0.value) }.sorted { $0.day < $1.day } }
    }

    // MARK: - State

    struct PatternState: Equatable { var fitness: Double; var fatigue: Double; var performance: Double }

    /// State of `pattern` at the start of `day` (that day's sessions excluded).
    func state(pattern: String, day: Int) -> PatternState {
        let history = (impulses[pattern] ?? []).filter { $0.day < day }
        let nonZero = history.map(\.impulse).filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else { return PatternState(fitness: 0, fatigue: 0, performance: 0) }
        let norm = nonZero[nonZero.count / 2]
        var f = 0.0, g = 0.0
        for h in history {
            let dt = Double(day - h.day)
            let w = h.impulse / norm
            f += w * exp(-dt / params.tauFitness)
            g += w * exp(-dt / params.tauFatigue)
        }
        return PatternState(fitness: f, fatigue: g, performance: f - params.fatigueWeight * g)
    }

    // MARK: - Prediction

    struct Prediction: Equatable { var predicted: Double; var baseline: Double }

    /// Predicted top-set e1RM for `exercise` on `day`, or nil with no prior
    /// loaded day to anchor on.
    func predict(exercise: String, day: Int) -> Prediction? {
        let key = exercise.lowercased()
        guard let last = (topByDay[key] ?? []).last(where: { $0.day < day }) else { return nil }
        let pattern = patternFor(key)
        let delta = state(pattern: pattern, day: day).performance
            - state(pattern: pattern, day: last.day).performance
        let predicted = max(0, last.top * (1 + params.gain * delta))
        return Prediction(predicted: predicted, baseline: last.top)
    }

    /// Session readiness in 0...1 over the patterns it trains: a logistic of
    /// mean performance relative to fitness. 0.5 when there is no history.
    func readiness(exercises: [String], day: Int) -> Double {
        let patterns = Set(exercises.map { patternFor($0.lowercased()) })
        let ratios = patterns.map { p -> Double in
            let s = state(pattern: p, day: day)
            return s.fitness > 0 ? s.performance / s.fitness : 0
        }
        guard !ratios.isEmpty else { return 0.5 }
        let mean = ratios.reduce(0, +) / Double(ratios.count)
        return 1 / (1 + exp(-2 * mean))
    }

    /// Actual top-set e1RM for `exercise` on `day`, if a loaded set exists.
    func actualTop(exercise: String, day: Int) -> Double? {
        (topByDay[exercise.lowercased()] ?? []).first { $0.day == day }?.top
    }

    // MARK: - Scoring and fitting

    /// Walk-forward score over training days in `range`: each day is
    /// predicted from strictly earlier data only.
    func score(days range: ClosedRange<Int>) -> TwinPairScore {
        var n = 0, errModel = 0.0, errBase = 0.0
        for (exercise, days) in topByDay {
            for entry in days where range.contains(entry.day) {
                guard let p = predict(exercise: exercise, day: entry.day) else { continue }
                n += 1
                errModel += abs(p.predicted - entry.top)
                errBase += abs(p.baseline - entry.top)
            }
        }
        guard n > 0 else { return TwinPairScore(n: 0, maeModel: 0, maeBaseline: 0) }
        return TwinPairScore(n: n, maeModel: errModel / Double(n), maeBaseline: errBase / Double(n))
    }

    /// Grid-search parameters on `calibration`, lowest model error wins; ties
    /// go to the earlier grid entry. Returns defaults when the window holds
    /// fewer than `minPairs` scored pairs, since a fit on less is noise.
    static func fit(sets: [LoadSet], calibration: ClosedRange<Int>, minPairs: Int = 20,
                    grid: [TwinParams] = TwinParams.fitGrid,
                    patternFor: @escaping (String) -> String) -> TwinParams {
        var best: (TwinParams, Double)?
        for p in grid {
            let s = TrainingLoadModel(sets: sets, params: p, patternFor: patternFor).score(days: calibration)
            guard s.n >= minPairs else { return .defaults }
            if best == nil || s.maeModel < best!.1 { best = (p, s.maeModel) }
        }
        return best?.0 ?? .defaults
    }

    /// Every day that has at least one loaded set, ascending.
    var trainingDays: [Int] {
        Array(Set(topByDay.values.flatMap { $0.map(\.day) })).sorted()
    }
}
