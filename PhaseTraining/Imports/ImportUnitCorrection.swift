// ImportUnitCorrection.swift — find an era of pounds typed in kg mode.
//
// A real Fitbod export (2016-2026) had Fitbod set to kg until late 2017
// while the lifter typed pound numbers: a 180 lb bench was stored as
// 180 kg and read back as 397 lb. Every exercise in that era sat 2.0-2.3x
// above its later level, which is how it surfaced as an impossible
// "target: 365 lb" for a lifter benching 135.
//
// The typed unit shows in the stored value. Fitbod stores kilograms; a
// number typed in kg is a plain kg number (on a 0.25 kg grid), while a
// number typed in lb arrives as lb x 0.45359237 with many decimals, which
// lands back on a 0.5 lb grid when converted. So each set reveals which
// unit was typed, and each session takes the majority.
//
// kg-typed sessions are only corrected when the same history also has
// lb-typed sessions AND the same exercises read 1.7-2.8x heavier on the kg
// side, the signature of pound numbers stored as kilograms. A lifter who
// trained in kg throughout, or switched units without the jump, is left
// alone. Correcting multiplies those sessions' weights by 0.45359237, after
// which they read as lb-typed, so a second pass changes nothing.

import Foundation

enum ImportUnitCorrection {

    static let kgPerLb = 0.45359237

    struct Report: Equatable {
        let correctedSets: Int
        let from: Date
        let through: Date
    }

    enum TypedUnit { case kg, lb }

    /// Which unit a stored kg value was typed in, or nil when it can't tell
    /// (both grids, or neither).
    static func typedUnit(kg: Double) -> TypedUnit? {
        guard kg > 0 else { return nil }
        let quarterKg = kg * 4
        let onKgGrid = abs(quarterKg - quarterKg.rounded()) < 0.001
        let halfLb = kg / kgPerLb * 2
        let onLbGrid = abs(halfLb - halfLb.rounded()) < 0.01
        switch (onKgGrid, onLbGrid) {
        case (true, false): return .kg
        case (false, true): return .lb
        default: return nil
        }
    }

    /// The corrected sets (same ids, so a write-back replaces in place) and
    /// what changed. Sets come back in the input order.
    ///
    /// One decision per history, not per stretch of sessions: the real export
    /// alternated kg-typed and lb-typed workouts week to week through 2017, so
    /// the kg sessions rarely sat in a run long enough to compare on their
    /// own. Instead every exercise logged both ways votes with the ratio of
    /// its kg-typed level to its lb-typed level; at least 3 such exercises
    /// with a median ratio of 1.7-2.8 convert every kg-typed session.
    static func apply(_ sets: [ImportedSet]) -> (sets: [ImportedSet], reports: [Report]) {
        let sessions = Dictionary(grouping: sets.indices, by: { sets[$0].performedAt })
        var kgSessions: [Date] = [], lbSessions: [Date] = []
        for (time, indices) in sessions {
            var kg = 0, lb = 0
            for i in indices {
                switch sets[i].weight.flatMap({ typedUnit(kg: $0) }) {
                case .kg: kg += 1
                case .lb: lb += 1
                case nil: break
                }
            }
            if kg > lb { kgSessions.append(time) } else if lb > kg { lbSessions.append(time) }
        }
        guard !kgSessions.isEmpty, !lbSessions.isEmpty else { return (sets, []) }

        let kgLevels = levels(sets, sessions: kgSessions.map { sessions[$0]! })
        let lbLevels = levels(sets, sessions: lbSessions.map { sessions[$0]! })
        let ratios = kgLevels.compactMap { name, a -> Double? in
            guard let b = lbLevels[name], b > 0 else { return nil }
            return a / b
        }
        guard ratios.count >= 3, let ratio = median(ratios), (1.7...2.8).contains(ratio) else {
            return (sets, [])
        }

        var out = sets
        var count = 0
        for time in kgSessions {
            for i in sessions[time]! {
                guard let w = out[i].weight, w > 0 else { continue }
                out[i] = out[i].withWeight(w * kgPerLb)
                count += 1
            }
        }
        let sorted = kgSessions.sorted()
        return (out, [Report(correctedSets: count, from: sorted.first!, through: sorted.last!)])
    }

    /// Median per-session best estimated 1RM, per raw exercise name, in
    /// stored kg. Warm-ups never reach imported_sets.
    private static func levels(_ sets: [ImportedSet], sessions: [[Int]]) -> [String: Double] {
        var perName: [String: [Double]] = [:]
        for session in sessions {
            var best: [String: Double] = [:]
            for i in session {
                guard let w = sets[i].weight, w > 0, let r = sets[i].reps, (1...12).contains(r) else { continue }
                let e = StrengthStandards.epley1RM(weight: w, reps: r)
                best[sets[i].exerciseNameRaw] = max(best[sets[i].exerciseNameRaw] ?? 0, e)
            }
            for (name, e) in best { perName[name, default: []].append(e) }
        }
        return perName.compactMapValues(median)
    }

    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

extension ImportedSet {
    func withWeight(_ kg: Double) -> ImportedSet {
        ImportedSet(id: id, source: source, exerciseId: exerciseId, exerciseNameRaw: exerciseNameRaw,
                    performedAt: performedAt, setNum: setNum, weight: kg, reps: reps, rir: rir, rpe: rpe)
    }

    func withExerciseId(_ exerciseId: Int?) -> ImportedSet {
        ImportedSet(id: id, source: source, exerciseId: exerciseId, exerciseNameRaw: exerciseNameRaw,
                    performedAt: performedAt, setNum: setNum, weight: weight, reps: reps, rir: rir, rpe: rpe)
    }
}
