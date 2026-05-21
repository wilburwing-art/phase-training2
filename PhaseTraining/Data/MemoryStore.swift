// MemoryStore.swift — @Published wrapper around TrainingMemory.
// Single UserDefaults key (`pt_training_memory`), JSON-encoded with the same
// secondsSince1970 date strategy SessionStore uses (so JSON dumps are uniform).
//
// API mirrors the rest of the data layer: explicit save() + a convenience
// update(_:) closure that mutates and persists in one call. Onboarding uses
// completeOnboarding() to stamp the gate.

import Foundation
import Combine

final class MemoryStore: ObservableObject {
    private static let key = "pt_training_memory"

    @Published var memory: TrainingMemory

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let m = try? Self.decoder().decode(TrainingMemory.self, from: data) {
            self.memory = m
        } else {
            self.memory = TrainingMemory()
        }
    }

    // MARK: - Persistence

    func save() {
        if let data = try? Self.encoder().encode(memory) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Mutate + persist in one call. Use this anywhere outside the onboarding
    /// flow so callers can't forget save().
    func update(_ block: (inout TrainingMemory) -> Void) {
        block(&memory)
        save()
    }

    // MARK: - Lifecycle helpers

    var isOnboarded: Bool { memory.onboardedAt != nil }

    func completeOnboarding(at date: Date = Date()) {
        update { $0.onboardedAt = date }
    }

    /// Bump the per-exercise affinity score by `delta`. Positive = "recommend
    /// more often"; negative = "recommend less often". Keyed by exercise name
    /// (same vocabulary the rest of the app uses for joins back to coach.db).
    func bumpAffinity(_ exerciseName: String, by delta: Int) {
        update {
            let current = $0.exerciseAffinities[exerciseName] ?? 0
            $0.exerciseAffinities[exerciseName] = current + delta
        }
    }

    /// Reset everything — only used in dev / preview / "Reset onboarding" debug action.
    func reset() {
        memory = TrainingMemory()
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - JSON

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
