// TwinDiagnosis.swift — 1a-2 of PLAN-next-gen.md.
//
// Where does the shadow twin lose to "same as last time"? Pure slicing over
// TrainingLoadModel.scoredPairs; it changes nothing about the model. Any
// model change this suggests must be judged on data the model has not seen
// (in-app pairs at the 2026-10-24 review, or a newer export). Re-scoring a
// changed model on the export that motivated it is fitting the test.

import Foundation

struct TwinSlice: Equatable {
    var label: String
    var n: Int
    var maeModel: Double
    var maeBaseline: Double
    var improvement: Double { maeBaseline > 0 ? (maeBaseline - maeModel) / maeBaseline : 0 }
}

struct TwinDiagnosis: Equatable {
    var overall: TwinSlice
    var byReps: [TwinSlice]
    var byGap: [TwinSlice]
    var byExercise: [TwinSlice]
    /// Pairs whose week (7-day block) held 2+ training days.
    var dense: TwinSlice
    var sparse: TwinSlice
    /// Among pairs where both the actual and the prediction moved away from the
    /// baseline, the share where they moved the same way. 0.5 is chance.
    var directionAgreement: Double
    var directionPairs: Int

    static func slice(_ label: String, _ pairs: [TrainingLoadModel.ScoredPair]) -> TwinSlice {
        guard !pairs.isEmpty else { return TwinSlice(label: label, n: 0, maeModel: 0, maeBaseline: 0) }
        let n = Double(pairs.count)
        return TwinSlice(label: label, n: pairs.count,
                         maeModel: pairs.map { abs($0.predicted - $0.actual) }.reduce(0, +) / n,
                         maeBaseline: pairs.map { abs($0.baseline - $0.actual) }.reduce(0, +) / n)
    }

    static func make(_ pairs: [TrainingLoadModel.ScoredPair], trainingDays: [Int],
                     topExercises: Int = 8) -> TwinDiagnosis {
        let byReps = [("1-5 reps", 1...5), ("6-10 reps", 6...10), ("11+ reps", 11...Int.max)].map { label, r in
            slice(label, pairs.filter { r.contains($0.actualReps) })
        }
        let byGap = [("gap 1-7 d", 1...7), ("gap 8-21 d", 8...21), ("gap 22+ d", 22...Int.max)].map { label, r in
            slice(label, pairs.filter { r.contains($0.day - $0.lastDay) })
        }
        let grouped = Dictionary(grouping: pairs, by: \.exercise)
        let byExercise = grouped.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(topExercises).map { slice($0.key, $0.value) }

        // A training day's week is dense when its 7-day block has 2+ training days.
        var perBlock: [Int: Int] = [:]
        for d in trainingDays { perBlock[Int((Double(d) / 7).rounded(.down)), default: 0] += 1 }
        let isDense = { (d: Int) in (perBlock[Int((Double(d) / 7).rounded(.down))] ?? 0) >= 2 }

        let moved = pairs.filter { $0.actual != $0.baseline && abs($0.predicted - $0.baseline) > 1e-9 }
        let agree = moved.filter { ($0.actual - $0.baseline) * ($0.predicted - $0.baseline) > 0 }.count

        return TwinDiagnosis(
            overall: slice("all", pairs),
            byReps: byReps, byGap: byGap, byExercise: byExercise,
            dense: slice("dense weeks", pairs.filter { isDense($0.day) }),
            sparse: slice("sparse weeks", pairs.filter { !isDense($0.day) }),
            directionAgreement: moved.isEmpty ? 0.5 : Double(agree) / Double(moved.count),
            directionPairs: moved.count)
    }

    var report: String {
        func line(_ s: TwinSlice) -> String {
            String(format: "%-28@ n=%4d twin %6.2f  last %6.2f  %+6.1f%%", s.label as NSString, s.n,
                   s.maeModel, s.maeBaseline, s.improvement * 100)
        }
        var out = [line(overall), line(dense), line(sparse)]
        out += byReps.map(line) + byGap.map(line) + byExercise.map(line)
        out.append(String(format: "direction agreement %.1f%% over %d moved pairs (chance 50%%)",
                          directionAgreement * 100, directionPairs))
        return out.joined(separator: "\n")
    }
}
