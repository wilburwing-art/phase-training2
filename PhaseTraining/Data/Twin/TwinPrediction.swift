// TwinPrediction.swift — B1a: the shadow twin's prediction for one session,
// frozen on that session's DayOutcome so it is scored against what was logged
// and cannot be revised after the fact.
//
// Riding on DayOutcome gives it the outcome log's persistence, 90-day window,
// backup and restore for free. Old outcomes decode with `twin == nil`.

import Foundation

struct TwinExercisePrediction: Codable, Hashable {
    var exercise: String
    /// Model's predicted top-set e1RM (lb).
    var predicted: Double
    /// Last-value baseline: the previous session's top-set e1RM (lb).
    var baseline: Double
    /// What was logged this session (lb); nil when the exercise was dropped
    /// or done with no load.
    var actual: Double?
}

struct TwinPrediction: Codable, Hashable {
    /// Which parameters produced it, so a later refit never mixes eras.
    var params: TwinParams
    /// 0...1, 0.5 = no history.
    var readiness: Double
    var exercises: [TwinExercisePrediction]
}

enum TwinInputs {

    static let poundsPerKilogram = 2.20462

    /// Native sessions: done, non-warmup sets. Weight strings are pounds by
    /// the app's logging convention; an empty or unparseable weight is
    /// bodyweight.
    static func sets(from sessions: [SavedSession]) -> [LoadSet] {
        sessions.flatMap { s in
            s.exercises.flatMap { ex in
                ex.sets.compactMap { set -> LoadSet? in
                    guard set.done, !set.isWarmup, let reps = set.repsValue, reps > 0 else { return nil }
                    return LoadSet(date: s.startTime, exercise: ex.name,
                                   weight: max(0, set.weightValue ?? 0), reps: reps)
                }
            }
        }
    }

    /// Imported history (Fitbod, Hevy, ...), stored in kilograms. Converted to
    /// pounds so one exercise never mixes units across sources. Warmups are
    /// already dropped at import.
    static func sets(from imported: [ImportedSet]) -> [LoadSet] {
        imported.compactMap { s -> LoadSet? in
            guard let reps = s.reps, reps > 0 else { return nil }
            return LoadSet(date: s.performedAt, exercise: s.exerciseNameRaw,
                           weight: max(0, (s.weight ?? 0) * poundsPerKilogram), reps: reps)
        }
    }

    /// Movement pattern for an exercise name: its first coach.db pattern slug
    /// (resolved through aliases), else a bucket of its own so an unmatched
    /// exercise never borrows another's fatigue.
    static func pattern(for name: String) -> String {
        if let id = ExerciseLookupCache.shared.exerciseID(forName: name),
           let slug = CoachDatabase.shared.patternsForExercise(id).first {
            return slug
        }
        return "ex:\(name.lowercased())"
    }

    /// Build the frozen prediction for `session` from history strictly before
    /// it. Planned exercises come from the planner's own list (the displaced
    /// original on a switched day); with no plan, the session's own exercises.
    static func predict(session: SavedSession, plannedExercises: [String],
                        history: [LoadSet], params: TwinParams = .defaults) -> TwinPrediction {
        let before = history.filter { $0.date < session.startTime }
        let model = TrainingLoadModel(sets: before + sets(from: [session]), params: params,
                                      patternFor: pattern(for:))
        let day = TrainingLoadModel.day(session.startTime)
        let names = plannedExercises.isEmpty ? session.exercises.map(\.name) : plannedExercises
        var seen = Set<String>()
        let rows = names.compactMap { name -> TwinExercisePrediction? in
            guard seen.insert(name.lowercased()).inserted,
                  let p = model.predict(exercise: name, day: day) else { return nil }
            return TwinExercisePrediction(exercise: name, predicted: p.predicted, baseline: p.baseline,
                                          actual: model.actualTop(exercise: name, day: day))
        }
        return TwinPrediction(params: params, readiness: model.readiness(exercises: names, day: day),
                              exercises: rows)
    }
}

/// Scorecard over frozen predictions: model versus last-value baseline on the
/// pairs that have an actual, plus mean readiness per outcome class.
struct TwinScorecard: Equatable {
    var pairs: TwinPairScore
    var readinessByKind: [DayOutcomeKind: Double]

    static func from(_ outcomes: [DayOutcome]) -> TwinScorecard {
        var n = 0, em = 0.0, eb = 0.0
        var readiness: [DayOutcomeKind: [Double]] = [:]
        for o in outcomes {
            guard let t = o.twin else { continue }
            readiness[o.kind, default: []].append(t.readiness)
            for e in t.exercises {
                guard let actual = e.actual else { continue }
                n += 1
                em += abs(e.predicted - actual)
                eb += abs(e.baseline - actual)
            }
        }
        let pairs = n == 0 ? TwinPairScore(n: 0, maeModel: 0, maeBaseline: 0)
            : TwinPairScore(n: n, maeModel: em / Double(n), maeBaseline: eb / Double(n))
        return TwinScorecard(pairs: pairs,
                             readinessByKind: readiness.mapValues { $0.reduce(0, +) / Double($0.count) })
    }
}

/// Walk-forward replay over a whole history: fit on the 16 weeks before the
/// final 8, then score the final 8 predicting each day from earlier data only.
/// This is the B1b go/no-go: `holdout.improvement > 0` or B1b does not start.
enum TwinReplay {

    struct Report: Equatable {
        var fitted: TwinParams
        var holdout: TwinPairScore
        var holdoutWithDefaults: TwinPairScore
        var holdoutDays: ClosedRange<Int>
        var trainingDays: Int
    }

    static let holdoutDays = 56
    static let calibrationDays = 112

    static func run(sets: [LoadSet], patternFor: @escaping (String) -> String = TwinInputs.pattern(for:)) -> Report? {
        let probe = TrainingLoadModel(sets: sets, patternFor: patternFor)
        guard let last = probe.trainingDays.last else { return nil }
        let holdout = (last - holdoutDays + 1)...last
        let calibration = (holdout.lowerBound - calibrationDays)...(holdout.lowerBound - 1)
        let fitted = TrainingLoadModel.fit(sets: sets, calibration: calibration, patternFor: patternFor)
        return Report(
            fitted: fitted,
            holdout: TrainingLoadModel(sets: sets, params: fitted, patternFor: patternFor).score(days: holdout),
            holdoutWithDefaults: probe.score(days: holdout),
            holdoutDays: holdout,
            trainingDays: probe.trainingDays.count)
    }
}
