// SportSeasonGenerator.swift — the season-aware engine (SPEC §5).
//
// Pure + deterministic: generate(athlete) → a week of sessions whose movement
// selection, volume, and intensity all trace to the (sport, variant, phase)
// PhaseRule. No app state, no I/O beyond the read-only catalog query. The seed
// is fixed per (sport, season, weekNumber, sessionIndex) so a delta is always
// attributable to an input, never to a shuffled pick (mirrors generateLift's
// hashSeed discipline).
//
// Pipeline (SPEC §5):
//   resolvePhase → phaseRule → applyVariantOverride (in resolve) →
//   applyInjuryRedistribution → build filtered pool → demand-weighted slot
//   allocation → deterministic selectN(prefer primary demand, deprioritize
//   recent) → per-phase scheme + progression → enforceFatigueCap →
//   (deferToSport lighten) → emit GeneratedWorkout.

import Foundation

enum SportSeasonGenerator {

    // MARK: - Public entry

    /// A full week: one session per `sessionsPerWeek` (clamped to the athlete's
    /// availability), each deterministic by its index.
    static func generateWeek(_ athlete: AthleteState) -> [GeneratedWorkout] {
        let rule = PhaseRule.resolve(sportSlug: athlete.sportSlug,
                                     variant: athlete.variant, season: athlete.season)
        let n = min(athlete.sessionsPerWeek, rule.sessionsPerWeek.upperBound)
        return (0..<max(1, n)).map { generateSession(athlete, sessionIndex: $0) }
    }

    /// One session. `adjacentSportDay` triggers the defer-to-sport lighten when
    /// the phase rule demands it (SPEC §1 invariant 2 / §5).
    static func generateSession(_ athlete: AthleteState,
                                sessionIndex: Int,
                                adjacentSportDay: Bool = false) -> GeneratedWorkout {
        let rule = PhaseRule.resolve(sportSlug: athlete.sportSlug,
                                     variant: athlete.variant, season: athlete.season)
        // Pool first: redistribution needs to know which demands this sport can
        // actually serve.
        let pool = filteredPool(athlete, phase: athlete.season)
        let weights = applyInjuryRedistribution(rule.demandWeights,
                                                flagged: athlete.flaggedDemands,
                                                available: Set(pool.flatMap(\.demands)))
        let seed = "\(athlete.sportSlug)-\(athlete.season.rawValue)-w\(athlete.weekNumber)-s\(sessionIndex)"

        let target = targetMovementCount(rule, preferredMinutes: athlete.preferredSessionMinutes)
        let slots = allocateSlots(weights, count: target)
        // Fatigue-shedding phases (in-season / transition / event taper — all
        // the deferToSport phases) bias selection toward lighter movements so
        // the session lands under the fatigue ceiling naturally. Building phases
        // (off / pre) don't — they chase the harder lifts.
        let preferLowFatigue = rule.deferToSport

        var picks: [Pick] = []
        var used = Set<Int>()
        var shortfall = 0
        for (demand, count) in slots {
            let candidates = pool
                .filter { $0.serves(demand) && !used.contains($0.exerciseId) }
                .sorted { lhs, rhs in
                    let lr = athlete.recentMovementIDs.contains(lhs.exerciseId)
                    let rr = athlete.recentMovementIDs.contains(rhs.exerciseId)
                    if lr != rr { return !lr }                               // not-recent first
                    if preferLowFatigue && lhs.fatigueCost != rhs.fatigueCost {
                        return lhs.fatigueCost < rhs.fatigueCost             // lighter first
                    }
                    let lp = lhs.primaryDemand == demand, rp = rhs.primaryDemand == demand
                    if lp != rp { return lp }                               // primary demand first
                    return djb2("\(seed)-\(demand.rawValue)-\(lhs.exerciseId)")
                         < djb2("\(seed)-\(demand.rawValue)-\(rhs.exerciseId)")
                }
            for m in candidates.prefix(count) {
                picks.append(Pick(movement: m, demand: demand))
                used.insert(m.exerciseId)
            }
            // Track the shortfall. `candidates.prefix(count)` of an empty or
            // short list silently yields fewer movements and the slot is simply
            // LOST — an equipment-restricted or injury-filtered athlete got a
            // session below the documented 3-movement floor with no explanation.
            shortfall += max(0, count - candidates.count)
        }

        // Backfill from any demand that still has candidates, so the session
        // keeps its intended size. Ordered by the rule's own weights, so what
        // replaces a dropped slot is still phase-appropriate.
        if shortfall > 0 {
            let byWeight = rule.demandWeights.sorted { $0.value > $1.value }.map(\.key)
            outer: for demand in byWeight {
                for m in pool.filter({ $0.serves(demand) && !used.contains($0.exerciseId) })
                    .sorted(by: { djb2("\(seed)-backfill-\($0.exerciseId)") < djb2("\(seed)-backfill-\($1.exerciseId)") }) {
                    picks.append(Pick(movement: m, demand: demand))
                    used.insert(m.exerciseId)
                    shortfall -= 1
                    if shortfall == 0 { break outer }
                }
            }
        }

        picks = enforceFatigueCap(picks, cap: rule.sessionVolumeCap,
                                  phase: athlete.season, signature: signatureDemand(athlete.sportSlug))
        if rule.deferToSport && adjacentSportDay { picks = lighten(picks) }

        let exercises = picks.map { prescribe($0.movement, demand: $0.demand, rule: rule) }
        return assemble(exercises, picks: picks, athlete: athlete, rule: rule,
                        sessionIndex: sessionIndex, lightened: rule.deferToSport && adjacentSportDay)
    }

