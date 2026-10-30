// ImportMaintenance.swift — bring stored imports up to the current rules.
//
// Imports are resolved and unit-checked once, at import time. When the
// catalog gains aliases or `ImportUnitCorrection` ships, rows imported by an
// older build keep their nil exercise ids and their 2.2x-heavy kg era until
// the user re-imports, which nobody does. This pass re-applies both to the
// stored rows and writes back only the rows that changed, so it is cheap and
// a no-op on every launch after the first.

import Foundation

enum ImportMaintenance {

    /// Rows rewritten. Runs off the main thread at launch.
    @discardableResult
    static func run(db: UserDatabase = .shared, coach: CoachDatabase = .shared) -> Int {
        let stored = db.allImportedSets()
        guard !stored.isEmpty else { return 0 }

        let resolve = db.importNameResolver(coach: coach)
        var resolvedByName: [String: Int?] = [:]
        let resolved = stored.map { set -> ImportedSet in
            guard set.exerciseId == nil else { return set }
            if resolvedByName[set.exerciseNameRaw] == nil {
                resolvedByName[set.exerciseNameRaw] = .some(resolve(set.exerciseNameRaw))
            }
            return set.withExerciseId(resolvedByName[set.exerciseNameRaw] ?? nil)
        }

        // One app's history at a time: a unit era is a property of how one
        // source was set up, never a mix of two.
        var corrected = resolved
        for indices in Dictionary(grouping: resolved.indices, by: { resolved[$0].source }).values {
            let fixed = ImportUnitCorrection.apply(indices.map { resolved[$0] }).sets
            for (i, set) in zip(indices, fixed) { corrected[i] = set }
        }

        let changed = zip(stored, corrected).filter { $0 != $1 }.map(\.1)
        if !changed.isEmpty { db.insertImportedSets(changed) }
        return changed.count
    }
}
