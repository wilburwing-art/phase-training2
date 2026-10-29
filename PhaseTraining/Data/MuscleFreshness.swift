// MuscleFreshness.swift — per-muscle recovery from logged volume.
//
// Each session leaves fatigue on the muscles it loaded: a done working set
// counts 1.0 toward its PRIMARY muscles and 0.5 toward its secondaries.
// That load sets how long the muscle takes to recover:
//
//     hours = baseHours[slug] × clamp(sqrt(load / 6), 0.5, 1.75)
//
// so six hard sets recover in the base time, twelve in about 1.4 times it,
// and one set in half of it. Fatigue left by each session falls linearly to
// zero over that time, and sessions stack: two leg days in a row leave more
// than one. Freshness is 1 minus the summed fatigue, clamped to 0...1.
//
// Base hours are starting estimates from general recovery research (large
// prime movers about 2.5 days at moderate volume, small muscles 1.5); the
// season-week probe in SorenessSelectionTests keeps them from blocking the
// app's own sport spacing. The Recovery cards and the generator's recovery
// gate (MuscleRecovery) read these same numbers.

import Foundation

enum MuscleFreshness {

    /// Hours to full recovery after a reference load of six working sets,
    /// by muscle_groups.slug. Anything not listed uses `defaultBaseHours`.
    static let baseHours: [String: Double] = {
        var out: [String: Double] = [:]
        let large = ["quadriceps", "rectus-femoris", "vastus-medialis", "vastus-lateralis", "vastus-intermedius",
                     "hamstrings", "biceps-femoris", "semitendinosus", "semimembranosus",
                     "glutes", "glute-max", "glute-med", "glute-min",
                     "back", "lats", "erector-thoracic", "erector-lumbar",
                     "chest", "pec-major-clav", "pec-major-sternal", "pec-minor"]
        let medium = ["shoulders", "delt-anterior", "delt-lateral", "delt-posterior",
                      "adductors", "traps", "upper-traps", "mid-traps", "lower-traps", "rhomboids"]
        for s in large { out[s] = 60 }
        for s in medium { out[s] = 48 }
        return out
    }()

    /// Small muscles: arms, calves, forearms, core, neck, rotator cuff.
    static let defaultBaseHours: Double = 36

    /// Working sets that recover in exactly `baseHours`.
    static let referenceSets: Double = 6

    /// Load a set puts on a secondary muscle, relative to a primary one.
    static let secondaryWeight: Double = 0.5

    /// Hours for `slug` to recover fully from `load` set-equivalents.
    static func recoveryHours(slug: String, load: Double) -> Double {
        let scale = min(max((load / referenceSets).squareRoot(), 0.5), 1.75)
        return (baseHours[slug] ?? defaultBaseHours) * scale
    }

    /// One session's load per muscle slug, in set-equivalents.
    struct Exposure: Equatable {
        let start: Date
        let loads: [String: Double]
    }

    /// Output row: per-muscle freshness + the last-worked date so callers
    /// can render "3 days" / "no recent exercises" subtitles.
    struct Row: Equatable {
        let slug: String
        let label: String
        let freshness: Double      // 0.0 = just trained, 1.0 = fully recovered
        let lastWorked: Date?      // nil if never trained (in window)
        let daysSinceLastWorked: Int? // nil if never trained

        /// Map to the BodyAnatomyView highlight intensity. Inverts the usual
        /// semantic — red means "do NOT train this", gray means "fresh".
        var intensity: BodyAnatomyView.HighlightIntensity {
            if freshness >= 1.0 { return .none }
            if freshness < 0.33 { return .primary }
            if freshness < 0.66 { return .secondary }
            return .tertiary
        }
    }

