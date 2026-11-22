// AuthoredRoutine.swift — Phase 2: serve curated authored coach.db routines.
//
// Direction: authored program spines, season engine as within-program assist.
// The season engine still decides each day's KIND + phase; when a curated
// authored routine exists for the (sport, phase), it fills the lift day's
// workout VERBATIM instead of the demand-scheme generator — with per-user
// weight recommendations layered onto the fixed authored sets/reps (never
// mutating them). Selection is deterministic and falls through to the season
// engine whenever no authored routine matches, so uncovered sports/phases are
// unchanged until they're curated (Phase 3).

import Foundation

enum AuthoredRoutineSelector {

    /// Kill-switch. Authored serving is on by default (the product direction);
    /// set this UserDefaults key to false to fall back to the season engine
    /// everywhere with no rebuild.
    static let enabledKey = "authored_routines_enabled"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Every coach.db `routines.phase` value — the "any phase" fallback pool so
    /// an authored-served sport with a phase gap still gets a session.
    static let allPhaseLabels = ["off_season", "base", "build", "peak", "race", "recovery", "maintenance"]

    /// The universal cross-sport base pool. `general-fitness` carries Easy
    /// Strength (Dan John / Pavel) — the last-resort content when a sport has
    /// no bespoke routine of its own for any phase.
    static let genericBaseSlug = "general-fitness"

    /// coach.db `routines.phase` labels that stand in for a SeasonPhase. A
    /// SeasonPhase can map to more than one label (off-season pulls both the
    /// sport's off_season block and generic base work).
    static func phaseLabels(for phase: SeasonPhase) -> [String] {
        switch phase {
        case .offSeason:   return ["off_season", "base"]
        case .preSeason:   return ["build"]
        case .inSeason:    return ["maintenance"]
        case .eventPrep:   return ["build", "maintenance"]
        case .maintenance: return ["maintenance", "base"]
        }
    }

    /// Sports the engine could build that are served written routines first:
    /// climbing and snowboarding. Skiing joins when it has routines for every
    /// season (it has two today, none in-season).
    static var pilotSports: Set<String> {
        Set(SportProfile.table.filter { $0.value.authoredOverEngine }.keys)
    }

    /// Which sports get authored serving:
    ///  - the pilot sports (climbing), where we prefer authored over the engine;
    ///  - any sport the season engine can't handle (MTB, cycling, running…),
    ///    where authored is strictly better than the engine's empty "Rest".
    /// A season-engine-supported sport that isn't piloted (ski/snowboard) keeps
    /// the engine.
    static func shouldServeAuthored(sportSlug: String) -> Bool {
        if SportProfile.of(sportSlug).authoredOverEngine { return true }
        return !SportSeasonGenerator.supports(sportSlug)
    }

    /// Minimum movements for a routine to be served as a day's workout. Mirrors
    /// the season engine's own floor (`targetMovementCount`'s `max(3, ...)`).
    /// The DB query applies it to the routine as authored; `viable` below
    /// applies it again AFTER the user's injury exclusions, because a 3-movement
    /// routine with one contraindicated lift is a 2-movement session.
    static let minimumMovements = 3

    /// Routines that still clear `minimumMovements` once this user's
    /// contraindicated exercises are removed. Filtering here rather than in
    /// `AuthoredRoutine.workout` keeps the fallback chain intact: a routine
    /// rejected for this user is skipped and the NEXT one is offered, where
    /// rejecting it at build time would drop an authored-only sport (MTB,
    /// hiking) through to the empty "no supported sport" workout.
    ///
    /// The same floor applies after the equipment pass (R2-05): a row the user
    /// cannot equip is swapped for a curated substitute they can, or dropped,
    /// and a routine that thins below the floor is skipped for the next one.
    private static func viable(_ ids: [Int], excluding excluded: Set<Int>,
                               allowed: Set<String>,
                               preferences: RoutinePreferences,
                               experience: ExperienceLevel?) -> [Int] {
        guard !excluded.isEmpty || !allowed.isEmpty || !preferences.isEmpty else { return ids }
        return ids.filter { id in
            AuthoredRoutine.resolvedRows(forRoutineId: id, excluded: excluded, allowed: allowed,
                                         preferences: preferences, experience: experience)
                .count >= minimumMovements
        }
    }

