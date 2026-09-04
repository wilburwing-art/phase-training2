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

    /// Most recent completed attempt per exercise NAME (lowercased): what the
    /// user actually did LAST session at their working weight, against what
    /// was asked. `priorBest` answers "how strong are they"; this answers "did
    /// the last dose land". The progression step reads both (T2-9): it used
    /// to add 2.5% from the all-time best unconditionally, with no branch for
    /// missed reps, so a user grinding a stalled lift was told to add weight
    /// every week.
    var lastAttempt: [String: LastAttempt] = [:]

    /// Lowercased body areas the user has reported sore or painful in the
    /// last 7 days. Slot pick excludes exercises whose primary muscle group
    /// label overlaps with this set.
    var recentSoreAreas: Set<String>

    /// Lowercased exercise names whose best estimated 1RM hasn't improved
    /// in 4+ weeks (using the StrengthStandards.epley1RM math). When the
    /// generator would otherwise pick one of these for a primary slot, it
    /// prefers a substitute from `exercise_substitutions`.
    var stagnantExercises: Set<String>

    /// Per-exercise affinity score keyed by exercise name (mirrors
    /// `TrainingMemory.exerciseAffinities`). Positive = the user has asked for /
    /// swapped toward this exercise; negative = swapped away from / "recommend
    /// less". The slot picker weights candidates by this score so preferred
    /// exercises are picked more often and strongly-demoted ones sink. Empty =
    /// no preference, no effect.
    var exerciseAffinities: [String: Int] = [:]

    /// Distinct calendar days in the last 7 with a HARD sport log. Used by
    /// the planner's recent-signal bias to trim lift volume when the user
    /// is already carrying heavy non-lift load. Moderate / light sport days
    /// don't count — only intensities the user labeled as hard.
    var recentHardSportDays: Int

    /// Phase 2 readiness signal (0.0 = fully detrained → 0.5 = neutral / no
    /// data → 1.0 = high training state). Computed from native sessions +
    /// imported workouts + sport logs over a 28-day window. Drives volume,
    /// RPE cap, and recommended-days floor SILENTLY in the generator — does
    /// NOT affect movement competency (that's `ExperienceLevel`) or
    /// aesthetic (that's `DemographicProfile.eraStyle`).
    var readinessScore: Double = 0.5

    /// Per-axis breakdown of `readinessScore` — surfaced only in debug
    /// builds. Generator never reads this; included so the Settings →
    /// Health & Imports screen can render it diagnostically.
    var readinessBreakdown: ReadinessBreakdown = ReadinessSignal.neutral.breakdown

    /// True when readiness came from real data (the caller had at least one
    /// session/workout/sportLog in the window). When false, the generator
    /// SKIPS readiness-based scaling entirely — explicit anti-pattern: the
    /// neutral 0.5 sentinel must not be mistaken for "low real readiness".
    var hasReadinessData: Bool = false

    static let empty = GeneratorContext(
        priorBest: [:], recentSoreAreas: [],
        stagnantExercises: [],
        recentHardSportDays: 0,
        readinessScore: 0.5,
        readinessBreakdown: ReadinessSignal.neutral.breakdown,
        hasReadinessData: false
    )

    var isEmpty: Bool {
        priorBest.isEmpty &&
        recentSoreAreas.isEmpty && stagnantExercises.isEmpty &&
        recentHardSportDays == 0 &&
        !hasReadinessData
    }
}

/// One row in `priorBest` — the user's best logged top-set for an exercise.
struct PriorBest: Equatable {
    let weight: Double      // lb
    let reps: Int
    let date: Date
}

/// The last completed session's working sets for one exercise, reduced to
/// the one question progression needs: at the heaviest weight lifted, how
/// many reps landed against how many were asked.
struct LastAttempt: Equatable {
    let weight: Double      // lb, heaviest completed non-warmup set
    let reps: Int           // best reps at that weight
    let targetReps: Int     // what the session asked for
    let date: Date
}

/// Pure decision: step up, hold, or step down, from the best-ever set and the
/// most recent attempt. Free of DB and view state so it is testable as a
/// table. Conservative on purpose: it only HOLDS or STEPS DOWN when the last
/// attempt was at or above the best-ever weight and fell short, so a light
/// day, a travel day or a deload can never trigger a step-down from the
/// all-time best.
enum ProgressionDecision: Equatable {
    case stepUp, hold, stepDown

