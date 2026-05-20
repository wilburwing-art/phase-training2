// CustomRoutineStore.swift — @Published list of user-created workouts.
//
// Backed by SQLite (`user.db` in Documents) via UserDatabase. On first launch
// after the SQLite migration shipped, any pre-existing `pt_custom_routines`
// UserDefaults JSON blob is imported into user.db and the key is cleared.
// Subsequent saves write straight through to user.db; the @Published list is
// the read-through cache that SwiftUI binds to.

import Foundation
import Combine

final class CustomRoutineStore: ObservableObject {
    private static let legacyKey = "pt_custom_routines"
    private static let migrationFlag = "pt_custom_routines_migrated_v1"

    @Published var routines: [CustomRoutine]

    private let defaults: UserDefaults
    private let userDB: UserDatabase

    init(defaults: UserDefaults = .standard, userDB: UserDatabase = .shared) {
        self.defaults = defaults
        self.userDB = userDB
        Self.migrateLegacyIfNeeded(defaults: defaults, userDB: userDB)
        self.routines = userDB.listRoutines()
    }

    // MARK: - Mutation

    /// Insert or update (matched by id). New routines float to the top by
    /// virtue of `created_at DESC` in UserDatabase.listRoutines.
    func save(_ routine: CustomRoutine) {
        userDB.save(routine)
        routines = userDB.listRoutines()
    }

    func delete(_ routine: CustomRoutine) {
        userDB.delete(routineId: routine.id)
        routines = userDB.listRoutines()
    }

    func clear() {
        userDB.clearAll()
        routines = []
    }

    // MARK: - One-shot migration

    /// Imports the old UserDefaults JSON blob into UserDatabase on first
    /// launch of the SQLite-backed build. Guarded by a flag so reruns are
    /// no-ops. The legacy UserDefaults key is removed after a successful
    /// import so it doesn't keep getting iCloud-backed up forever.
    private static func migrateLegacyIfNeeded(defaults: UserDefaults, userDB: UserDatabase) {
        if defaults.bool(forKey: migrationFlag) { return }
        defer { defaults.set(true, forKey: migrationFlag) }

        guard let data = defaults.data(forKey: legacyKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let legacy = try? decoder.decode([CustomRoutine].self, from: data) else { return }

        for routine in legacy {
            userDB.save(routine)
        }
        defaults.removeObject(forKey: legacyKey)
    }
}