    /// `allowedEquipmentSlugs` follows the season engine's convention: empty
    /// means full gym / unrestricted.
    /// Routines at or below the athlete's level. A beginner is never handed the
    /// advanced campus block; an advanced athlete may take any routine.
    ///
    /// When every routine for the sport is above the athlete's level, an
    /// engine-supported sport returns an empty list so the caller falls through
    /// to the season engine (which gates movements by level itself). An
    /// authored-only sport keeps the unfiltered list, because an empty day is
    /// worse than a hard one there.
    private static func routines(_ ids: [Int], for experience: ExperienceLevel?,
                                 sportSlug: String) -> [Int] {
        guard !ids.isEmpty, let ceiling = difficultyCeiling(experience) else { return ids }
        let difficulty = CoachDatabase.shared.routineDifficulty(forIds: ids)
        let fit = ids.filter { fits(difficulty[$0], under: ceiling) }
        if !fit.isEmpty { return fit }
        return SportSeasonGenerator.supports(sportSlug) ? [] : ids
    }

    private static let difficultyRank: [String: Int] =
        ["beginner": 0, "intermediate": 1, "advanced": 2, "elite": 3]

    /// Highest coach.db difficulty rank this athlete is served, or nil for no
    /// ceiling (advanced, or experience unknown).
    static func difficultyCeiling(_ experience: ExperienceLevel?) -> Int? {
        switch experience {
        case .beginner: return 0
        case .intermediate: return 1
        case .advanced, nil: return nil
        }
    }

    /// A missing difficulty ranks as intermediate.
    static func fits(_ difficulty: String?, under ceiling: Int) -> Bool {
        (difficultyRank[difficulty ?? "intermediate"] ?? 1) <= ceiling
    }

    /// Routines this athlete may be served for (sport, phase), id ASC: the
    /// sport's mapped phases, then (an unsupported sport only) any phase, then
    /// (an outdoor authored sport only) the generic base. Empty means fall
    /// through to the season engine.
    static func candidates(sportSlug: String, phase: SeasonPhase,
                           experience: ExperienceLevel? = nil,
                           excludedExerciseIds: Set<Int> = [],
                           allowedEquipmentSlugs: Set<String> = [],
                           preferences: RoutinePreferences = .none) -> [Int] {
        guard isEnabled, shouldServeAuthored(sportSlug: sportSlug) else { return [] }
        let db = CoachDatabase.shared
        var ids = viable(routines(db.authoredRoutineIds(sportSlug: sportSlug,
                                                        phaseLabels: phaseLabels(for: phase)),
                                  for: experience, sportSlug: sportSlug),
                         excluding: excludedExerciseIds, allowed: allowedEquipmentSlugs,
                         preferences: preferences, experience: experience)
        if ids.isEmpty {
            // Phase gap. A season-engine-supported sport (climbing pilot) falls
            // THROUGH to the engine. An unsupported authored sport has no engine
            // backstop, so broaden to any full-session routine for the sport —
            // an authored-served sport must never yield an empty day.
            guard !SportSeasonGenerator.supports(sportSlug) else { return [] }
            ids = viable(routines(db.authoredRoutineIds(sportSlug: sportSlug, phaseLabels: allPhaseLabels),
                                  for: experience, sportSlug: sportSlug),
                         excluding: excludedExerciseIds, allowed: allowedEquipmentSlugs,
                         preferences: preferences, experience: experience)
            if ids.isEmpty, SportCatalog.outdoorAuthoredSlugs.contains(sportSlug) {
                // Last resort for a real outdoor sport with no content of its
                // own: the universal cross-sport base (Easy Strength). Gated on
                // the allowlist so an arbitrary/unknown slug still returns nil.
                //
                // The last resort used to skip the viability filter, on the
                // reasoning that serving what remained beat serving nothing.
                // That was written before there WAS an honest nothing. It
                // produced 315 of 1,800 days in the filter-composition grid as
                // one- and two-movement sessions still titled "Easy Strength —
                // 5-Lift Base", every one of them to a user who had declared
                // limited equipment: below the floor the app enforces
                // everywhere else, and lying about the program on top. Since
                // R2-05 the caller has a declared empty state that names the
                // reason and points at Profile, so the floor applies here too
                // and falling through is the better answer.
                ids = viable(db.authoredRoutineIds(sportSlug: genericBaseSlug, phaseLabels: allPhaseLabels),
                             excluding: excludedExerciseIds, allowed: allowedEquipmentSlugs,
                             preferences: preferences, experience: experience)
            }
        }
        return ids
    }