    static func decide(prior: PriorBest, last: LastAttempt?) -> ProgressionDecision {
        guard let last, last.targetReps > 0 else { return .stepUp }
        guard last.weight >= prior.weight - 0.01 else { return .stepUp }
        if last.reps >= last.targetReps { return .stepUp }
        if last.reps >= last.targetReps - 1 { return .hold }
        return .stepDown
    }

    /// Multiplier on the rep-mapped load before the 2.5-lb rounding.
    var loadMultiplier: Double {
        switch self {
        case .stepUp:   return 1.025
        case .hold:     return 1.0
        case .stepDown: return 0.95
        }
    }
}

// MARK: - Builder

extension GeneratorContext {

    /// Build a context from raw stores. Pass `SessionStore.savedSessions`,
    /// `memory.soreness`, `memory.feedback`. Honors a 4-week window for
    /// pattern + volume signals, 7 days for soreness, 4 weeks since last PR
    /// for stagnation. `now` is injectable for tests.
    ///
    /// Phase 2 additions:
    /// - `importedWorkouts` — HK + (Phase 3) CSV history, unioned with
    ///   native sessions for readiness density/recency/trend.
    /// - `cohort` — sets the density-component denominator. Default 3/wk
    ///   when nil. Per the three-axes skill, cohort here drives ONLY the
    ///   readiness norm; it does NOT touch competency.
    static func from(
        sessions: [SavedSession],
        soreness: [SorenessEntry],
        feedback: [FeedbackEntry],
        // Defaulted so the test/preview surfaces that already call .from
        // don't have to thread sport logs through. Production callers
        // (PlanStore.buildGeneratorContext) pass the real list.
        sportLogs: [SportLogEntry] = [],
        // Phase 2 — HK / CSV imports. Defaulted so existing test surfaces
        // and the LLM-refinement path (which builds its own context) don't
        // need to thread them. PlanStore.buildGeneratorContext does pass
        // the real list once HK auth is granted.
        importedWorkouts: [ImportedWorkout] = [],
        // Phase 3 — per-exercise heaviest set from imported_sets, in kg.
        // Used to warm-start priorBest for exercises the user has never
        // logged natively but DOES have imported history for. PlanStore
        // sources this from UserDatabase.importedSetsLifetimePeaks().
        // Each tuple resolves to a coach.db exercise the importer was
        // able to match by name — unmatched rows never reach here.
        importedPeaks: [(exerciseId: Int, weight: Double, reps: Int, performedAt: Date)] = [],
        // Phase 2 — cohort for the readiness density norm. nil → default
        // 3 sessions/wk. PlanStore resolves this from DemographicProfile.
        cohort: EraCohort? = nil,
        // Per-exercise affinity from TrainingMemory. Defaulted so the
        // test/preview + LLM-refinement surfaces that build their own context
        // don't have to thread it; PlanStore.buildGeneratorContext passes the
        // real map so swap-derived preferences reach the slot picker.
        exerciseAffinities: [String: Int] = [:],
        now: Date = Date(),
        /// Compute the PARKED adaptive signals (recentSoreAreas,
        /// stagnantExercises, exerciseAffinities)? Defaults OFF because nothing
        /// reads them and they're the expensive half of building a context.
        /// Tests pass `true` to keep exercising the builders, which stay
        /// correct and ready for the day the engine consumes them.
        includeParkedSignals: Bool = false
    ) -> GeneratorContext {
        let cal = Calendar.current
        let weekSoreCutoff = cal.date(byAdding: .day, value: -7, to: now) ?? now

        // Readiness inputs — union native sessions + imports + hard sport
        // days. All three count equally toward density/recency/trend (the
        // signal layer doesn't distinguish strength from cardio from sport;
        // the unionized "did the user move this week" is what matters).
        let readinessEvents = buildReadinessEvents(
            sessions: sessions,
            importedWorkouts: importedWorkouts,
            sportLogs: sportLogs,
            now: now
        )
        let signal = ReadinessSignal.compute(
            events: readinessEvents,
            cohort: cohort,
            now: now
        )
        let hasData = !readinessEvents.isEmpty

        // T2-11 — PARKED ADAPTIVE LAYER, do not delete.
        //
        // `recentSoreAreas`, `stagnantExercises` and `exerciseAffinities` have
        // NO reader: verified by grep for `context.<field>` / `ctx.<field>`
        // across the app — zero hits, against 9 for the live
        // readinessScore / priorBest / hasReadinessData. (Careful: grepping the
        // bare field name is misleading, because TrainingMemory has its OWN
        // `exerciseAffinities` that MemoryStore.recordSwap writes and
        // PlanStore+Generation passes IN here. The memory side is live; the
        // context side is what nothing reads.)
        //
        // They belong to the adaptive layer that is built but deliberately not
        // consumed by the season engine (see the repo's direction note), so the
        // fix is to stop PAYING for them on every regen, NOT to remove them —
        // buildStagnantExercises walks 4 weeks of sessions computing Epley 1RMs
        // per exercise, and buildRecentSoreAreas resolves names through
        // CoachDatabase. `computeParkedSignals` is the single switch to flip
        // when the engine starts consuming them.
        return GeneratorContext(
            priorBest: buildPriorBest(sessions: sessions, importedPeaks: importedPeaks),
            lastAttempt: buildLastAttempt(sessions: sessions),
            recentSoreAreas: includeParkedSignals
                ? buildRecentSoreAreas(soreness: soreness, feedback: feedback, cutoff: weekSoreCutoff)
                : [],
            stagnantExercises: includeParkedSignals
                ? buildStagnantExercises(sessions: sessions, now: now)
                : [],
            exerciseAffinities: includeParkedSignals ? exerciseAffinities : [:],
            recentHardSportDays: buildRecentHardSportDays(sportLogs: sportLogs,
                                                          cutoff: weekSoreCutoff,
                                                          calendar: cal),
            readinessScore: signal.score,
            readinessBreakdown: signal.breakdown,
            hasReadinessData: hasData
        )
    }

