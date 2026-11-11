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

extension ActiveSession {
    /// Total load moved: weight × reps over done working sets, in the lifter's
    /// unit. Warm-ups are left out. A bodyweight row counts only its added load
    /// (a vest or plate), since the logged weight is the addition.
    func workingVolume(usesImperial: Bool) -> Double {
        exercises.reduce(0) { total, ex in
            let isKg = ex.unit.lowercased() == "kg"
            let factor: Double
            switch (isKg, usesImperial) {
            case (true, true): factor = 1 / ImportUnitCorrection.kgPerLb
            case (false, false): factor = ImportUnitCorrection.kgPerLb
            default: factor = 1
            }
            return total + ex.sets.reduce(0) { sum, set in
                guard set.done, !set.isWarmup,
                      let w = set.weightValue, w > 0,
                      let r = set.repsValue, r > 0 else { return sum }
                return sum + w * Double(r) * factor
            }
        }
    }
}

/// Tag vocabulary for `SavedSession.sessionTags`. A raw-value enum so the
/// persisted strings stay stable; `label` is display-only.
enum SessionTag: String, Codable, CaseIterable, Identifiable {
    case testDay, maxAttempt, lightDay, techniqueFocus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .testDay:        return "Test day"
        case .maxAttempt:     return "Max attempt"
        case .lightDay:       return "Light day"
        case .techniqueFocus: return "Technique focus"
        }
    }
}

struct SessionStats: Equatable {
    var totalSets: Int
    var doneSets: Int
    var avgRpe: String // matches prototype's "-" sentinel when no RPEs logged
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