    /// How far, in minutes, a routine may sit from the budget beyond the
    /// closest routine's distance and still be picked.
    static let durationTolerance = 10

    /// The ids whose estimated minutes sit within `durationTolerance` of the
    /// closest one to `budget`, in their original order.
    static func fitting(_ ids: [Int], budget: Int, minutes: (Int) -> Int) -> [Int] {
        let gaps = ids.map { abs(minutes($0) - budget) }
        guard let best = gaps.min() else { return [] }
        return zip(ids, gaps).filter { $0.1 <= best + durationTolerance }.map(\.0)
    }

    /// Week-`planWeek` working minutes of a routine as this user is served it:
    /// the same rows, sets and reps (and defaults) `AuthoredRoutine.workout`
    /// serves, so the selector and the served session agree.
    static func estimatedMinutes(forRoutineId id: Int, excluded: Set<Int>, allowed: Set<String>,
                                 preferences: RoutinePreferences = .none,
                                 experience: ExperienceLevel? = nil,
                                 planWeek: Int? = nil) -> Int {
        AuthoredRoutine.resolvedRows(forRoutineId: id, excluded: excluded, allowed: allowed,
                                     preferences: preferences, experience: experience)
            .reduce(0) { total, rr in
                total + AuthoredRoutine.estimatedSeconds(sets: rr.row.sets(forWeek: planWeek) ?? 3,
                                                         reps: rr.row.reps(forWeek: planWeek) ?? "8-12")
            } / 60
    }

    /// Pick an authored routine id for this (sport, phase, session slot), or
    /// nil to fall through to the season engine. Deterministic: the same
    /// inputs always resolve to the same routine. With `sessionMinutes`, the
    /// pool narrows to the routines whose length sits closest to it
    /// (`fitting`); lift days in a phase rotate by `sessionIndex` over what is
    /// left, id ASC.
    static func select(sportSlug: String, phase: SeasonPhase, sessionIndex: Int,
                       experience: ExperienceLevel? = nil,
                       excludedExerciseIds: Set<Int> = [],
                       allowedEquipmentSlugs: Set<String> = [],
                       preferences: RoutinePreferences = .none,
                       sessionMinutes: Int? = nil,
                       planWeek: Int? = nil) -> Int? {
        var ids = candidates(sportSlug: sportSlug, phase: phase, experience: experience,
                             excludedExerciseIds: excludedExerciseIds,
                             allowedEquipmentSlugs: allowedEquipmentSlugs, preferences: preferences)
        guard !ids.isEmpty else { return nil }
        if let budget = sessionMinutes, ids.count > 1 {
            ids = fitting(ids, budget: budget) {
                estimatedMinutes(forRoutineId: $0, excluded: excludedExerciseIds,
                                 allowed: allowedEquipmentSlugs, preferences: preferences,
                                 experience: experience, planWeek: planWeek)
            }
        }
        // Non-negative modulo so a negative sessionIndex can't crash.
        return ids[((sessionIndex % ids.count) + ids.count) % ids.count]
    }
}

