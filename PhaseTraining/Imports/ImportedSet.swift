// ImportedSet.swift — Phase 3 CSV strength-import row.
//
// One row per logged working set imported from Fitbod / Hevy / Strava /
// other CSV history. Lives alongside `ImportedWorkout` (workout-level
// summary from Phase 2 HK + CSV cardio) in user.db.
//
// Why a separate type from `SavedSession.LoggedSet`: imports come without
// a session container — Fitbod logs a flat per-set stream and we don't
// always know which sets belong to which session until we cluster by
// date. Keep imports flat and let `GeneratorContext.from(...)` aggregate.
//
// Why `exerciseId` is optional: CSV exercise names that don't fuzzy-match
// any coach.db row still get preserved (zero-data-loss policy) but can't
// safely feed priorBest. The Settings → Imports screen surfaces the
// match rate so the user can decide whether to re-import with a fixed
// catalog or accept the partial coverage.

import Foundation

struct ImportedSet: Equatable, Sendable, Codable {
    /// Stable primary key. `source:performed_at:exercise_name_raw:set_num`
    /// — deterministic so a re-import of the same CSV idempotently
    /// replaces rather than duplicates.
    let id: String
    let source: ImportSource
    /// Resolved coach.db exercise id; nil when the raw name didn't match.
    let exerciseId: Int?
    let exerciseNameRaw: String
    let performedAt: Date
    /// 1-indexed set position within the row's exercise on that date.
    let setNum: Int
    /// Weight in kilograms (canonical unit in our schema). Nil for
    /// bodyweight / cardio rows that still carry rep data.
    let weight: Double?
    /// Nil for cardio rows where the row is duration-based.
    let reps: Int?
    /// Reps-in-reserve, when the source captures it (Hevy does, Fitbod
    /// does not).
    let rir: Double?
    /// RPE, when the source captures it (Hevy does, Fitbod does not).
    let rpe: Double?

    /// Construct a stable id from the natural-key tuple.
    static func makeId(source: ImportSource, performedAt: Date, exerciseNameRaw: String, setNum: Int) -> String {
        let ts = Int64(performedAt.timeIntervalSince1970)
        // Trim the name so trailing-space-padded CSV fields don't drift the id.
        let name = exerciseNameRaw.trimmingCharacters(in: .whitespaces)
        return "\(source.rawValue):\(ts):\(name):\(setNum)"
    }
}
