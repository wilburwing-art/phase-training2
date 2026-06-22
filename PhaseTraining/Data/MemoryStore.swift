// MemoryStore.swift — @Published wrapper around TrainingMemory.
// Single UserDefaults key (`pt_training_memory`), JSON-encoded with the same
// secondsSince1970 date strategy SessionStore uses (so JSON dumps are uniform).
//
// API mirrors the rest of the data layer: explicit save() + a convenience
// update(_:) closure that mutates and persists in one call. Onboarding uses
// completeOnboarding() to stamp the gate.
//
// ---------------------------------------------------------------------------
// Privacy posture
// ---------------------------------------------------------------------------
// - All user data lives on-device: profile in `UserDefaults.standard`, and
//   saved sessions / custom routines / imported history in the on-disk SQLite
//   `UserDatabase`. No backend, no analytics fan-out.
// - Health-adjacent fields (age, gender, height, weight, body-composition)
//   carry an inline `/// SENSITIVE.` marker in TrainingMemory.swift. Treat it
//   as a hard signal: do not log, do not include in crash reports, do not send
//   to any third-party SDK without an explicit privacy review.
// - Data minimization: don't add a health-adjacent field unless a feature
//   actually consumes it — each one grows the App Store privacy disclosure and
//   the GDPR special-category surface.
// - Deletion: `wipeAllUserData(...)` is the single canonical "erase
//   everything" path, used by BOTH the production "Erase all my data" action
//   in ProfileScreen and the `--ui-test-reset` launch hook so the two can't
//   drift. It sweeps the UserDefaults keyspace by prefix AND clears the SQLite
//   store, so new persistent state is covered automatically — no hand-kept key
//   list to fall out of date.

import Foundation
import Combine
import UserNotifications

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

    /// How many times the user must swap AWAY from an exercise before its
    /// affinity is nudged down by one. A single swap-away is "not today," not a
    /// vote against the exercise; repeated swaps-away are the durable negative.
    static let swapAwayDemoteThreshold = 3

    /// Record an exercise swap (A → B) as a preference signal. The replacement
    /// gets an immediate +1 affinity so the generator surfaces it more often;
    /// the original is demoted by one only once the user has swapped away from
    /// it `swapAwayDemoteThreshold` times. Keyed by exercise name — the same
    /// vocabulary `bumpAffinity` and the generator's name-match use. No-op when
    /// the names are equal (a swap to the same exercise carries no signal).
    func recordSwap(out original: String, in replacement: String) {
        guard original.caseInsensitiveCompare(replacement) != .orderedSame else { return }
        update {
            $0.exerciseAffinities[replacement, default: 0] += 1
            let count = ($0.swapAwayCounts[original] ?? 0) + 1
            $0.swapAwayCounts[original] = count
            if count % Self.swapAwayDemoteThreshold == 0 {
                $0.exerciseAffinities[original, default: 0] -= 1
            }
        }
    }

    /// Re-read memory from UserDefaults, discarding the in-memory copy. Used
    /// after a destructive backup-restore so this already-instantiated store
    /// reflects the imported data without an app relaunch.
    func reload() {
        if let data = defaults.data(forKey: Self.key),
           let m = try? Self.decoder().decode(TrainingMemory.self, from: data) {
            memory = m
        } else {
            memory = TrainingMemory()
        }
    }

    /// Reset everything — only used in dev / preview / "Reset onboarding" debug action.
    func reset() {
        memory = TrainingMemory()
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Full wipe

    /// Erase everything this app has persisted on the device, across BOTH
    /// storage layers:
    ///   - UserDefaults: every key this app owns. They're all `pt_`-prefixed,
    ///     so we sweep the prefix rather than maintain a hand-written list (the
    ///     list approach silently drifted as new stores were added — coach
    ///     archives, sport logs, plan overrides, etc. went unwiped). Anything
    ///     non-`pt_` (system/SDK state) is left untouched.
    ///   - SQLite (`UserDatabase`): saved sessions, custom routines, imported
    ///     history (these migrated out of UserDefaults; a defaults-only wipe
    ///     would leave all workout history on disk).
    /// Plus any pending local notification.
    ///
    /// Callers holding live @Published stores must reset those separately
    /// (ProfileScreen.eraseAllData does; `--ui-test-reset` runs at launch
    /// before the stores are built, so disk state is all that matters there).
    static func wipeAllUserData(defaults: UserDefaults = .standard,
                                userDB: UserDatabase? = nil) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pt_") {
            defaults.removeObject(forKey: key)
        }
        (userDB ?? UserDatabase.defaultStore()).wipeAll()
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pt.weekly_reminder"])
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