/// Which sports the app can build a coherent plan for as a PRIMARY sport — the
/// gate onboarding + the profile sports editor filter on. Season-engine sports
/// (ski / climbing) plus the outdoor sports we've distilled authored content
/// for. Kept here next to the authored-serving layer that makes the outdoor
/// sports plannable in the first place.
enum SportCatalog {
    /// Sports exposed as primary once they carry authored coverage: every
    /// `.general` profile, own row or inherited from a family root (backlog
    /// 11e). Ski + climbing come via the season engine; these come via
    /// distilled coach.db routines.
    static let outdoorAuthoredSlugs: Set<String> = SportProfile.generalSlugs

    /// True when the app can plan for `slug` as primary: season-engine supported
    /// OR an outdoor authored sport that actually has curated routines. The
    /// coverage check keeps a listed-but-empty sport from being offered.
    static func isPlannable(_ slug: String) -> Bool {
        if SportSeasonGenerator.supports(slug) { return true }
        guard outdoorAuthoredSlugs.contains(slug) else { return false }
        return !CoachDatabase.shared.authoredRoutineIds(
            sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).isEmpty
    }
}

/// What the user has said about specific exercises, as the authored-routine
/// path reads it: the same dislike substring test and sunk-affinity threshold
/// the season engine applies through `AthleteState`.
struct RoutinePreferences: Equatable {
    var dislikedNameKeywords: [String] = []
    var affinities: [String: Int] = [:]

    static let none = RoutinePreferences()

    var isEmpty: Bool {
        dislikedNameKeywords.isEmpty
            && !affinities.values.contains { $0 <= AthleteState.affinitySinkThreshold }
    }

    static func from(_ memory: TrainingMemory) -> RoutinePreferences {
        RoutinePreferences(
            dislikedNameKeywords: AthleteState.dislikedKeywords(memory.dislikes),
            affinities: AthleteState.lowercasedAffinities(memory.exerciseAffinities))
    }

    func rejects(_ name: String) -> Bool {
        let lower = name.lowercased()
        if (affinities[lower] ?? 0) <= AthleteState.affinitySinkThreshold { return true }
        return dislikedNameKeywords.contains { lower.contains($0) }
    }
}

enum AuthoredRoutine {

    /// Build a `GeneratedWorkout` from a coach.db routine, layering a per-user
    /// "target: X lb" weight rec onto each strength row from the user's prior
    /// best (via `WorkoutGenerator.progressiveOverloadHint`) WITHOUT changing
    /// the authored sets/reps.
    ///
    /// `profile` is REQUIRED, not defaulted, because it carries the injury
    /// filter. InjuriesEditorSheet promises "We'll filter out exercises that
    /// aren't safe for the injuries you pick"; the season engine honours that at
    /// `SportSeasonGenerator.filteredPool`, and this path served seven of the
    /// ten plannable sports (every outdoor authored sport, plus climbing via the
    /// pilot flag) with no filter at all. A defaulted empty set would let a new
    /// call site silently opt out of the safety property again.
    ///
    /// Returns nil when the routine has no exercises, or when the injury and
    /// equipment filters remove all of them — the caller falls through to its
    /// next option rather than serving a session the user was told would be
    /// filtered.
    ///
    /// One routine row after this user's injury and equipment filters.
    /// `swappedFrom` names the authored exercise when a curated substitute
    /// stands in for it; `missingEquipment` lists what the original needed.
    struct ResolvedRow {
        let row: RoutineExercise
        let exerciseId: Int
        let name: String
        let swappedFrom: String?
        let missingEquipment: [String]
    }

