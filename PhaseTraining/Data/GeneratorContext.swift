// GeneratorContext.swift — runtime-history signals the WorkoutGenerator
// can use to make context-aware picks.
//
// Until build 66 the generator was blind to logged training: it picked
// exercises off DemographicProfile + dislikes + recentlyPicked and prescribed
// sets/reps from coach.db defaults adjusted by experience + age. No idea what
// the user actually lifted, what's sore, what's been overdone or skipped.
//
// This context is the analog of `CoachContext` for the deterministic side:
// derived once from `SavedSession[]` + `SorenessEntry[]` + `FeedbackEntry[]`,
// passed into the generator, queried during slot fulfillment + prescription.
// Pure value type — no DB calls during access, so the generator stays fast.
//
// `from(...)` IS allowed to hit `CoachDatabase` (to resolve exercise names →
// patterns / muscles), since it runs once per workout-build, not once per
// slot. The signals it produces are plain Swift collections.

import Foundation

struct GeneratorContext: Equatable {

    /// Most recent completed top-set per exercise NAME (lowercased). Used by
    /// the prescription to emit a progressive-overload target weight in
    /// `GeneratedExercise.notes`.
    var priorBest: [String: PriorBest]

    /// movement_patterns.slug → number of distinct days hit in the lookback
    /// window. Patterns with zero count are absent. The generator uses this
    /// to boost under-trained patterns when picking accessory slots.
    var patternFrequency: [String: Int]

    /// Lowercased body areas the user has reported sore or painful in the
    /// last 7 days. Slot pick excludes exercises whose primary muscle group
    /// label overlaps with this set.
    var recentSoreAreas: Set<String>

    /// Lowercased exercise names whose best estimated 1RM hasn't improved
    /// in 4+ weeks (using the StrengthStandards.epley1RM math). When the
    /// generator would otherwise pick one of these for a primary slot, it
    /// prefers a substitute from `exercise_substitutions`.
    var stagnantExercises: Set<String>

    /// muscle_groups.slug → role-allocated volume in the last 4 weeks (same
    /// math as `MuscleVolume.rows`). Accessory slot picks prefer exercises
    /// hitting muscles in the bottom third by volume.
    var muscleVolume: [String: Double]

    static let empty = GeneratorContext(
        priorBest: [:], patternFrequency: [:], recentSoreAreas: [],
        stagnantExercises: [], muscleVolume: [:]
    )

    var isEmpty: Bool {
        priorBest.isEmpty && patternFrequency.isEmpty &&
        recentSoreAreas.isEmpty && stagnantExercises.isEmpty &&
        muscleVolume.isEmpty
    }
}

/// One row in `priorBest` — the user's best logged top-set for an exercise.
struct PriorBest: Equatable {
    let weight: Double      // lb
    let reps: Int
    let date: Date
}

// MARK: - Builder

extension GeneratorContext {

    /// Build a context from raw stores. Pass `SessionStore.savedSessions`,
    /// `memory.soreness`, `memory.feedback`. Honors a 4-week window for
    /// pattern + volume signals, 7 days for soreness, 4 weeks since last PR
    /// for stagnation. `now` is injectable for tests.
    static func from(
        sessions: [SavedSession],
        soreness: [SorenessEntry],
        feedback: [FeedbackEntry],
        now: Date = Date()
    ) -> GeneratorContext {
        let cal = Calendar.current
        let weekCutoff = cal.date(byAdding: .weekOfYear, value: -4, to: now) ?? now
        let weekSoreCutoff = cal.date(byAdding: .day, value: -7, to: now) ?? now

        return GeneratorContext(
            priorBest: buildPriorBest(sessions: sessions),
            patternFrequency: buildPatternFrequency(sessions: sessions, cutoff: weekCutoff),
            recentSoreAreas: buildRecentSoreAreas(soreness: soreness,
                                                  feedback: feedback,
                                                  cutoff: weekSoreCutoff),
            stagnantExercises: buildStagnantExercises(sessions: sessions, now: now),
            muscleVolume: buildMuscleVolume(sessions: sessions, now: now)
        )
    }

    // MARK: - priorBest

    /// Walk sessions newest-first; first completed set with weight + reps
    /// for an exercise name wins. We treat "top-set" as the heaviest
    /// completed set in the user's most recent session for that exercise,
    /// not the all-time max — the generator wants "what did you actually
    /// do last time?" not "your best ever".
    private static func buildPriorBest(sessions: [SavedSession]) -> [String: PriorBest] {
        let ordered = sessions.sorted { $0.startTime > $1.startTime }
        var out: [String: PriorBest] = [:]
        for session in ordered {
            for ex in session.exercises {
                let key = ex.name.lowercased()
                guard out[key] == nil else { continue } // most recent session wins
                // Heaviest completed set in this session.
                // Warmup sets excluded — progressive-overload signal needs the
                // working top set, not a warmup ramp weight.
                var bestWeight = 0.0
                var bestReps = 0
                for set in ex.sets where set.done && !set.isWarmup {
                    let w = Double(set.weight) ?? 0
                    let r = Int(set.reps) ?? 0
                    guard w > 0, r > 0 else { continue }
                    if w > bestWeight {
                        bestWeight = w
                        bestReps = r
                    }
                }
                if bestWeight > 0 {
                    out[key] = PriorBest(weight: bestWeight, reps: bestReps,
                                         date: session.startTime)
                }
            }
        }
        return out
    }

