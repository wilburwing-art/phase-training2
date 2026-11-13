// ExerciseLookupCache.swift — single-flight memoization of coach.db lookups
// keyed by exercise name.
//
// The composite tile migration (HANDOFF §4a) has every Today / preview /
// coach-request row resolving (a) the primary muscle bucket and (b) a
// thumbnail URL for the leading photo slot. Both lookups hit
// `CoachDatabase.listExercises(search:)` — a SQL LIKE scan — once per row,
// per render. For a 6-exercise Today screen that's 12 scans per redraw, and
// SwiftUI redraws frequently. This cache collapses them to a single hit per
// unique name per app session.
//
// Cache key is the exercise name (case-insensitive). Cache value is a
// resolved bundle: the matching `Exercise?` row, the primary `MuscleBucket?`,
// and the photo URL string (thumbnailURL or imageURL fallback). All three
// are computed together because the underlying SQL query that surfaces the
// `Exercise` row is the same one that drives the muscles + photo lookups.
//
// Backed by an NSLock — the cache is read on the main thread by SwiftUI
// view bodies but `CoachDatabase` itself synchronizes reads under its
// recursive lock, so the cache lock here is light-weight insurance for any
// future off-main resolution path (preloading, prefetch, etc.).

import Foundation

/// Per-name resolved bundle. nil fields mean neither coach.db nor the user's
/// custom exercises have a row by that name (a free-typed one-off). A custom
/// exercise resolves with its own bucket and no photo.
struct ExerciseLookup {
    let exercise: Exercise?
    let bucket: MuscleBucket?
    let thumbnailURL: String?
}

final class ExerciseLookupCache {
    /// Process-wide singleton — same lifetime as `CoachDatabase.shared`.
    static let shared = ExerciseLookupCache()

    private var entries: [String: ExerciseLookup] = [:]
    private let lock = NSLock()

    /// Where custom exercises are read from after both catalog attempts miss.
    /// `.shared` in production; under XCTest and previews an isolated empty
    /// in-memory store, so a test never reads the simulator's real user.db.
    /// Tests that need custom names assign their own store. Assigning clears
    /// the cache, since cached misses may now resolve.
    var userDB: UserDatabase? = UserDatabase.defaultStore() {
        didSet { reset() }
    }

    private init() {}

    /// Look up the resolved bundle for an exercise name. On cache miss, walks
    /// coach.db once and stores the resolution (including nil resolutions —
    /// negative caching prevents repeated misses on truly unknown names).
    func lookup(name: String) -> ExerciseLookup {
        let key = name.lowercased()
        lock.lock()
        if let hit = entries[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let resolved = resolve(name: name)

        lock.lock()
        entries[key] = resolved
        lock.unlock()
        return resolved
    }

    /// Convenience: just the bucket. Same single-lookup behavior.
    func bucket(forName name: String) -> MuscleBucket? {
        lookup(name: name).bucket
    }

    /// Convenience: just the thumbnail URL. Same single-lookup behavior.
    func thumbnailURL(forName name: String) -> String? {
        lookup(name: name).thumbnailURL
    }

    /// Convenience: just the resolved coach.db row.
    func exercise(forName name: String) -> Exercise? {
        lookup(name: name).exercise
    }

    /// Convenience: just the resolved exercise id. Used by composite-tile
    /// callers to drive the bundle-first WebP lookup in `ExerciseThumbnail`.
    func exerciseID(forName name: String) -> Int? {
        lookup(name: name).exercise?.id
    }

    /// Clear all cached resolutions. Called by UserDatabase whenever the
    /// custom-exercise table changes (create, delete, restore, clear, erase),
    /// because cached misses for a new name and cached hits for a deleted one
    /// would otherwise outlive the change. Also a test and preview hook.
    func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    // MARK: - Resolution

    private func resolve(name: String) -> ExerciseLookup {
        // Exact canonical name first. Generator-written plans carry canonical
        // names, so this is the hot path.
        var dbEx = CoachDatabase.shared
            .listExercises(search: name)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        // Then the shorthand path. Display names are deliberately short
        // ("Bench Press") while coach.db stays specific ("Barbell Bench
        // Press"), so an exact miss is expected here, not a data error.
        // Reuses the CSV importer's resolver, which walks name, then slug,
        // then exercise_aliases, with a trailing "(Foo)" strip. Without this
        // a shorthand name resolves to nil and the row renders a muscle-chip
        // placeholder while its photo sits unused in the bundle.
        if dbEx == nil,
           let id = CoachDatabase.shared.exerciseId(forImportName: name) {
            dbEx = CoachDatabase.shared.exercise(id: id)
        }
        // Custom exercises last, so the catalog always wins a name tie.
        // Creation already refuses catalog names; this is the read-side guard.
        guard let dbEx else {
            if let custom = userDB?.userExercise(named: name) {
                return ExerciseLookup(exercise: custom.exercise,
                                      bucket: custom.muscleBucket.flatMap(MuscleBucket.init(rawValue:)),
                                      thumbnailURL: nil)
            }
            return ExerciseLookup(exercise: nil, bucket: nil, thumbnailURL: nil)
        }
        let muscles = CoachDatabase.shared.musclesForExercise(dbEx.id)
        let primary = muscles.first(where: { $0.role == "primary" }) ?? muscles.first
        let bucket = primary.flatMap { MuscleBucket.bucket(forSlug: $0.slug) }
        let thumb = dbEx.thumbnailURL ?? dbEx.imageURL
        return ExerciseLookup(exercise: dbEx, bucket: bucket, thumbnailURL: thumb)
    }
}