    /// Substitution contexts curated for a gear gap. Tried before the other
    /// contexts, which exist for intensity, recovery, age and time and only
    /// happen to be equipment-free.
    private static let equipmentContexts: Set<String> = ["equipment_swap", "home_friendly"]

    /// Apply the user's injury exclusions, then the equipment rule the season
    /// engine uses (`SportSeasonGenerator.filteredPool`): an exercise is usable
    /// when its required slugs are a subset of the allowed set, and an empty
    /// allowed set is full gym. A row the user cannot equip is replaced by the
    /// best curated substitute they can (equipment contexts first, then
    /// similarity, then id for determinism), never one already in the routine
    /// or one their injuries exclude; with no substitute the row is dropped.
    /// 103 of the 113 authored routines carry at least one barbell or dumbbell
    /// movement, so dropping alone would gut the library for a bodyweight
    /// user (R2-05). A substitute also stays at or below the athlete's
    /// difficulty ceiling, the same one the selector applies to whole
    /// routines, so a beginner's bodyweight swap is never a pistol squat.
    /// The selector's floor and `workout` both read this so the
    /// two never disagree about what a routine holds for this user.
    static func resolvedRows(forRoutineId routineId: Int,
                             excluded: Set<Int>, allowed: Set<String>,
                             preferences: RoutinePreferences = .none,
                             experience: ExperienceLevel? = nil) -> [ResolvedRow] {
        let db = CoachDatabase.shared
        let rows = db.exercises(forRoutineId: routineId)
            .filter { !excluded.contains($0.exerciseId) }
        func plain(_ r: RoutineExercise) -> ResolvedRow {
            ResolvedRow(row: r, exerciseId: r.exerciseId, name: r.name,
                        swappedFrom: nil, missingEquipment: [])
        }
        guard (!allowed.isEmpty || !preferences.isEmpty), !rows.isEmpty else { return rows.map(plain) }

        let reqs = allowed.isEmpty ? [:]
            : db.requiredEquipmentSlugs(forExerciseIds: Set(rows.map(\.exerciseId)))
        func usable(_ need: Set<String>) -> Bool {
            allowed.isEmpty || need.isEmpty || need.isSubset(of: allowed)
        }
        let ceiling = AuthoredRoutineSelector.difficultyCeiling(experience)
        func withinCeiling(_ difficulty: String?) -> Bool {
            ceiling.map { AuthoredRoutineSelector.fits(difficulty, under: $0) } ?? true
        }
        var taken = Set(rows.map(\.exerciseId))
        var names: [String: String] = [:]
        var out: [ResolvedRow] = []
        for r in rows {
            let need = reqs[r.exerciseId] ?? []
            // A disliked or sunk exercise goes the same way as one the user
            // cannot equip: a curated substitute, else the row is dropped.
            if usable(need) && !preferences.rejects(r.name) { out.append(plain(r)); continue }
            let subs = db.substitutes(forExerciseId: r.exerciseId)
            let subReqs = allowed.isEmpty ? [:]
                : db.requiredEquipmentSlugs(forExerciseIds: Set(subs.map(\.id)))
            let pick = subs
                .filter { !excluded.contains($0.id) && !taken.contains($0.id)
                          && usable(subReqs[$0.id] ?? [])
                          && !preferences.rejects($0.exercise.name)
                          && withinCeiling($0.exercise.difficulty) }
                .min { a, b in
                    let ra = a.contexts.contains(where: equipmentContexts.contains) ? 0 : 1
                    let rb = b.contexts.contains(where: equipmentContexts.contains) ? 0 : 1
                    return (ra, -a.score, a.id) < (rb, -b.score, b.id)
                }
            guard let pick else { continue }
            taken.insert(pick.id)
            let missing = need.subtracting(allowed).sorted()
            if names.isEmpty, !missing.isEmpty { names = db.equipmentNameBySlug() }
            out.append(ResolvedRow(
                row: r, exerciseId: pick.id, name: pick.exercise.name, swappedFrom: r.name,
                missingEquipment: allowed.isEmpty ? [] : missing.map { names[$0] ?? $0 }))
        }
        return out
    }

