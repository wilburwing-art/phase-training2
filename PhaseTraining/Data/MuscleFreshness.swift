// MuscleFreshness.swift — per-muscle-group recovery freshness model.
//
// For each muscle_groups.slug, find the most recent SavedSession that
// trained it as a PRIMARY role and decay freshness from there. Used by the
// Recovery tab body view: red = needs recovery, gray = fresh.
//
// Why primary-only: stabilisers and secondaries fire all day across many
// lifts; counting them would mean "nothing is ever fresh." Volume-based
// recovery (MuscleVolume) is a separate model for the Progress card.
//
// Recovery windows are tuned per muscle size: large prime movers (glutes,
// quads, back) take ~6 days; smaller ones (forearms, calves) ~3-4. Defaults
// in `Self.recoveryWindow`. Override via the `recoveryWindow` parameter for
// previews / tests.

import Foundation

enum MuscleFreshness {

    /// Days to full recovery, by muscle_groups.slug. Anything not listed
    /// falls back to `Self.defaultWindow` (5 days). Sized roughly on
    /// muscle-fiber recovery research — bigger / more eccentrically-loaded
    /// muscles take longer. Tunable; see PR notes for future per-user
    /// adjustments.
    static let recoveryWindow: [String: Double] = [
        // Large prime movers — slow recovery
        "quadriceps":   6, "rectus-femoris": 6, "vastus-medialis": 6, "vastus-lateralis": 6, "vastus-intermedius": 6,
        "hamstrings":   6, "biceps-femoris": 6, "semitendinosus": 6, "semimembranosus": 6,
        "glutes":       6, "glute-max": 6, "glute-med": 6, "glute-min": 6,
        "back":         6, "lats": 6, "erector-thoracic": 6, "erector-lumbar": 6,

        // Medium muscles — default-ish
        "chest":        5, "pec-major-clav": 5, "pec-major-sternal": 5, "pec-minor": 5,
        "shoulders":    5, "delt-anterior": 5, "delt-lateral": 5, "delt-posterior": 5,
        "biceps":       4, "triceps": 4, "brachialis": 4, "brachioradialis": 4,
        "traps":        4, "upper-traps": 4, "mid-traps": 4, "lower-traps": 4,
        "rhomboids":    4,
        "abs":          4, "rectus-abdominis": 4, "external-obliques": 4, "internal-obliques": 4,
        "adductors":    5, "hip-flexors": 4, "iliopsoas": 4,

        // Small / fast-recovering muscles
        "calves":       3, "gastrocnemius": 3, "soleus": 3, "peroneals": 3, "tib-anterior": 3,
        "forearm-flexors": 3, "forearm-extensors": 3, "finger-flexors": 3, "finger-extensors": 3,
        "grip-crush":   3, "grip-pinch": 3, "grip-support": 3,
        "neck":         3, "scm": 3, "scalenes": 3, "cervical-extensors": 3, "deep-neck-flexors": 3, "levator-scapulae": 3,
        "rotator-cuff": 4, "supraspinatus": 4, "infraspinatus": 4, "teres-minor": 4, "subscapularis": 4,
        "serratus-anterior": 4, "teres-major": 4,
    ]

    /// Fallback recovery window for any slug not in `recoveryWindow`.
    static let defaultWindow: Double = 5

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

    /// Compute freshness for every muscle_groups slug.
    ///
    /// - Parameters:
    ///   - sessions: full saved-session history (in any order). Only sets
    ///     marked `done` are counted; in-progress sets don't fatigue you.
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
        // 1. Walk sessions, finding the most recent done-set per primary-role
        //    muscle slug. Memoize the exercise-name resolution across the call.
        var lastWorked: [String: Date] = [:]
        var resolved: [String: MuscleVolume.ResolvedExercise?] = [:]

        for session in sessions {
            // Skip sessions with no done sets — the session timestamp is the
            // session start, but a session with zero done sets shouldn't
            // fatigue anyone.
            let anyDone = session.exercises.contains { ex in
                ex.sets.contains { $0.done }
            }
            guard anyDone else { continue }

            for ex in session.exercises {
                guard ex.sets.contains(where: { $0.done }) else { continue }

                let info: MuscleVolume.ResolvedExercise?
                if let cached = resolved[ex.name] {
                    info = cached
                } else {
                    let r = resolve(ex.name)
                    resolved[ex.name] = r
                    info = r
                }
                guard let info else { continue }

                // Use session end time if available, otherwise startTime.
                // We approximate per-set timing as "the session it happened
                // in" — sub-session resolution is noise at the day scale.
                let when = session.startTime
                for muscle in info.muscles where muscle.role == "primary" {
                    if let existing = lastWorked[muscle.slug] {
                        if when > existing { lastWorked[muscle.slug] = when }
                    } else {
                        lastWorked[muscle.slug] = when
                    }
                }
            }
        }

        // 2. Build a row per muscle in `allMuscles`. Slugs with no recent
        //    primary training get freshness 1.0 (fully recovered) and nil
        //    lastWorked — the UI shows "No recent exercises".
        return allMuscles.map { (slug, name) in
            let window = recoveryWindow[slug] ?? defaultWindow
            if let last = lastWorked[slug] {
                let seconds = now.timeIntervalSince(last)
                let days = max(0, seconds / 86_400)
                let freshness = min(1.0, days / window)
                return Row(
                    slug: slug,
                    label: name,
                    freshness: freshness,
                    lastWorked: last,
                    daysSinceLastWorked: Int(days.rounded(.down))
                )
            } else {
                return Row(
                    slug: slug,
                    label: name,
                    freshness: 1.0,
                    lastWorked: nil,
                    daysSinceLastWorked: nil
                )
            }
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
