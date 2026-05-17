// CustomRoutineStore.swift — @Published list of user-created workouts.
//
// UserDefaults key: `pt_custom_routines`. JSON-encoded with the same
// secondsSince1970 date strategy the other data stores use so dumps stay
// uniform. API mirrors MemoryStore: explicit save() + an update closure for
// in-place edits that auto-persist.

import Foundation
import Combine

final class CustomRoutineStore: ObservableObject {
    private static let key = "pt_custom_routines"

    @Published var routines: [CustomRoutine]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let list = try? Self.decoder().decode([CustomRoutine].self, from: data) {
            self.routines = list
        } else {
            self.routines = []
        }
    }

    // MARK: - Mutation

    /// Insert or update (matched by id). New routines land at the top so the
    /// most-recently-created workout is easiest to find.
    func save(_ routine: CustomRoutine) {
        if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[idx] = routine
        } else {
            routines.insert(routine, at: 0)
        }
        persist()
    }

    func delete(_ routine: CustomRoutine) {
        routines.removeAll { $0.id == routine.id }
        persist()
    }

    func clear() {
        routines = []
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? Self.encoder().encode(routines) {
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