    // MARK: - Pool

    /// Map a supported sport slug onto the slug that actually has rows in
    /// `sport_movements`. The engine claims three ski slugs and seven climbing
    /// slugs, but the shipped coach.db seeds only `alpine-skiing` (44 rows) and
    /// `climbing` (25). Picking "Skiing / Snowboarding" (snow-sports) or
    /// "Ski Mountaineering" — both in Sport.catalog and both accepted by
    /// `supports()` — therefore produced an empty pool and a 0-movement session
    /// on EVERY lift day. The ski variants share a movement vocabulary, so
    /// aliasing is correct, not a stopgap; `PhaseRule.applyingVariantOverride`
    /// is what expresses their differences.
    ///
    /// The climbing variants are aliased for the same reason, though none are
    /// currently in Sport.catalog so they're unreachable from the UI today.
    static func poolSlug(for sportSlug: String) -> String {
        if PhaseRule.skiSlugs.contains(sportSlug) { return "alpine-skiing" }
        if PhaseRule.climbingSlugs.contains(sportSlug) { return "climbing" }
        return sportSlug
    }

    private static func filteredPool(_ athlete: AthleteState, phase: SeasonPhase) -> [SportMovement] {
        // eventPrep draws from BOTH its own pool and the pre-season pool: for
        // skiing it's literally "pre-season tapered" (same movements); for
        // climbing it's antagonist-heavy, so its distinct event_prep-tagged
        // movements must surface alongside the sharp pre-season ones. Accepting
        // either tag covers both without duplicating phase tags across the seed.
        let raw = CoachDatabase.shared.sportMovements(sport: poolSlug(for: athlete.sportSlug))
            .filter { m in
                let phaseOK = (phase == .eventPrep)
                    ? (m.allowed(in: .eventPrep) || m.allowed(in: .preSeason))
                    : m.allowed(in: phase)
                return phaseOK
                    && m.allowed(for: athlete.variant)
                    && m.minExperienceRank <= athlete.experience.seasonRank
                    && !athlete.contraindicatedExerciseIDs.contains(m.exerciseId)
            }
        // Equipment: an empty available-set means FULL GYM / unrestricted (the
        // `allowedCoachDbSlugs` convention — full gym returns []). Otherwise a
        // movement is usable when all its required slugs are available;
        // bodyweight movements (no required slugs) are always usable.
        if athlete.availableEquipmentSlugs.isEmpty { return raw }
        let reqs = CoachDatabase.shared.requiredEquipmentSlugs(
            forExerciseIds: Set(raw.map(\.exerciseId)))
        return raw.filter { m in
            let need = reqs[m.exerciseId] ?? []
            return need.isEmpty || need.isSubset(of: athlete.availableEquipmentSlugs)
        }
    }

    // MARK: - Demand weighting

    /// SPEC §5 applyInjuryRedistribution: a flagged demand zeroes; its weight
    /// lands on antagonist/prehab. Empty for skiing M1 (mechanism for M3).
    /// - Parameter available: demands this sport's movement pool can actually
    ///   serve. The sinks were hardcoded [.prehab, .antagonist], but the
    ///   alpine-skiing pool carries ZERO antagonist movements (its demands are
    ///   maxStrength / kneeStability / eccentricLeg / prehab / legEndurance /
    ///   aerobicUphill / power / hipLateral / core). So for an injured skier
    ///   half the freed weight allocated slots that found no candidates. Pass
    ///   nil to keep the old unfiltered behavior (tests, callers without a pool).
    static func applyInjuryRedistribution(_ weights: [Demand: Double],
                                          flagged: Set<Demand>,
                                          available: Set<Demand>? = nil) -> [Demand: Double] {
        guard !flagged.isEmpty else { return weights }
        var w = weights
        var freed = 0.0
        for d in flagged where w[d] != nil { freed += w[d] ?? 0; w[d] = 0 }
        guard freed > 0 else { return w }
        var sinks: [Demand] = [.prehab, .antagonist]
        if let available {
            let servable = sinks.filter { available.contains($0) && !flagged.contains($0) }
            // Fall back to any non-flagged demand the pool serves rather than
            // dropping the weight on the floor.
            sinks = servable.isEmpty
                ? available.subtracting(flagged).sorted { $0.rawValue < $1.rawValue }
                : servable
        }
        guard !sinks.isEmpty else { return w }
        let share = freed / Double(sinks.count)
        for s in sinks { w[s, default: 0] += share }
        return w
    }

