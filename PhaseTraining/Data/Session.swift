// Session.swift — app-side extensions and types around the session models.
// The models themselves (LoggedSet, LoggedExercise, ActiveSession,
// SavedSession) live in Shared/Models/SessionModels.swift so the watch app
// can compile them.

import Foundation

extension LoggedExercise {
    /// Map an `EquipmentCategory` to the weight-logging unit carried on the
    /// session row. `.repsOnly` collapses to bodyweight; everything else logs
    /// in lbs. Centralised so the generated / custom / bundled template
    /// builders stay in sync.
    static func unit(for category: EquipmentCategory?) -> String {
        category == .repsOnly ? bodyweightUnit : "lbs"
    }
}

struct SessionStats: Equatable {
    var totalSets: Int
    var doneSets: Int
    var avgRpe: String // matches prototype's "—" sentinel when no RPEs logged
}

/// A personal-record event: highest weight ever lifted at a given rep count
/// for a given exercise (matched by name). Emitted by `SessionStore.prs(in:)`
/// after each saved session for CompleteScreen to celebrate.
struct PersonalRecord: Equatable, Hashable {
    let exerciseName: String
    let reps: Int
    let weight: Double
    let previousBest: Double?
    let date: Date
}