    // MARK: - patternFrequency

    /// Count distinct sessions in the window hitting each movement pattern.
    /// Resolves exercise names through CoachDatabase once per unique name.
    private static func buildPatternFrequency(
        sessions: [SavedSession],
        cutoff: Date
    ) -> [String: Int] {
        let recent = sessions.filter { $0.startTime >= cutoff }
        guard !recent.isEmpty else { return [:] }
        let db = CoachDatabase.shared
        var resolved: [String: [String]] = [:]
        var out: [String: Int] = [:]
        for session in recent {
            var sessionPatterns: Set<String> = []
            for ex in session.exercises {
                let key = ex.name.lowercased()
                let patterns: [String]
                if let cached = resolved[key] {
                    patterns = cached
                } else {
                    let exact = db.listExercises(search: ex.name).first {
                        $0.name.caseInsensitiveCompare(ex.name) == .orderedSame
                    }
                    patterns = exact.map { db.patternsForExercise($0.id) } ?? []
                    resolved[key] = patterns
                }
                sessionPatterns.formUnion(patterns)
            }
            for p in sessionPatterns { out[p, default: 0] += 1 }
        }
        return out
    }

    // MARK: - recentSoreAreas

    /// Lower-cased body-area strings the user has tagged in pre-workout
    /// soreness check-ins OR post-workout hurt-area reports within the
    /// window. Lower-case so callers can intersect with muscle-group labels
    /// case-insensitively.
    private static func buildRecentSoreAreas(
        soreness: [SorenessEntry],
        feedback: [FeedbackEntry],
        cutoff: Date
    ) -> Set<String> {
        var out: Set<String> = []
        for entry in soreness where entry.date >= cutoff {
            for area in entry.areas { out.insert(area.lowercased()) }
        }
        for entry in feedback where entry.date >= cutoff {
            for area in entry.hurtAreas { out.insert(area.lowercased()) }
        }
        return out
    }

    // MARK: - stagnantExercises

    /// Walk completed sets newest-first, computing the best Epley 1RM per
    /// exercise per session. If the best 1RM hasn't improved by ≥5 lb in 4
    /// weeks (the strength-velocity noise floor), the exercise is stagnant.
    /// We only flag exercises with ≥3 sessions in window — flagging based
    /// on a single data point is noise.
    private static func buildStagnantExercises(
        sessions: [SavedSession],
        now: Date
    ) -> Set<String> {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: now) ?? now
        // For each exercise name → ordered list of (date, epley1RM).
        var perEx: [String: [(date: Date, epley: Double)]] = [:]
        for session in sessions where session.startTime >= cutoff {
            for ex in session.exercises {
                let key = ex.name.lowercased()
                var bestEpley = 0.0
                // Warmup sets excluded — stagnation detection compares working
                // 1RM-equivalents over time.
                for set in ex.sets where set.done && !set.isWarmup {
                    let w = Double(set.weight) ?? 0
                    let r = Int(set.reps) ?? 0
                    guard w > 0, r > 0 else { continue }
                    let e = StrengthStandards.epley1RM(weight: w, reps: r)
                    if e > bestEpley { bestEpley = e }
                }
                if bestEpley > 0 {
                    perEx[key, default: []].append((session.startTime, bestEpley))
                }
            }
        }
        var out: Set<String> = []
        for (name, points) in perEx where points.count >= 3 {
            let ordered = points.sorted { $0.date < $1.date }
            // Stagnant if max 1RM in window improved by < 5 lb from start to end.
            let first = ordered.first!.epley
            let max = ordered.map(\.epley).max() ?? first
            if max - first < 5.0 { out.insert(name) }
        }
        return out
    }

    // MARK: - muscleVolume

    /// Delegate to `MuscleVolume.rows`, which already handles the role-weighted
    /// allocation. We re-export as `[slug: volume]` for cheap lookup during
    /// slot pick.
    private static func buildMuscleVolume(
        sessions: [SavedSession],
        now: Date
    ) -> [String: Double] {
        let rows = MuscleVolume.rows(from: sessions, weeks: 4, limit: 50, now: now)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.slug, $0.volume) })
    }
}