    /// Per-session muscle loads. Only done, non-warm-up sets count; an
    /// exercise the resolver doesn't know contributes nothing. Name lookups
    /// are memoized across the call.
    static func exposures(
        from sessions: [SavedSession],
        resolve: MuscleVolume.NameResolver = MuscleVolume.defaultResolve
    ) -> [Exposure] {
        var resolved: [String: MuscleVolume.ResolvedExercise?] = [:]
        return sessions.compactMap { session in
            var loads: [String: Double] = [:]
            for ex in session.exercises {
                let sets = Double(ex.sets.filter { $0.done && !$0.isWarmup }.count)
                guard sets > 0 else { continue }
                let info: MuscleVolume.ResolvedExercise?
                if let cached = resolved[ex.name] {
                    info = cached
                } else {
                    info = resolve(ex.name)
                    resolved[ex.name] = info
                }
                for muscle in info?.muscles ?? [] {
                    switch muscle.role {
                    case "primary":   loads[muscle.slug, default: 0] += sets
                    case "secondary": loads[muscle.slug, default: 0] += sets * secondaryWeight
                    default: break
                    }
                }
            }
            return loads.isEmpty ? nil : Exposure(start: session.startTime, loads: loads)
        }
    }

    /// Sessions logged more than this far after the anchor are ignored: they
    /// have not happened yet from that point of view (a past day being
    /// rebuilt). Anything closer is clock skew and counts as just trained.
    static let futureTolerance: TimeInterval = 6 * 3600

    /// Freshness of `slug` at `now`: 1 minus the fatigue every exposure has
    /// left, clamped to 0...1.
    static func freshness(of slug: String, exposures: [Exposure], at now: Date) -> Double {
        var fatigue = 0.0
        for e in exposures {
            guard let load = e.loads[slug], load > 0,
                  e.start.timeIntervalSince(now) <= futureTolerance else { continue }
            let hours = max(0, now.timeIntervalSince(e.start)) / 3600
            fatigue += max(0, 1 - hours / recoveryHours(slug: slug, load: load))
        }
        return max(0, 1 - min(1, fatigue))
    }

    /// Compute freshness for every muscle_groups slug.
    ///
    /// - Parameters:
    ///   - sessions: full saved-session history (in any order).
    ///   - now: time anchor (defaults to `Date()`).
    ///   - resolve: exercise-name → muscles resolver. Production callers
    ///     pass `MuscleVolume.defaultResolve` so we hit CoachDatabase via
    ///     the same memoized path.
    ///   - allMuscles: every slug we want a row for. Production passes
    ///     `CoachDatabase.shared.allMuscleGroups()`; tests inject a small
    ///     subset.
    static func rows(
        from sessions: [SavedSession],
        now: Date = Date(),
        resolve: MuscleVolume.NameResolver = MuscleVolume.defaultResolve,
        allMuscles: [(slug: String, name: String)] = MuscleFreshness.defaultMuscleList()
    ) -> [Row] {
        let exposures = exposures(from: sessions, resolve: resolve)
            .filter { $0.start.timeIntervalSince(now) <= futureTolerance }
        return allMuscles.map { (slug, name) in
            let last = exposures.filter { $0.loads[slug, default: 0] > 0 }.map(\.start).max()
            return Row(
                slug: slug,
                label: name,
                freshness: freshness(of: slug, exposures: exposures, at: now),
                lastWorked: last,
                daysSinceLastWorked: last.map { Int((max(0, now.timeIntervalSince($0)) / 86_400).rounded(.down)) }
            )
        }
    }

    /// slug → intensity dictionary ready to drop into BodyAnatomyView.
    /// Convenience over `rows(from:)` for the top-of-screen body silhouette.
    static func highlights(
        from sessions: [SavedSession],
        now: Date = Date(),
        resolve: MuscleVolume.NameResolver = MuscleVolume.defaultResolve,
        allMuscles: [(slug: String, name: String)] = MuscleFreshness.defaultMuscleList()
    ) -> [String: BodyAnatomyView.HighlightIntensity] {
        let rs = rows(from: sessions, now: now, resolve: resolve, allMuscles: allMuscles)
        var out: [String: BodyAnatomyView.HighlightIntensity] = [:]
        for r in rs {
            // Skip .none rows — leaves the body silhouette gray for fresh
            // muscles, which is the intended look (only show what needs
            // recovery).
            if r.intensity != .none {
                out[r.slug] = r.intensity
            }
        }
        return out
    }

    /// Production default for `allMuscles` — pulled from CoachDatabase once.
    /// Cached as a static-let so we don't re-query on every freshness call.
    static func defaultMuscleList() -> [(slug: String, name: String)] {
        CoachDatabase.shared.allMuscleGroups()
    }
}
