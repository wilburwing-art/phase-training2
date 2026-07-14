// SupportScheduler.swift — de-confliction, not generation
// (PLAN-primary-support.md).
//
// A pure post-pass that places an already-generated primary week around the
// athlete's declared support-sport pattern. It deliberately consumes
// `[GeneratedWorkout]` — NOT the generator — so the same layer schedules
// authored spines (shralpinism import) later without change.
//
// Rules, in priority order:
//   1. Session days and support days are disjoint (never stack) unless the
//      week has no free day left; a forced stack is downgraded, not skipped.
//   2. The heaviest primary session never lands inside a support day's
//      `restDaysBefore` buffer (48h before a big alpine day, etc.) when any
//      legal day exists; otherwise it is downgraded with an explanation.
//   3. Heavier sessions are placed first, onto the days furthest (by the
//      directional interference penalty) from big support days.
//   4. Support days consume the weekly fatigue budget: each full
//      session-equivalent of summed `loadFraction` lightens the plan by one
//      exercise (highest-load exercise of the heaviest session, floor 3).
//   5. Deterministic: same inputs → same week. Ties break on fixed ordering,
//      mirroring the generator's fixed-seed discipline.
//
// Session "load" is derived from the workout's own content (sets × parsed
// RPE) because `fatigueCost` is intentionally never persisted onto
// `GeneratedExercise` — and authored spines won't have it either.

import Foundation

// MARK: - Output types

/// One primary session pinned to a weekday, with human-readable adjustment
/// notes ("why did my session move / shrink" — surfaced by the week UI).
struct ScheduledSession: Hashable {
    let weekday: Weekday
    let workout: GeneratedWorkout
    let adjustments: [String]
}

/// The de-conflicted week: every input session placed (never dropped), plus
/// the support days echoed back for rendering.
struct ScheduledWeek: Hashable {
    let sessions: [ScheduledSession]   // sorted by weekday
    let supportDays: [SupportDay]
    let notes: [String]                // week-level explanations (budget lighten)
}

// MARK: - Scheduler

enum SupportScheduler {

    /// Place `week` around `pattern`. A nil/empty pattern spreads sessions
    /// evenly (max spacing) with no adjustments.
    static func schedule(week: [GeneratedWorkout],
                         pattern: SupportPattern?,
                         primaryVariant: SportVariant) -> ScheduledWeek {
        guard !week.isEmpty else {
            return ScheduledWeek(sessions: [], supportDays: pattern?.days ?? [], notes: [])
        }
        guard let pattern, !pattern.isEmpty else {
            let spread = evenSpread(count: week.count)
            let sessions = zip(spread, week).map {
                ScheduledSession(weekday: $0, workout: $1, adjustments: [])
            }
            return ScheduledWeek(sessions: sessions, supportDays: [], notes: [])
        }

        // Budget lighten first (rule 4) so placement scores the week we keep.
        var (workouts, notes) = applyWeeklyBudget(week, pattern: pattern,
                                                  primaryVariant: primaryVariant)
        var adjustments: [[String]] = Array(repeating: [], count: workouts.count)

        // Place heaviest-first onto min-penalty free days (rules 1-3).
        let supportSet = Set(pattern.days.map(\.weekday))
        var free = Weekday.allCases.filter { !supportSet.contains($0) }
        let order = workouts.indices.sorted {
            let (a, b) = (sessionLoad(workouts[$0]), sessionLoad(workouts[$1]))
            return a != b ? a > b : $0 < $1                    // heaviest first, index tiebreak
        }
        let heaviestIdx = order.first!

        var placed: [Int: Weekday] = [:]                       // session index → day
        for idx in order {
            let isHeaviest = (idx == heaviestIdx)
            let candidates = free.isEmpty
                ? pattern.days.sorted { $0.magnitude != $1.magnitude
                        ? $0.magnitude < $1.magnitude : $0.weekday < $1.weekday }
                    .map(\.weekday)                            // forced stack: lightest support day
                : free
            let legal = isHeaviest
                ? candidates.filter { !violatesBuffer($0, pattern: pattern, primaryVariant: primaryVariant) }
                : candidates
            let pool = legal.isEmpty ? candidates : legal      // collision week: best available
            let day = pool.min {
                let (pa, pb) = (penalty($0, pattern: pattern, primaryVariant: primaryVariant, placed: placed),
                                penalty($1, pattern: pattern, primaryVariant: primaryVariant, placed: placed))
                return pa != pb ? pa < pb : $0 < $1            // deterministic tiebreak
            }!
            placed[idx] = day
            free.removeAll { $0 == day }

            if free.isEmpty && supportSet.contains(day) {
                let (w, note) = lighten(workouts[idx],
                    reason: "shares \(day.short) with a support day — no free day left")
                workouts[idx] = w
                adjustments[idx].append(note)
            }
            if isHeaviest && legal.isEmpty {
                let (w, note) = lighten(workouts[idx],
                    reason: "every day collides with a support-day recovery buffer")
                workouts[idx] = w
                adjustments[idx].append(note)
            }
        }

        let sessions = workouts.indices
            .map { ScheduledSession(weekday: placed[$0]!, workout: workouts[$0],
                                    adjustments: adjustments[$0]) }
            .sorted { $0.weekday != $1.weekday ? $0.weekday < $1.weekday
                                               : $0.workout.title < $1.workout.title }
        return ScheduledWeek(sessions: sessions, supportDays: pattern.days, notes: notes)
    }

