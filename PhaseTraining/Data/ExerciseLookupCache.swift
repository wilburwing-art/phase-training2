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

/// Per-name resolved bundle. nil fields mean coach.db has no row by that
/// name (custom-routine entries with no DB linkage, user-added one-offs).
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

    /// Test-only / preview hook to clear all cached resolutions.
    func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    // MARK: - Resolution

    private func resolve(name: String) -> ExerciseLookup {
        let dbEx = CoachDatabase.shared
            .listExercises(search: name)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard let dbEx else {
            return ExerciseLookup(exercise: nil, bucket: nil, thumbnailURL: nil)
        }
        let muscles = CoachDatabase.shared.musclesForExercise(dbEx.id)
        let primary = muscles.first(where: { $0.role == "primary" }) ?? muscles.first
        let bucket = primary.flatMap { MuscleBucket.bucket(forSlug: $0.slug) }
        let thumb = dbEx.thumbnailURL ?? dbEx.imageURL
        return ExerciseLookup(exercise: dbEx, bucket: bucket, thumbnailURL: thumb)
    }
}