    /// Largest-remainder apportionment of `count` slots across demands by
    /// weight. Demands are iterated in a DETERMINISTIC order (weight desc, then
    /// rawValue) so ties resolve identically every run — the fixed-seed promise.
    static func allocateSlots(_ weights: [Demand: Double], count: Int) -> [(Demand, Int)] {
        let active = weights.filter { $0.value > 0 }.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue
        }
        let total = active.reduce(0) { $0 + $1.value }
        guard total > 0, count > 0 else { return [] }
        var floors: [(demand: Demand, n: Int, rem: Double)] = active.map { d, w in
            let exact = w / total * Double(count)
            let f = exact.rounded(.down)
            return (d, Int(f), exact - f)
        }
        let assigned = floors.reduce(0) { $0 + $1.n }
        let order = floors.indices.sorted {
            floors[$0].rem != floors[$1].rem ? floors[$0].rem > floors[$1].rem
                                             : floors[$0].demand.rawValue < floors[$1].demand.rawValue
        }
        for k in 0..<max(0, count - assigned) { floors[order[k % order.count]].n += 1 }
        return floors.filter { $0.n > 0 }.map { ($0.demand, $0.n) }
    }

    /// The one demand a phase must always cover (asserted by SeasonFidelity
    /// check 2 and protected by the fatigue cap). Ski = eccentricLeg,
    /// climbing = fingerStrength.
    static func signatureDemand(_ sportSlug: String) -> Demand? {
        if PhaseRule.skiSlugs.contains(sportSlug) { return .eccentricLeg }
        if PhaseRule.climbingSlugs.contains(sportSlug) { return .fingerStrength }
        return nil
    }

    /// Sports the season engine generates for. The live Planner routes these to
    /// `generateSession`; everything else falls through to the legacy generator.
    static func supports(_ sportSlug: String?) -> Bool {
        guard let s = sportSlug else { return false }
        return PhaseRule.skiSlugs.contains(s) || PhaseRule.climbingSlugs.contains(s)
    }

    /// Default variant until the variant picker lands (M4): ski → inbounds,
    /// climbing → sportRoute.
    static func defaultVariant(forSport sportSlug: String?) -> SportVariant {
        guard let s = sportSlug else { return .inbounds }
        return PhaseRule.climbingSlugs.contains(s) ? .sportRoute : .inbounds
    }

    private static func targetMovementCount(_ rule: PhaseRule,
                                            preferredMinutes: Int? = nil) -> Int {
        // ~11 min per movement; clamp to a sane session shape.
        //
        // T2-7: honor the user's declared session length. This read ONLY the
        // rule's own band, so `memory.sessionMinutes` had no effect on season
        // workouts at all — "30 minutes" and "90 minutes" both produced the
        // same ~63-minute off-season session. The phase rule still bounds the
        // result: a 90-minute preference can't inflate an in-season taper past
        // what the phase intends, and a 20-minute one can't drop below the
        // 3-movement floor.
        let ruleMinutes = rule.sessionMinutesTarget
        let minutes = preferredMinutes.map {
            min(max($0, ruleMinutes.lowerBound), ruleMinutes.upperBound)
        } ?? ruleMinutes.upperBound
        return max(3, min(6, minutes / 11))
    }

    /// The generator's INTENDED per-session demand emphasis (normalized slot
    /// allocation). A K-slot session can only approximate a continuous weight
    /// vector; this is the quantization-limited best match, used by
    /// SeasonFidelity check 1 as the fidelity floor (realized should track THIS,
    /// not the raw weights). Exposed for the eval.
    /// - Parameter preferredMinutes: MUST match what generation used, or this
    ///   describes a differently-sized session than the one produced and the
    ///   fidelity check compares apples to oranges. (T2-7 wired the user's
    ///   declared session length into `targetMovementCount`; this overload
    ///   existed only in the rule's-ceiling form and immediately disagreed with
    ///   every generated week.)
    static func intendedSlotDistribution(for rule: PhaseRule,
                                         preferredMinutes: Int? = nil) -> [Demand: Double] {
        let slots = allocateSlots(rule.demandWeights,
                                  count: targetMovementCount(rule, preferredMinutes: preferredMinutes))
        let total = Double(slots.reduce(0) { $0 + $1.1 })
        guard total > 0 else { return [:] }
        var out: [Demand: Double] = [:]
        for (d, n) in slots { out[d, default: 0] += Double(n) / total }
        return out
    }

    // MARK: - Deterministic tiebreak

    private static func djb2(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }

    // MARK: - Fatigue cap

    private struct Pick { let movement: SportMovement; let demand: Demand }

    /// Drop highest-fatigue movements until Σ fatigueCost ≤ cap, never dropping
    /// the last carrier of a demand and keeping ≥3 movements. In-season also
    /// excludes cost-5 movements outright (SPEC §6 check 3).
    private static func enforceFatigueCap(_ picks: [Pick], cap: Int,
                                          phase: SeasonPhase, signature: Demand?) -> [Pick] {
        // In-season / transition exclude cost-5 movements outright (SPEC §6 #3).
        var kept = (phase == .inSeason || phase == .maintenance)
            ? picks.filter { $0.movement.fatigueCost < 5 } : picks
        func total() -> Int { kept.reduce(0) { $0 + $1.movement.fatigueCost } }
        while total() > cap && kept.count > 3 {
            // Protect the LAST carrier of the signature demand; otherwise drop
            // the highest-fatigue movement (even a sole non-signature carrier).
            let sigCount = signature.map { sig in kept.filter { $0.demand == sig }.count } ?? 0
            let droppable = kept.enumerated().filter { e in
                guard let sig = signature, e.element.demand == sig else { return true }
                return sigCount > 1
            }.sorted { $0.element.movement.fatigueCost > $1.element.movement.fatigueCost }
            guard let drop = droppable.first else { break }
            kept.remove(at: drop.offset)
        }
        return kept
    }

    private static func lighten(_ picks: [Pick]) -> [Pick] {
        // Defer-to-sport: drop the single highest-fatigue movement (shorten).
        guard picks.count > 3, let drop = picks.enumerated()
            .max(by: { $0.element.movement.fatigueCost < $1.element.movement.fatigueCost })
        else { return picks }
        var out = picks; out.remove(at: drop.offset); return out
    }

    // MARK: - Prescription

    /// Prescription is driven by the DEMAND the slot was allocated to (not the
    /// movement's generic catalog default), modulated by the phase progression.
    private static func prescribe(_ m: SportMovement, demand: Demand, rule: PhaseRule) -> GeneratedExercise {
        let scheme = DemandScheme.scheme(for: demand, progression: rule.progression)
        return GeneratedExercise(
            id: "ss-\(m.exerciseId)",
            exerciseId: m.exerciseId,
            name: m.name,
            pattern: nil,
            isCompound: m.isCompound,
            sets: max(1, scheme.setsMid),
            reps: scheme.repsString,
            restSeconds: scheme.restSeconds,
            notes: m.injuryCaution.map { "Caution: \($0)" },
            rpe: scheme.rpeString,
            tempo: scheme.tempoString,
            source: .recipe)
    }

    /// Short, human label for a session title. Prefers the catalog's own name
    /// so a new sport needs no change here.
    static func sportTitlePrefix(for slug: String) -> String {
        if let sport = Sport.catalog.first(where: { $0.slug == slug }) {
            return sport.name
        }
        if PhaseRule.skiSlugs.contains(slug) { return "Ski" }
        if PhaseRule.climbingSlugs.contains(slug) { return "Climb" }
        return slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    // MARK: - Assembly

    private static func assemble(_ exercises: [GeneratedExercise], picks: [Pick],
                                 athlete: AthleteState, rule: PhaseRule,
                                 sessionIndex: Int, lightened: Bool) -> GeneratedWorkout {
        let minutes = exercises.reduce(0) { $0 + Int(ceil(Double($1.sets) * (Double($1.restSeconds) + 40) / 60)) }
        let demandMix = picks.map { $0.demand.rawValue }
        // Derived from the athlete's actual sport. Hardcoding "Ski" meant a
        // climbing athlete who fell through to the engine read
        // "Ski · In-season — Session 1" on a finger-strength session — and the
        // string also poisons PlanValidator.resolveFocus, which infers focus
        // from title text.
        let title = "\(sportTitlePrefix(for: athlete.sportSlug)) · \(athlete.season.label) — Session \(sessionIndex + 1)"
        let summary = "\(exercises.count) movements · ~\(minutes) min"
        var prov = "\(athlete.sportSlug) · \(athlete.variant.rawValue) · \(rule.objective)"
        if lightened { prov += " · lightened (sport day adjacent)" }
        prov += " · demands: \(demandMix.joined(separator: "/"))"
        // A real WorkoutFocus (not nil) so downstream consolidation / split
        // analytics / LLM-refinement anchoring keep working. Season sessions are
        // whole-body by construction → fullBodyA.
        return GeneratedWorkout(
            title: title, summary: summary, exercises: exercises,
            estimatedMinutes: minutes, provenance: prov, focus: .fullBodyA)
    }
}