    // MARK: - readiness events (Phase 2)

    /// Union native sessions + imported workouts + sport logs within the
    /// 28-day readiness window. Each contributes ONE ReadinessEvent per
    /// distinct calendar day so the same date hit by both a native session
    /// AND an HK record (the user logged in-app AND HK detected it from
    /// the watch) doesn't double-count.
    private static func buildReadinessEvents(
        sessions: [SavedSession],
        importedWorkouts: [ImportedWorkout],
        sportLogs: [SportLogEntry],
        now: Date
    ) -> [ReadinessEvent] {
        let cutoff = now.addingTimeInterval(-28 * 86_400)
        let cal = Calendar.current

        // Native sessions: use startTime as-is.
        var byDay: [Date: ReadinessEvent] = [:]
        for s in sessions where s.startTime >= cutoff {
            let day = cal.startOfDay(for: s.startTime)
            // Prefer the earliest event on that day so trend math sees the
            // session start consistently — the within-day choice doesn't
            // matter for density/recency/trend which are at day granularity.
            if byDay[day] == nil || byDay[day]!.startTime > s.startTime {
                byDay[day] = ReadinessEvent(startTime: s.startTime)
            }
        }
        // Imported workouts.
        for w in importedWorkouts where w.startTime >= cutoff {
            let day = cal.startOfDay(for: w.startTime)
            if byDay[day] == nil || byDay[day]!.startTime > w.startTime {
                byDay[day] = ReadinessEvent(startTime: w.startTime)
            }
        }
        // Sport logs feed readiness as "you've been active" — EXCEPT hard
        // sport days. The planner's recent-signal bias already treats >=3 hard
        // sport days as fatigue (it trims a lift day), so counting them here
        // too would let one hard sport week BOTH cut a day AND inflate
        // readiness (keeping per-session volume high). Sport = fatigue: hard
        // days don't raise the readiness/training signal. Light/moderate sport
        // still counts as general activity.
        for log in sportLogs where log.date >= cutoff && log.intensity != .hard {
            let day = cal.startOfDay(for: log.date)
            if byDay[day] == nil || byDay[day]!.startTime > log.date {
                byDay[day] = ReadinessEvent(startTime: log.date)
            }
        }
        return Array(byDay.values)
    }

    // MARK: - recentHardSportDays

    /// Count distinct calendar days within the 7-day window that have at
    /// least one HARD sport log. We dedupe by start-of-day so the same
    /// long climbing session split into two entries (rare but possible)
    /// doesn't double-count.
    private static func buildRecentHardSportDays(
        sportLogs: [SportLogEntry],
        cutoff: Date,
        calendar: Calendar
    ) -> Int {
        let hardDays = Set(
            sportLogs
                .filter { $0.intensity == .hard && $0.date >= cutoff }
                .map { calendar.startOfDay(for: $0.date) }
        )
        return hardDays.count
    }

    // MARK: - priorBest

