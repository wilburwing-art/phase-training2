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
    /// External demo video link (YouTube / Vimeo). Opened in Safari /
    /// platform app rather than embedded to sidestep embedding TOS.
    let videoURL: String?
    /// Human-readable attribution for `videoURL` (e.g. "Squat University
    /// (YouTube)"). Surfaced next to the video link in the UI.
    let sourceVideoAttribution: String?
}

extension Exercise {
    var modalityLabel: String {
        (modality ?? "—").replacingOccurrences(of: "_", with: " ").capitalized
    }

    var difficultyLabel: String { (difficulty ?? "—").capitalized }

    /// Shared catalog meta line: "Modality · Difficulty[ · Compound]".
    /// Pass `includeCompound: false` for dense surfaces (the exercise
    /// picker) that drop the compound tag to keep the line short.
    func metaLabel(includeCompound: Bool = true) -> String {
        var parts: [String] = []
        if modalityLabel != "—" { parts.append(modalityLabel) }
        if difficultyLabel != "—" { parts.append(difficultyLabel) }
        if includeCompound && isCompound { parts.append("Compound") }
        return parts.joined(separator: " · ")
    }
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