    /// In-place de-confliction for the APP PIPELINE, where the Planner has
    /// ALREADY placed lift days on fixed weekdays (respecting overrides /
    /// events / protected days) — so we must NOT relocate, only lighten.
    ///
    /// Applies the same two rules as `schedule()` minus placement:
    ///   - weekly budget: floor(Σ loadFraction) exercises dropped from the
    ///     heaviest day(s);
    ///   - buffer: any lift day sitting inside a support day's restDaysBefore
    ///     window is lightened once (can't move it → downgrade, floor 3).
    /// Returns the (possibly-lightened) sessions with per-day adjustment notes,
    /// in the input order. `lifts` weekdays are authoritative and preserved.
    static func deconflictInPlace(lifts: [(weekday: Weekday, workout: GeneratedWorkout)],
                                  pattern: SupportPattern?,
                                  primaryVariant: SportVariant) -> [ScheduledSession] {
        var workouts = lifts.map(\.workout)
        let weekdays = lifts.map(\.weekday)
        var adjustments: [[String]] = Array(repeating: [], count: lifts.count)
        guard let pattern, !pattern.isEmpty, !lifts.isEmpty else {
            return zip(weekdays, workouts).map { ScheduledSession(weekday: $0, workout: $1, adjustments: []) }
        }

        // Rule 4 — weekly budget: drop floor(Σ loadFraction) from the heaviest.
        let equivalents = pattern.days.reduce(0.0) {
            $0 + SupportInterference.resolve(primary: primaryVariant,
                                             support: pattern.variant,
                                             magnitude: $1.magnitude).loadFraction
        }
        var drops = min(Int(equivalents), workouts.count)
        while drops > 0 {
            drops -= 1
            guard let idx = workouts.indices
                .filter({ workouts[$0].exercises.count > 3 })
                .max(by: { sessionLoad(workouts[$0]) < sessionLoad(workouts[$1]) })
            else { break }
            let (w, note) = lighten(workouts[idx],
                reason: "combined weekly load — \(pattern.sportSlug) is carrying \(String(format: "%.1f", equivalents)) session-equivalents")
            workouts[idx] = w
            adjustments[idx].append(note)
        }

        // Rule 2 — buffer: a fixed lift day inside a support buffer downgrades.
        for i in lifts.indices where violatesBuffer(weekdays[i], pattern: pattern, primaryVariant: primaryVariant) {
            guard workouts[i].exercises.count > 3 else { continue }
            let (w, note) = lighten(workouts[i],
                reason: "sits within a \(pattern.sportSlug) recovery buffer")
            workouts[i] = w
            adjustments[i].append(note)
        }

        return weekdays.indices.map {
            ScheduledSession(weekday: weekdays[$0], workout: workouts[$0], adjustments: adjustments[$0])
        }
    }

    // MARK: - Load scoring (content-derived; works for authored spines too)

    /// Σ sets × RPE-midpoint per exercise. RPE parses "6-7"/"8"; nil → 7
    /// (moderate default) so un-RPE'd spines still rank sensibly.
    static func sessionLoad(_ w: GeneratedWorkout) -> Double {
        w.exercises.reduce(0) { $0 + exerciseLoad($1) }
    }

    static func exerciseLoad(_ e: GeneratedExercise) -> Double {
        Double(e.sets) * rpeMidpoint(e.rpe)
    }

    private static func rpeMidpoint(_ rpe: String?) -> Double {
        guard let rpe else { return 7 }
        let parts = rpe.split(separator: "-").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty else { return 7 }
        return parts.reduce(0, +) / Double(parts.count)
    }

    // MARK: - Placement scoring