    static func resolvedRows(forRoutineId routineId: Int, profile: DemographicProfile,
                             preferences: RoutinePreferences = .none,
                             experience: ExperienceLevel? = nil) -> [ResolvedRow] {
        resolvedRows(forRoutineId: routineId, excluded: profile.excludedExerciseIds,
                     allowed: profile.allowedEquipmentSlugs, preferences: preferences,
                     experience: experience)
    }

    static func workout(
        forRoutineId routineId: Int,
        memory: TrainingMemory,
        context: GeneratorContext,
        focus: WorkoutFocus,
        profile: DemographicProfile,
        blockedBuckets: Set<String> = [],
        timeBudget: Int? = nil,
        planWeek: Int? = nil
    ) -> GeneratedWorkout? {
        let db = CoachDatabase.shared
        let all = resolvedRows(forRoutineId: routineId, profile: profile,
                               preferences: RoutinePreferences.from(memory),
                               experience: memory.experience)
        guard !all.isEmpty else { return nil }
        // Rule one: drop rows whose prime mover is still recovering. Under
        // three rows left is not the authored session any more, so the caller
        // builds something else.
        let skipped = blockedBuckets.isEmpty ? Set<String>() : all.reduce(into: Set<String>()) {
            $0.formUnion(WorkoutGenerator.primaryMuscleBuckets(exerciseId: $1.exerciseId))
        }.intersection(blockedBuckets)
        let rows = skipped.isEmpty ? all : all.filter {
            WorkoutGenerator.primaryMuscleBuckets(exerciseId: $0.exerciseId).isDisjoint(with: blockedBuckets)
        }
        guard !rows.isEmpty, skipped.isEmpty || rows.count >= 3 else { return nil }

        var exercises: [GeneratedExercise] = rows.map { rr in
            let re = rr.row
            // A row that writes its progression by week serves that week's
            // reps and sets.
            let reps = re.reps(forWeek: planWeek) ?? "8-12"
            // A swapped row says so, and what the original needed, so the user
            // can see why the session differs from the authored program.
            let swap = rr.swappedFrom.map { from -> String in
                let gear = rr.missingEquipment.joined(separator: ", ")
                return gear.isEmpty ? "Swapped in for \(from)" : "Swapped in for \(from) (no \(gear))"
            }
            var note = [swap, re.notes].compactMap { $0 }.filter { !$0.isEmpty }
                .joined(separator: " · ")
            // Weight rec: append a load target from prior best. Only fires for
            // movements the user has a logged/imported best for and a numeric
            // rep band — bodyweight / AMRAP rows keep just the authored note.
            if let ex = db.exercise(id: rr.exerciseId),
               let hint = WorkoutGenerator.progressiveOverloadHint(
                   for: ex, context: context, memory: memory, prescribedReps: reps) {
                note = [note, hint].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return GeneratedExercise(
                id: "authored-\(routineId)-\(re.position)",
                exerciseId: rr.exerciseId,
                name: rr.name,
                pattern: nil,
                isCompound: false,
                sets: re.sets(forWeek: planWeek) ?? 3,
                reps: reps,
                restSeconds: parseRest(re.rest) ?? 90,
                notes: note.isEmpty ? nil : note,
                rpe: nil,
                tempo: nil,
                source: .recipe,
                supersetGroup: re.supersetGroup
            )
        }

        let estimate = { (list: [GeneratedExercise]) in list.reduce(0) { $0 + estimatedSeconds($1) } / 60 }
        // A same-day time chip: the authored order puts the main work first,
        // so trailing rows give way until the session fits, never below the
        // movement floor. A superset leaves as a whole group, so trimming never
        // serves half of one.
        if let budget = timeBudget {
            exercises = trimmed(exercises, toMinutes: budget, estimate: estimate)
        }
        let estMin = max(15, estimate(exercises))
        let meta = db.authoredRoutineMeta(id: routineId)
        let provenance = meta?.source.map { "Authored · \($0)" } ?? "Authored program"
        var summary = "\(exercises.count) movements · ~\(estMin) min"
        let skippedOrdered = MuscleBucket.allCases.map(\.rawValue).filter(skipped.contains)
        if !skippedOrdered.isEmpty {
            let names = skippedOrdered.compactMap { MuscleBucket(rawValue: $0)?.label.lowercased() }
            summary += " · no \(ListFormatter.localizedString(byJoining: names)) work, still recovering"
        }
        var workout = GeneratedWorkout(
            title: meta?.name ?? "Session",
            summary: summary,
            exercises: exercises,
            estimatedMinutes: estMin,
            provenance: provenance,
            refinedByLLMAt: nil,
            focus: focus,
            authoredRoutineId: routineId
        )
        if !blockedBuckets.isEmpty {
            workout.blockedAreas = MuscleBucket.allCases.map(\.rawValue).filter(blockedBuckets.contains)
        }
        workout.skippedAreas = skippedOrdered.isEmpty ? nil : skippedOrdered
        return workout
    }

    /// Seconds a row takes for the time estimate. R3-12: a row whose reps lead
    /// with minutes ("20 min", "10 min EMOM") is its own minutes; anything else
    /// counts 90 s per set. Anchored at the start so "30-40% of your 2-minute
    /// max" counts as sets x 90 s.
    static func estimatedSeconds(_ ex: GeneratedExercise) -> Int {
        estimatedSeconds(sets: ex.sets, reps: ex.reps)
    }

    static func estimatedSeconds(sets: Int, reps: String) -> Int {
        let pattern = #"^\s*(\d+)(?:\s*-\s*(\d+))?\s*min"#
        if let m = reps.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let nums = reps[m].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let top = nums.last { return sets * top * 60 }
        }
        return sets * 90
    }

