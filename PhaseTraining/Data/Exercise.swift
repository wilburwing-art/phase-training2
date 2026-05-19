import Foundation

struct Exercise: Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let description: String?
    let instructions: String?
    let cues: [String]
    let difficulty: String?
    let modality: String?
    let environment: String?
    let isCompound: Bool
    let isUnilateral: Bool

    let defaultSets: Int?
    let defaultReps: String?
    let defaultRest: String?
    let defaultDuration: String?

    let regression: String?
    let progression: String?

    /// Full-resolution photo URL when available. Currently sourced from
    /// `yuhonas/free-exercise-db` (~17% catalog coverage); nil otherwise.
    let imageURL: String?
    /// Thumbnail-grade photo URL — same source today, may diverge later.
    let thumbnailURL: String?
}

extension Exercise {
    var modalityLabel: String {
        (modality ?? "—").replacingOccurrences(of: "_", with: " ").capitalized
    }

    var difficultyLabel: String { (difficulty ?? "—").capitalized }
}

/// A single alternative exercise sourced from `exercise_substitutions`.
/// `contexts` aggregates every context tag the same substitute appeared
/// under (e.g. ["home_friendly", "lower_intensity"]) so the picker can show
/// the user *why* this swap is reasonable. `score` is the max similarity
/// across those rows (0.0–1.0).
struct ExerciseSubstitute: Identifiable, Hashable {
    let exercise: Exercise
    var contexts: [String]
    var score: Double
    var notes: String?

    var id: Int { exercise.id }

    var contextLabels: [String] {
        contexts.map {
            $0.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var matchPercent: Int { Int((score * 100).rounded()) }
}