    /// Directional interference: a session BEFORE a support day costs twice a
    /// session after it (pre-fatiguing the sport day is the sin the model
    /// exists to prevent). Weighted by the support day's loadFraction, plus a
    /// spacing nudge away from already-placed primary sessions.
    private static func penalty(_ day: Weekday, pattern: SupportPattern,
                                primaryVariant: SportVariant,
                                placed: [Int: Weekday]) -> Double {
        var p = 0.0
        for sd in pattern.days {
            let inter = SupportInterference.resolve(primary: primaryVariant,
                                                    support: pattern.variant,
                                                    magnitude: sd.magnitude)
            let before = day.daysUntil(sd.weekday)             // session → support (session is before)
            let after = sd.weekday.daysUntil(day)              // support → session (session is after)
            if before > 0 { p += inter.loadFraction * 2.0 / Double(before) }
            if after > 0 { p += inter.loadFraction * 1.0 / Double(after) }
            if before == 0 { p += inter.loadFraction * 4.0 }   // same day (stack fallback only)
        }
        for (_, d) in placed {
            let gap = min(day.daysUntil(d), d.daysUntil(day))
            if gap == 0 { p += 100 }                           // occupied (shouldn't arise)
            else if gap == 1 { p += 0.75 }                     // avoid back-to-back lifting
        }
        return p
    }

    /// Rule 2: is `day` inside any support day's `restDaysBefore` window?
    /// (day is 1...restDaysBefore days before the support day, circular week.)
    static func violatesBuffer(_ day: Weekday, pattern: SupportPattern,
                               primaryVariant: SportVariant) -> Bool {
        pattern.days.contains { sd in
            let rest = SupportInterference.resolve(primary: primaryVariant,
                                                   support: pattern.variant,
                                                   magnitude: sd.magnitude).restDaysBefore
            let before = day.daysUntil(sd.weekday)
            return before >= 1 && before <= rest
        }
    }

    // MARK: - Weekly budget (rule 4)

    /// Each full session-equivalent of summed support `loadFraction` drops one
    /// exercise (the highest-load one, from the currently-heaviest session,
    /// floor 3 exercises) — mirroring the generator's lighten(): downgrade,
    /// never skip.
    private static func applyWeeklyBudget(_ week: [GeneratedWorkout],
                                          pattern: SupportPattern,
                                          primaryVariant: SportVariant)
        -> (workouts: [GeneratedWorkout], notes: [String]) {
        let equivalents = pattern.days.reduce(0.0) {
            $0 + SupportInterference.resolve(primary: primaryVariant,
                                             support: pattern.variant,
                                             magnitude: $1.magnitude).loadFraction
        }
        var workouts = week
        var notes: [String] = []
        var drops = Int(equivalents)                           // floor
        guard drops > 0 else { return (workouts, notes) }
        drops = min(drops, workouts.count)                     // never over-lighten
        for _ in 0..<drops {
            guard let idx = workouts.indices
                .filter({ workouts[$0].exercises.count > 3 })
                .max(by: { sessionLoad(workouts[$0]) < sessionLoad(workouts[$1]) })
            else { break }                                     // every session at floor
            let (w, note) = lighten(workouts[idx],
                reason: "combined weekly load — support sport is carrying \(String(format: "%.1f", equivalents)) session-equivalents")
            workouts[idx] = w
            notes.append("\(w.title): \(note)")
        }
        return (workouts, notes)
    }

    /// Drop the single highest-load exercise, floor 3 (the generator's
    /// lighten(), re-expressed over persisted content).
    private static func lighten(_ w: GeneratedWorkout, reason: String)
        -> (GeneratedWorkout, String) {
        guard w.exercises.count > 3,
              let drop = w.exercises.indices
                .max(by: { exerciseLoad(w.exercises[$0]) < exerciseLoad(w.exercises[$1]) })
        else { return (w, "kept as-is (already at 3-exercise floor): \(reason)") }
        var out = w
        let dropped = out.exercises.remove(at: drop)
        // Same per-exercise minutes formula the generator's assemble() uses.
        out.estimatedMinutes = out.exercises.reduce(0) {
            $0 + Int(ceil(Double($1.sets) * (Double($1.restSeconds) + 40) / 60))
        }
        out.summary = "\(out.exercises.count) movements · ~\(out.estimatedMinutes) min"
        return (out, "dropped \(dropped.name) — \(reason)")
    }

    // MARK: - No-pattern spread

    /// Max-spacing default: round(i × 7 / n), Monday-anchored (n=3 → Mon/Wed/Fri).
    /// Weekday is 1-based (monday = 1).
    static func evenSpread(count: Int) -> [Weekday] {
        (0..<count).map { Weekday(rawValue: 1 + ($0 * 7) / count)! }
    }
}
