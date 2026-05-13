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
}

extension Exercise {
    var modalityLabel: String {
        (modality ?? "—").replacingOccurrences(of: "_", with: " ").capitalized
    }

    var difficultyLabel: String { (difficulty ?? "—").capitalized }
}
