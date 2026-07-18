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
    static func select(sportSlug: String, phase: SeasonPhase, sessionIndex: Int) -> Int? {
        guard isEnabled, shouldServeAuthored(sportSlug: sportSlug) else { return nil }
        let db = CoachDatabase.shared
        var ids = db.authoredRoutineIds(sportSlug: sportSlug, phaseLabels: phaseLabels(for: phase))
        if ids.isEmpty {
            // Phase gap. A season-engine-supported sport (climbing pilot) falls
            // THROUGH to the engine. An unsupported authored sport has no engine
            // backstop, so broaden to any full-session routine for the sport —
            // an authored-served sport must never yield an empty day.
            guard !SportSeasonGenerator.supports(sportSlug) else { return nil }
            ids = db.authoredRoutineIds(sportSlug: sportSlug, phaseLabels: allPhaseLabels)
            if ids.isEmpty, SportCatalog.outdoorAuthoredSlugs.contains(sportSlug) {
                // Last resort for a real outdoor sport with no content of its
                // own: the universal cross-sport base (Easy Strength). Gated on
                // the allowlist so an arbitrary/unknown slug still returns nil.
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
    /// the authored sets/reps. Returns nil when the routine has no exercises.
    static func workout(
        forRoutineId routineId: Int,
        memory: TrainingMemory,
        context: GeneratorContext,
        focus: WorkoutFocus
    ) -> GeneratedWorkout? {
        let db = CoachDatabase.shared
        let rows = db.exercises(forRoutineId: routineId)
        guard !rows.isEmpty else { return nil }

        let exercises: [GeneratedExercise] = rows.map { re in
            let reps = re.reps ?? "8-12"
            var note = re.notes
            // Weight rec: append a load target from prior best. Only fires for
            // movements the user has a logged/imported best for and a numeric
            // rep band — bodyweight / AMRAP rows keep just the authored note.
            if let ex = db.exercise(id: re.exerciseId),
               let hint = WorkoutGenerator.progressiveOverloadHint(
                   for: ex, context: context, memory: memory, prescribedReps: reps) {
                note = [re.notes, hint]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            }
            return GeneratedExercise(
                id: "authored-\(routineId)-\(re.position)",
                exerciseId: re.exerciseId,
                name: re.name,
                pattern: nil,
                isCompound: false,
                sets: re.sets ?? 3,
                reps: reps,
                restSeconds: parseRest(re.rest) ?? 90,
                notes: note,
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