    /// Walk sessions newest-first; first completed set with weight + reps
    /// for an exercise name wins. We treat "top-set" as the heaviest
    /// completed set in the user's most recent session for that exercise,
    /// not the all-time max — the generator wants "what did you actually
    /// do last time?" not "your best ever".
    ///
    /// Phase 3 addition: after the native pass, fill gaps from `importedPeaks`
    /// (lifetime peak per exercise from CSV history). Imports never override
    /// a native entry — native session > imported peak. For exercises the
    /// user has imported but never logged natively, the peak warm-starts
    /// priorBest so the generator has a real baseline weight to work from.
    /// Imported weight arrives in kg (Fitbod schema literally calls the
    /// column `Weight(kg)`) and is converted to lb to match the native
    /// path's convention.
    /// Most recent session per exercise name; heaviest completed working set
    /// and the best reps at that weight, against the session's target reps.
    static func buildLastAttempt(sessions: [SavedSession]) -> [String: LastAttempt] {
        var out: [String: LastAttempt] = [:]
        for session in sessions.sorted(by: { $0.startTime > $1.startTime }) {
            for ex in session.exercises {
                let key = ex.name.lowercased()
                guard out[key] == nil else { continue }
                var bestW = 0.0, bestR = 0
                for set in ex.sets where set.done && !set.isWarmup {
                    let w = set.weightValue ?? 0, r = set.repsValue ?? 0
                    guard w > 0, r > 0 else { continue }
                    if w > bestW || (w == bestW && r > bestR) { bestW = w; bestR = r }
                }
                guard bestW > 0 else { continue }
                out[key] = LastAttempt(weight: bestW, reps: bestR,
                                       targetReps: ex.targetReps, date: session.startTime)
            }
        }
        return out
    }

    private static func buildPriorBest(
        sessions: [SavedSession],
        importedPeaks: [(exerciseId: Int, weight: Double, reps: Int, performedAt: Date)] = []
    ) -> [String: PriorBest] {
        let ordered = sessions.sorted { $0.startTime > $1.startTime }
        var out: [String: PriorBest] = [:]
        for session in ordered {
            for ex in session.exercises {
                let key = ex.name.lowercased()
                guard out[key] == nil else { continue } // most recent session wins
                // Heaviest completed set in this session.
                // Warmup sets excluded — progressive-overload signal needs the
                // working top set, not a warmup ramp weight.
                let isBodyweight = ex.isBodyweight
                var bestWeight = 0.0
                var bestReps = 0
                var bestBodyweightReps = 0   // best reps on a loadless bodyweight set
                for set in ex.sets where set.done && !set.isWarmup {
                    let w = set.weightValue ?? 0
                    let r = set.repsValue ?? 0
                    guard r > 0 else { continue }
                    if w > 0 {
                        if w > bestWeight { bestWeight = w; bestReps = r }
                    } else if isBodyweight {
                        // Only a true bodyweight movement (unit == "bw") reads a
                        // loadless set as a rep-progression signal. A 0 logged on
                        // a loaded lift is missing data, not a bodyweight PR — so
                        // it stays ignored, preserving the old skip-zero behavior.
                        bestBodyweightReps = max(bestBodyweightReps, r)
                    }
                }
                if bestWeight > 0 {
                    out[key] = PriorBest(weight: bestWeight, reps: bestReps,
                                         date: session.startTime)
                } else if bestBodyweightReps > 0 {
                    // Bodyweight movement (push-up, inverted row): no external
                    // load to progress, so track best reps — weight 0 signals the
                    // reps-based progression path in progressiveOverloadHint. (T2.1)
                    out[key] = PriorBest(weight: 0, reps: bestBodyweightReps,
                                         date: session.startTime)
                }
            }
        }

        // Phase 3: fill gaps from imported peaks. Resolve coach.db exercise
        // by id → name, key by lowercased name to match the native path.
        if !importedPeaks.isEmpty {
            let db = CoachDatabase.shared
            let kgToLb = 2.20462
            for peak in importedPeaks {
                guard let ex = db.exercise(id: peak.exerciseId) else { continue }
                let key = ex.name.lowercased()
                guard out[key] == nil else { continue }  // native always wins
                guard peak.weight > 0, peak.reps > 0 else { continue }
                out[key] = PriorBest(
                    weight: peak.weight * kgToLb,
                    reps: peak.reps,
                    date: peak.performedAt
                )
            }
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
            for area in entry.areas where MuscleBucket.sorenessPrimarySlugs.contains(area) {
                out.insert(area.lowercased())
            }
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
                    let w = set.weightValue ?? 0
                    let r = set.repsValue ?? 0
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

}
