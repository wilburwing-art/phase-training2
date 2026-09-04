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

    /// Climbing is the deliberate pilot: we prefer authored content over the
    /// season engine even though the engine supports climbing. Ski/snowboard
    /// (also engine-supported) are intentionally NOT here — the flagship season
    /// experience stays unchanged until authored ski content is curated.
    static var pilotSports: Set<String> { PhaseRule.climbingSlugs }

    /// Which sports get authored serving:
    ///  - the pilot sports (climbing), where we prefer authored over the engine;
    ///  - any sport the season engine can't handle (MTB, cycling, running…),
    ///    where authored is strictly better than the engine's empty "Rest".
    /// A season-engine-supported sport that isn't piloted (ski/snowboard) keeps
    /// the engine.
    static func shouldServeAuthored(sportSlug: String) -> Bool {
        if pilotSports.contains(sportSlug) { return true }
        return !SportSeasonGenerator.supports(sportSlug)
    }

    /// Pick an authored routine id for this (sport, phase, session slot), or
    /// nil to fall through to the season engine. Deterministic: the same
    /// (sport, phase, sessionIndex) always resolves to the same routine, and
    /// multiple lift days in a phase rotate through the available routines.
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
                               allowed: Set<String>) -> [Int] {
        guard !excluded.isEmpty || !allowed.isEmpty else { return ids }
        return ids.filter { id in
            AuthoredRoutine.resolvedRows(forRoutineId: id, excluded: excluded, allowed: allowed)
                .count >= minimumMovements
        }
    }

    /// `allowedEquipmentSlugs` follows the season engine's convention: empty
    /// means full gym / unrestricted.
    static func select(sportSlug: String, phase: SeasonPhase, sessionIndex: Int,
                       excludedExerciseIds: Set<Int> = [],
                       allowedEquipmentSlugs: Set<String> = []) -> Int? {
        guard isEnabled, shouldServeAuthored(sportSlug: sportSlug) else { return nil }
        let db = CoachDatabase.shared
        var ids = viable(db.authoredRoutineIds(sportSlug: sportSlug,
                                               phaseLabels: phaseLabels(for: phase)),
                         excluding: excludedExerciseIds, allowed: allowedEquipmentSlugs)
        if ids.isEmpty {
            // Phase gap. A season-engine-supported sport (climbing pilot) falls
            // THROUGH to the engine. An unsupported authored sport has no engine
            // backstop, so broaden to any full-session routine for the sport —
            // an authored-served sport must never yield an empty day.
            guard !SportSeasonGenerator.supports(sportSlug) else { return nil }
            ids = viable(db.authoredRoutineIds(sportSlug: sportSlug, phaseLabels: allPhaseLabels),
                         excluding: excludedExerciseIds, allowed: allowedEquipmentSlugs)
            if ids.isEmpty, SportCatalog.outdoorAuthoredSlugs.contains(sportSlug) {
                // Last resort for a real outdoor sport with no content of its
                // own: the universal cross-sport base (Easy Strength). Gated on
                // the allowlist so an arbitrary/unknown slug still returns nil.
                // Last resort is NOT injury- or equipment-filtered on
                // viability: if Easy Strength is all that is left, serve what
                // remains of it rather than nothing. `AuthoredRoutine.workout`
                // still removes the contraindicated rows and swaps or drops
                // the ones the user cannot equip.
                ids = db.authoredRoutineIds(sportSlug: genericBaseSlug, phaseLabels: allPhaseLabels)
            }
        }
        guard !ids.isEmpty else { return nil }
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
    /// Outdoor / mountain-athlete sports exposed as primary once they carry
    /// authored coverage. Ski + climbing come via the season engine; these come
    /// via authored coach.db routines (Phase 3 distillation). Grow this as more
    /// outdoor content is distilled.
    static let outdoorAuthoredSlugs: Set<String> = [
        "snowboarding", "mountain-biking", "mountaineering",
        "trail-running", "hiking-trekking", "thru-hiking",
    ]

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
    /// user (R2-05). The selector's floor and `workout` both read this so the
    /// two never disagree about what a routine holds for this user.
    static func resolvedRows(forRoutineId routineId: Int,
                             excluded: Set<Int>, allowed: Set<String>) -> [ResolvedRow] {
        let db = CoachDatabase.shared
        let rows = db.exercises(forRoutineId: routineId)
            .filter { !excluded.contains($0.exerciseId) }
        func plain(_ r: RoutineExercise) -> ResolvedRow {
            ResolvedRow(row: r, exerciseId: r.exerciseId, name: r.name,
                        swappedFrom: nil, missingEquipment: [])
        }
        guard !allowed.isEmpty, !rows.isEmpty else { return rows.map(plain) }

        let reqs = db.requiredEquipmentSlugs(forExerciseIds: Set(rows.map(\.exerciseId)))
        func usable(_ need: Set<String>) -> Bool { need.isEmpty || need.isSubset(of: allowed) }
        var taken = Set(rows.map(\.exerciseId))
        var names: [String: String] = [:]
        var out: [ResolvedRow] = []
        for r in rows {
            let need = reqs[r.exerciseId] ?? []
            if usable(need) { out.append(plain(r)); continue }
            let subs = db.substitutes(forExerciseId: r.exerciseId)
            let subReqs = db.requiredEquipmentSlugs(forExerciseIds: Set(subs.map(\.id)))
            let pick = subs
                .filter { !excluded.contains($0.id) && !taken.contains($0.id)
                          && usable(subReqs[$0.id] ?? []) }
                .min { a, b in
                    let ra = a.contexts.contains(where: equipmentContexts.contains) ? 0 : 1
                    let rb = b.contexts.contains(where: equipmentContexts.contains) ? 0 : 1
                    return (ra, -a.score, a.id) < (rb, -b.score, b.id)
                }
            guard let pick else { continue }
            taken.insert(pick.id)
            if names.isEmpty { names = db.equipmentNameBySlug() }
            out.append(ResolvedRow(
                row: r, exerciseId: pick.id, name: pick.exercise.name, swappedFrom: r.name,
                missingEquipment: need.subtracting(allowed).sorted().map { names[$0] ?? $0 }))
        }
        return out
    }

    static func resolvedRows(forRoutineId routineId: Int, profile: DemographicProfile) -> [ResolvedRow] {
        resolvedRows(forRoutineId: routineId, excluded: profile.excludedExerciseIds,
                     allowed: profile.allowedEquipmentSlugs)
    }

    static func workout(
        forRoutineId routineId: Int,
        memory: TrainingMemory,
        context: GeneratorContext,
        focus: WorkoutFocus,
        profile: DemographicProfile
    ) -> GeneratedWorkout? {
        let db = CoachDatabase.shared
        let rows = resolvedRows(forRoutineId: routineId, profile: profile)
        guard !rows.isEmpty else { return nil }

        let exercises: [GeneratedExercise] = rows.map { rr in
            let re = rr.row
            let reps = re.reps ?? "8-12"
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
                sets: re.sets ?? 3,
                reps: reps,
                restSeconds: parseRest(re.rest) ?? 90,
                notes: note.isEmpty ? nil : note,
                rpe: nil,
                tempo: nil,
                source: .recipe,
                supersetGroup: re.supersetGroup
            )
        }

        let estMin = max(15, exercises.reduce(0) { $0 + $1.sets * 90 } / 60)
        let meta = db.authoredRoutineMeta(id: routineId)
        let provenance = meta?.source.map { "Authored · \($0)" } ?? "Authored program"
        return GeneratedWorkout(
            title: meta?.name ?? "Session",
            summary: "\(exercises.count) movements · ~\(estMin) min",
            exercises: exercises,
            estimatedMinutes: estMin,
            provenance: provenance,
            refinedByLLMAt: nil,
            focus: focus
        )
    }

    /// Parse a free-form rest string ("90s", "1 min", "2:00") to seconds.
    /// Mirrors PlanStore.parseRest so authored + custom routines resolve rest
    /// identically.
    static func parseRest(_ s: String?) -> Int? {
        guard let s else { return nil }
        let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.contains(":") {
            let parts = lower.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        let digits = lower.prefix(while: { $0.isNumber || $0 == "." })
        guard let n = Double(digits) else { return nil }
        if lower.contains("min") { return Int(n * 60) }
        return Int(n)
    }
}
