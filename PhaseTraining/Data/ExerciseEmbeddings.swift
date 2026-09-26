// ExerciseEmbeddings.swift — "more like this" for the exercise detail sheet
// (PLAN-next-gen.md, smaller ideas).
//
// On-device sentence embeddings (NaturalLanguage) over each catalog exercise's
// name, description and primary muscles; neighbours by cosine similarity.
// Nothing leaves the device and nothing is stored: the index is built once
// per launch, off the main thread, on first use.
//
// When the system has no English sentence-embedding asset the index is nil and
// the detail sheet hides the section. It never errors.

import Foundation
import NaturalLanguage

final class ExerciseEmbeddings {

    typealias Embed = (String) -> [Double]?

    private let entries: [(exercise: Exercise, vector: [Double])]

    /// Build over `exercises`. Returns nil when the embedder produces nothing
    /// (no asset), so callers hide the feature rather than show an empty row.
    init?(exercises: [Exercise], text: (Exercise) -> String, embed: Embed) {
        var built: [(Exercise, [Double])] = []
        for ex in exercises {
            guard let v = embed(text(ex)), !v.isEmpty else { continue }
            built.append((ex, Self.normalised(v)))
        }
        guard !built.isEmpty else { return nil }
        entries = built
    }

    /// Up to `k` exercises most similar to `exercise`, never itself, filtered
    /// by `allowed` (equipment, exclusions). Best first.
    func neighbours(of exercise: Exercise, k: Int = 6,
                    allowed: (Exercise) -> Bool = { _ in true }) -> [Exercise] {
        guard let query = entries.first(where: { $0.exercise.id == exercise.id })?.vector else { return [] }
        var scored: [(exercise: Exercise, score: Double)] = []
        for entry in entries where entry.exercise.id != exercise.id && allowed(entry.exercise) {
            scored.append((entry.exercise, Self.dot(query, entry.vector)))
        }
        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.exercise.id < rhs.exercise.id
        }
        return scored.prefix(k).map(\.exercise)
    }

    /// Nearest six by meaning, restricted to equipment the user has. An empty
    /// allow-list means unrestricted, the season engine's convention.
    func similar(to exercise: Exercise, allowedEquipment: Set<String>, k: Int = 6) -> [Exercise] {
        let pool = neighbours(of: exercise, k: 40)
        guard !allowedEquipment.isEmpty else { return Array(pool.prefix(k)) }
        let required = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: Set(pool.map(\.id)))
        return Array(pool.filter { (required[$0.id] ?? []).isSubset(of: allowedEquipment) }.prefix(k))
    }

    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        var total = 0.0
        for i in 0..<min(a.count, b.count) { total += a[i] * b[i] }
        return total
    }

    static func normalised(_ v: [Double]) -> [Double] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return norm > 0 ? v.map { $0 / norm } : v
    }

    // MARK: - Production index

    /// Name, description, then primary muscles: the words that say what an
    /// exercise is for, not how to set it up.
    static func text(for ex: Exercise) -> String {
        let primary = CoachDatabase.shared.musclesForExercise(ex.id)
            .filter { $0.role == "primary" }.map(\.label)
        return [ex.name, ex.description ?? "", primary.isEmpty ? "" : "Muscles: " + primary.joined(separator: ", ")]
            .filter { !$0.isEmpty }.joined(separator: ". ")
    }

    static let systemEmbed: Embed? = {
        guard let model = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        // The name carries half the weight: the full text alone ranked a back
        // squat's nearest as lunges and jumps, missing every other squat.
        return { text in
            guard let full = model.vector(for: text) else { return nil }
            let name = String(text.split(separator: ".", maxSplits: 1).first ?? "")
            guard let head = model.vector(for: name), head.count == full.count else { return full }
            let a = normalised(full), b = normalised(head)
            return zip(a, b).map { 0.5 * $0 + 0.5 * $1 }
        }
    }()

    private static let lock = NSLock()
    private static var cached: ExerciseEmbeddings??

    /// The catalog index, built on first call. Call off the main thread.
    static func shared() -> ExerciseEmbeddings? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let built = systemEmbed.flatMap { embed in
            ExerciseEmbeddings(exercises: CoachDatabase.shared.searchExercises(search: nil).exercises,
                               text: text(for:), embed: embed)
        }
        cached = .some(built)
        return built
    }
}
