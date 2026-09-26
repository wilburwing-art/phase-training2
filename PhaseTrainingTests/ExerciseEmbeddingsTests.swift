// ExerciseEmbeddingsTests.swift — "more like this".

import XCTest
@testable import PhaseTraining

final class ExerciseEmbeddingsTests: XCTestCase {

    private func ex(_ id: Int, _ name: String) -> Exercise {
        Exercise(id: id, name: name, slug: "t\(id)", description: nil, instructions: nil, cues: [],
                 difficulty: nil, modality: nil, environment: nil, isCompound: false, isUnilateral: false,
                 defaultSets: nil, defaultReps: nil, defaultRest: nil, defaultDuration: nil,
                 regression: nil, progression: nil, imageURL: nil, thumbnailURL: nil, videoURL: nil,
                 sourceVideoAttribution: nil)
    }

    /// Bag of words over a fixed vocabulary: deterministic, no model needed.
    private let vocab = ["squat", "leg", "press", "bench", "chest", "row", "back", "curl"]
    private lazy var bow: ExerciseEmbeddings.Embed = { [vocab] text in
        let t = text.lowercased()
        return vocab.map { t.contains($0) ? 1.0 : 0.0 }
    }

    func test_neighbours_rankBySimilarity_neverIncludeSelf_andRespectAllowed() throws {
        let all = [ex(1, "Squat leg"), ex(2, "Front squat leg"), ex(3, "Leg press"),
                   ex(4, "Bench press chest"), ex(5, "Back row")]
        let index = try XCTUnwrap(ExerciseEmbeddings(exercises: all, text: \.name, embed: bow))
        let n = index.neighbours(of: all[0], k: 3)
        XCTAssertEqual(n.map(\.id), [2, 3, 4], "squat's nearest are the other leg exercises")
        XCTAssertFalse(n.contains { $0.id == 1 })
        XCTAssertEqual(index.neighbours(of: all[0], k: 3, allowed: { $0.id != 2 }).first?.id, 3)
    }

    func test_noEmbeddingAvailable_meansNoIndex() {
        XCTAssertNil(ExerciseEmbeddings(exercises: [ex(1, "Squat")], text: \.name, embed: { _ in nil }))
    }

    /// The real on-device model: Barbell Back Squat's neighbours are mostly
    /// lower-body by their own primary muscles.
    func test_systemModel_squatNeighboursAreLowerBody() throws {
        guard let index = ExerciseEmbeddings.shared() else {
            throw XCTSkip("No English sentence-embedding asset on this simulator.")
        }
        let squat = try XCTUnwrap(CoachDatabase.shared.searchExercises(search: nil).exercises.first { $0.id == 57 })
        let n = index.neighbours(of: squat, k: 6)
        XCTAssertEqual(n.count, 6)
        let lower: Set<MuscleBucket> = [.quads, .hamstrings, .glutes, .calves]
        let lowerCount = n.filter { peer in
            CoachDatabase.shared.musclesForExercise(peer.id)
                .filter { $0.role == "primary" }
                .contains { MuscleBucket.bucket(forSlug: $0.slug).map(lower.contains) ?? false }
        }.count
        print("SIMILAR squat ->", n.map(\.name))
        XCTAssertGreaterThanOrEqual(lowerCount, 4, "neighbours: \(n.map(\.name))")
    }

    func test_equipmentFilter_dropsExercisesNeedingMissingGear() throws {
        guard let index = ExerciseEmbeddings.shared() else {
            throw XCTSkip("No English sentence-embedding asset on this simulator.")
        }
        let squat = try XCTUnwrap(CoachDatabase.shared.searchExercises(search: nil).exercises.first { $0.id == 57 })
        let bodyweightOnly: Set<String> = ["bodyweight"]
        let n = index.similar(to: squat, allowedEquipment: bodyweightOnly)
        let required = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: Set(n.map(\.id)))
        XCTAssertTrue(n.allSatisfy { (required[$0.id] ?? []).isSubset(of: bodyweightOnly) },
                      "got \(n.map(\.name))")
    }
}
