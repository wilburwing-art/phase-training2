// RecentPicksStore.swift — what the generator has picked recently.
//
// The deterministic djb2 pick gave the same workout every regeneration for
// the same inputs. With variety memory the generator soft-filters against
// `recentlyPickedIds()` — exercises picked in the last 28 days drop to the
// back of the pool, so consecutive weeks of push days don't all bench press.
//
// Tracked in UserDefaults under `pt_recent_exercise_picks` as a tiny
// `[exerciseId: lastPickedAt]` map. Pruned aggressively at 60 days so the
// map never grows beyond the active exercise pool (~789 max possible).
//
// Soft filter, not hard: if every candidate for a slot has been picked
// recently (small variety pool), the pick still happens — variety is best-
// effort, never an empty slot.

import Foundation
import Combine

final class RecentPicksStore: ObservableObject {
    private static let key = "pt_recent_exercise_picks"
    /// Picks within this window count as "recent" for the soft filter.
    static let cutoffDays = 28
    /// Entries older than this are pruned on next write — bounded memory.
    private static let pruneAfterDays = 60

    @Published private(set) var lastPicked: [Int: Date]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let map = try? Self.decoder().decode([String: Date].self, from: data) {
            // JSON keys are strings; coerce back to Int.
            var rebuilt: [Int: Date] = [:]
            for (k, v) in map {
                if let id = Int(k) { rebuilt[id] = v }
            }
            self.lastPicked = rebuilt
        } else {
            self.lastPicked = [:]
        }
    }

    /// Stamp these exercise ids as picked at `date`. Called by PlanStore
    /// after every generate / regenerate / migrate. Idempotent — touching
    /// an existing id just bumps its timestamp.
    func record(exerciseIds: [Int], at date: Date = Date()) {
        guard !exerciseIds.isEmpty else { return }
        for id in exerciseIds { lastPicked[id] = date }
        prune()
        persist()
    }

    /// Exercise ids picked within `withinDays`. WorkoutGenerator uses this
    /// to deprioritize them for the next pick.
    func recentlyPickedIds(withinDays days: Int = RecentPicksStore.cutoffDays,
                           now: Date = Date()) -> Set<Int> {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return Set(lastPicked.filter { $0.value >= cutoff }.keys)
    }

    func clear() {
        lastPicked = [:]
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Persistence

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Double(Self.pruneAfterDays) * 86400)
        lastPicked = lastPicked.filter { $0.value >= cutoff }
    }

    private func persist() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: lastPicked.map { (String($0.key), $0.value) })
        if let data = try? Self.encoder().encode(stringKeyed) {
            defaults.set(data, forKey: Self.key)
        }
    }

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
