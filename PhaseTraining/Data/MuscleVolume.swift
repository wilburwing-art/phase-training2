// MuscleVolume.swift — per-muscle-group volume rollup for the Progress
// muscle-balance card.
//
// For each completed weighted set in the last N weeks, compute
// `weight × reps` and allocate that volume across the muscles the exercise
// targets. Role-weighted: primary > secondary > stabilizer. This lets a
// chest press contribute mostly to "chest" with a smaller pec-minor /
// triceps share, and a deadlift split across erectors / glutes / hamstrings.
//
// The exercise → muscles lookup goes through CoachDatabase. Logged sets
// only store the exercise NAME (not coach.db id), so we do a name→id
// resolve once per exercise per call and memoise within the call.

import Foundation

enum MuscleVolume {

    /// Volume share weights by exercise_muscles.role. Tuned so a typical
    /// compound lift's primary gets ~60% of the volume, secondaries ~25%,
    /// stabilisers ~15%. Then normalised per exercise so total = 1.0
    /// regardless of how many muscles each role contains.
    private static let roleWeight: [String: Double] = [
        "primary":    0.60,
        "secondary":  0.25,
        "stabilizer": 0.15,
    ]

    /// One muscle-group row for the card.
    struct Row: Identifiable, Equatable {
        var id: String { slug }
        let slug: String
        let label: String
        let volume: Double
    }

    /// Walk saved sessions in the last `weeks` weeks. For each completed set
    /// with weight + reps, compute volume and distribute across the
    /// exercise's muscles weighted by role. Returns the top `limit` rows by
    /// descending volume.
    ///
    /// `nameToExerciseId` is an injection point for tests — production calls
    /// pass `defaultResolve` which goes through `CoachDatabase.shared`.
    static func rows(from sessions: [SavedSession],
                     weeks: Int = 4,
                     limit: Int = 8,
                     now: Date = Date(),
                     resolve: NameResolver = defaultResolve) -> [Row] {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: now) ?? now
        var volumeBySlug: [String: Double] = [:]
        var labelBySlug: [String: String] = [:]

        // Memoise name → exercise lookup across the call. SQLite calls are
        // cheap individually but per-set lookups would multiply needlessly.
        var resolved: [String: ResolvedExercise?] = [:]

        for session in sessions where session.startTime >= cutoff {
            for ex in session.exercises {
                let exerciseInfo: ResolvedExercise?
                if let cached = resolved[ex.name] {
                    exerciseInfo = cached
                } else {
                    let r = resolve(ex.name)
                    resolved[ex.name] = r
                    exerciseInfo = r
                }
                guard let exerciseInfo else { continue }
                let allocations = normalisedAllocations(for: exerciseInfo.muscles)
                if allocations.isEmpty { continue }

                // Warmup sets excluded — volume aggregation reflects working
                // sets only. Warmups distort weekly volume comparisons.
                for set in ex.sets where set.done && !set.isWarmup {
                    let reps = Double(Int(set.reps) ?? 0)
                    let weight = Double(set.weight) ?? 0
                    guard reps > 0, weight > 0 else { continue }
                    let setVolume = weight * reps
                    for (slug, share) in allocations {
                        volumeBySlug[slug, default: 0] += setVolume * share
                        if labelBySlug[slug] == nil {
                            labelBySlug[slug] = exerciseInfo.label(for: slug) ?? slug
                        }
                    }
                }
            }
        }

        return volumeBySlug
            .map { Row(slug: $0.key, label: labelBySlug[$0.key] ?? $0.key, volume: $0.value) }
            .sorted { $0.volume > $1.volume }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Allocation math

    /// Convert a list of (slug, role) to (slug → share) with shares summing
    /// to 1.0 across the exercise. Each role's share is split evenly among
    /// the muscles tagged with that role.
    private static func normalisedAllocations(
        for muscles: [(slug: String, role: String, label: String)]
    ) -> [(slug: String, share: Double)] {
        // Group by role, count members.
        var byRole: [String: [String]] = [:]
        for m in muscles {
            byRole[m.role, default: []].append(m.slug)
        }
        // Raw share per muscle.
        var raw: [String: Double] = [:]
        for (role, slugs) in byRole {
            guard let weight = roleWeight[role], !slugs.isEmpty else { continue }
            let per = weight / Double(slugs.count)
            for slug in slugs { raw[slug, default: 0] += per }
        }
        let total = raw.values.reduce(0, +)
        guard total > 0 else { return [] }
        return raw.map { ($0.key, $0.value / total) }
    }

    // MARK: - Resolver protocol (testable injection)

    typealias NameResolver = (String) -> ResolvedExercise?

    struct ResolvedExercise {
        let muscles: [(slug: String, role: String, label: String)]
        func label(for slug: String) -> String? {
            muscles.first { $0.slug == slug }?.label
        }
    }

    /// Production resolver — looks up the exercise by name and fetches its
    /// muscle roles. `musclesForExercise` now returns labels in the same
    /// SQL row, so no separate label lookup is needed.
    static let defaultResolve: NameResolver = { name in
        let db = CoachDatabase.shared
        let exact = db.listExercises(search: name)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard let exact else { return nil }
        let muscles = db.musclesForExercise(exact.id)
        guard !muscles.isEmpty else { return nil }
        return ResolvedExercise(muscles: muscles)
    }
}