    /// Drop trailing units until `estimate` fits `budget` minutes. A unit is a
    /// run of rows sharing a superset group, or one ungrouped row. A unit that
    /// would take the session under the movement floor stays, so the result can
    /// run over the budget.
    static func trimmed(_ exercises: [GeneratedExercise], toMinutes budget: Int,
                        estimate: ([GeneratedExercise]) -> Int) -> [GeneratedExercise] {
        var out = exercises
        while estimate(out) > budget, let last = out.last {
            var cut = out.count - 1
            if let group = last.supersetGroup {
                while cut > 0, out[cut - 1].supersetGroup == group { cut -= 1 }
            }
            guard cut >= AuthoredRoutineSelector.minimumMovements else { break }
            out.removeSubrange(cut...)
        }
        return out
    }

    /// Parse an authored rest string to seconds: "90 sec", "2 min", "2:00",
    /// a range at its top ("2-3 min" is 180), and 0 for rows the program says
    /// carry no timed rest ("none", "built-in", "full recovery"). Log starts
    /// no rest timer at 0. Nil when the row has no rest or none can be read.
    static func parseRest(_ s: String?) -> Int? {
        guard let s else { return nil }
        let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
        if ["none", "built-in", "full recovery"].contains(lower) { return 0 }
        if lower.contains(":") {
            let parts = lower.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        let number = #"\d+(?:\.\d+)?"#
        guard let m = lower.range(of: "^\(number)(?:\\s*[-\u{2013}]\\s*\(number))?",
                                  options: .regularExpression) else { return nil }
        guard let top = lower[m].split(whereSeparator: { $0 == "-" || $0 == "\u{2013}" || $0 == " " })
            .last.flatMap({ Double($0) }) else { return nil }
        if lower.contains("min") { return Int(top * 60) }
        return Int(top)
    }
}
