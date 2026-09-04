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
        let n = max(1, min(athlete.sessionsPerWeek, rule.sessionsPerWeek.upperBound))
        return (0..<n).map { generateSession(athlete, sessionIndex: $0, sessionsInWeek: n) }
    }

    /// One session. `adjacentSportDay` triggers the defer-to-sport lighten when
    /// the phase rule demands it (SPEC §1 invariant 2 / §5).
    /// `sessionsInWeek` is how many lift sessions this week holds. It is what
    /// makes a demand weighted below one slot's granularity reachable: the
    /// allocation is computed for the WHOLE week and dealt across sessions, so
    /// ski off-season's `power` at 0.10 lands in one session out of three
    /// instead of rounding to zero in every one. It also makes the three
    /// sessions differ, which per-session allocation could not do — it asked
    /// for the same top-K demands every time and the pool answered with the
    /// same movements.
    /// `strategy` is the LLM coach's override layer. It reaches the season
    /// engine now (T1-6); before, `generateLift` accepted it and dropped it,
    /// so CoachRequestScreen made a billed call whose output was discarded and
    /// showed the model's reasoning above an unrelated deterministic workout.
    /// Only the fields that MEAN something to a demand-driven engine are
    /// honoured: intensity, and the per-exercise RPE / tempo / load overrides.
    /// `emphasizePatterns` / `deprioritizePatterns` are movement-pattern slugs
    /// with no demand equivalent and are still ignored, deliberately, rather
    /// than mapped by guesswork.
    static func generateSession(_ athlete: AthleteState,
                                sessionIndex: Int,
                                adjacentSportDay: Bool = false,
                                sessionsInWeek: Int = 1,
                                strategy: GeneratorStrategy = .auto) -> GeneratedWorkout {
        let rule = deloadAware(
            PhaseRule.resolve(sportSlug: athlete.sportSlug,
                              variant: athlete.variant, season: athlete.season),
            athlete: athlete)
        // Pool first: redistribution needs to know which demands this sport can
        // actually serve.
        let pool = filteredPool(athlete, phase: athlete.season)
        let weights = applyInjuryRedistribution(rule.demandWeights,
                                                flagged: athlete.flaggedDemands,
                                                available: Set(pool.flatMap(\.demands)))
        let seed = "\(athlete.sportSlug)-\(athlete.season.rawValue)-w\(athlete.weekNumber)-s\(sessionIndex)"

        let target = targetMovementCount(rule, preferredMinutes: athlete.preferredSessionMinutes)
        let slots = guaranteeSignature(
            weekSlots(weights, perSession: target,
                      sessionsInWeek: max(1, sessionsInWeek),
                      sessionIndex: sessionIndex),
            signature: signatureDemand(athlete.sportSlug),
            weights: weights,
            pool: pool)
        // Fatigue-shedding phases (in-season / transition / event taper — all
        // the deferToSport phases) bias selection toward lighter movements so
        // the session lands under the fatigue ceiling naturally. Building phases
        // (off / pre) don't — they chase the harder lifts.
        let preferLowFatigue = rule.deferToSport

        var picks: [Pick] = []
        var used = Set<Int>()
        var shortfall = 0
        // SCARCEST DEMAND FIRST. A movement can serve several demands, so a
        // demand with one qualifying movement in the pool loses it to a demand
        // with six whenever the six-way slot happens to run first — and which
        // one runs first shifts with `recentMovementIDs`, so the same week
        // regenerated after a rotation quietly dropped a demand it had covered
        // (ski `hipLateral`, one movement in the pool). Filling the scarce
        // slots first makes coverage independent of that ordering. Ties break
        // on the raw value for determinism.
        let scarcity = Dictionary(uniqueKeysWithValues: slots.map { demand, _ in
            (demand, pool.filter { $0.serves(demand) }.count)
        })
        let orderedSlots = slots.sorted {
            let a = scarcity[$0.0] ?? 0, b = scarcity[$1.0] ?? 0
            return a != b ? a < b : $0.0.rawValue < $1.0.rawValue
        }
        for (demand, count) in orderedSlots {
            // Hangboard max hangs at most TWICE a week (3a, 2026-09-04). The
            // signature guarantee puts fingerStrength in every session, which
            // is right; but finger tendon and pulley tissue adapts on a slower
            // timeline than muscle and the standard protocols cap max hangs at
            // two sessions a week with 48-72 h between. The third and later
            // sessions of a week fill the finger slot from the LIGHTER finger
            // movements (pinch holds, dead hangs) instead. Deterministic by
            // session index, so no cross-session state is needed.
            let excludeHangboard = demand == .fingerStrength
                && sessionsInWeek >= 3 && sessionIndex >= 2
            let candidates = pool
                .filter { $0.serves(demand) && !used.contains($0.exerciseId) }
                .filter { !excludeHangboard || !$0.name.localizedCaseInsensitiveContains("hangboard") }
                .sorted { lhs, rhs in
                    // PRIMARY-DEMAND MATCH OUTRANKS RECENCY. It used to sit
                    // below it, so a slot whose only primary-demand movement
                    // was recently used handed the slot to a movement that
                    // merely LISTS the demand — a squat filling a hipLateral
                    // slot. With one such movement in the pool (ski
                    // `hipLateral`) that is not a rotation, it is losing the
                    // demand entirely, which is what
                    // test_check7_rotation_preserves_coverage caught once T1-3
                    // made low-weight demands reachable at all. Rotation should
                    // vary WHICH movement serves a demand, never whether it is
                    // served.
                    let lp = lhs.primaryDemand == demand, rp = rhs.primaryDemand == demand
                    if lp != rp { return lp }
                    let lr = athlete.recentMovementIDs.contains(lhs.exerciseId)
                    let rr = athlete.recentMovementIDs.contains(rhs.exerciseId)
                    if lr != rr { return !lr }                               // not-recent first
                    if preferLowFatigue && lhs.fatigueCost != rhs.fatigueCost {
                        return lhs.fatigueCost < rhs.fatigueCost             // lighter first
                    }
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

        var exercises = picks.map {
            prescribe($0.movement, demand: $0.demand, rule: rule, strategy: strategy)
        }
        // Readiness x sets (T2-10). Same lerp(0.6, 1.0) curve makePickedRow
        // has used since Phase 2: a detrained user gets 60% of the sets, a
        // fully-ready one the full dose. nil means no data and no scaling;
        // the neutral 0.5 sentinel never reaches here.
        if let r = athlete.readinessScore {
            let mul = lerp(0.6, 1.0, r)
            exercises = exercises.map { ex in
                var e = ex
                e.sets = max(1, Int((Double(ex.sets) * mul).rounded()))
                return e
            }
        }
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

    /// The sport-defining demand appears in EVERY session, even when the
    /// week-level deal did not land one here.
    ///
    /// Dealing across the week is right for accessories and wrong for the
    /// signature: a climber's fingers and a skier's eccentric legs are the
    /// reason the block exists, and `test_check2_signature_coverage` asserts
    /// every session carries them. Takes the slot from the largest non-signature
    /// group so the session size is unchanged.
    static func guaranteeSignature(_ slots: [(Demand, Int)], signature: Demand?,
                                   weights: [Demand: Double],
                                   pool: [SportMovement]) -> [(Demand, Int)] {
        guard let signature,
              weights[signature, default: 0] > 0,
              pool.contains(where: { $0.serves(signature) }),
              !slots.contains(where: { $0.0 == signature }) else { return slots }
        var out = slots
        guard let donor = out.enumerated()
            .filter({ $0.element.1 > 0 })
            .max(by: { $0.element.1 < $1.element.1 })
        else { return [(signature, 1)] }
        out[donor.offset].1 -= 1
        out = out.filter { $0.1 > 0 }
        out.append((signature, 1))
        return out
    }

    /// This session's share of a WEEK-level allocation.
    ///
    /// Per-session allocation quantises at 1/target: with five slots any demand
    /// under 0.20 rounds to zero, and for ski off-season that silently deleted
    /// `power`, `legEndurance`, `prehab` and `hipLateral` — the four the
    /// objective's "fix imbalances" actually depends on. It also made every
    /// session ask for the same demands, so a three-day week came back as the
    /// same workout three times.
    ///
    /// Apportion over `perSession * sessionsInWeek` instead, then DEAL the flat
    /// list round-robin. Round-robin rather than contiguous chunks so the
    /// high-weight demands (which sort first) spread across sessions instead of
    /// stacking into session 0. Deterministic: same inputs, same deal.
    static func weekSlots(_ weights: [Demand: Double], perSession: Int,
                          sessionsInWeek: Int, sessionIndex: Int) -> [(Demand, Int)] {
        guard sessionsInWeek > 1 else { return allocateSlots(weights, count: perSession) }
        let flat = allocateSlots(weights, count: perSession * sessionsInWeek)
            .flatMap { demand, n in Array(repeating: demand, count: n) }
        guard !flat.isEmpty else { return [] }
        let idx = ((sessionIndex % sessionsInWeek) + sessionsInWeek) % sessionsInWeek
        var counts: [Demand: Int] = [:]
        var order: [Demand] = []
        for (i, demand) in flat.enumerated() where i % sessionsInWeek == idx {
            if counts[demand] == nil { order.append(demand) }
            counts[demand, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
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

    /// Apply the mesocycle deload to a phase rule (T1-8).
    ///
    /// `MesocycleProgression` already knows whether this is a deload week; it
    /// just had no consumer outside the badge, so a DELOAD pill sat above a
    /// full-volume session. `weekNumber` is 1-indexed weeks into the phase and
    /// is the same value the badge reads.
    ///
    /// Only `.deload` changes the prescription. `.taper` and `.peak` are
    /// event-prep states the eventPrep rule already expresses through its own
    /// weights and a cap of 14, and `.deloadNextWeek` is a warning, not a dose.
    static func deloadAware(_ rule: PhaseRule, athlete: AthleteState) -> PhaseRule {
        let daysUntilPeak = athlete.targetObjectiveDate.map {
            Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0
        }
        let status = MesocycleProgression.status(phase: athlete.season,
                                                 weeksInPhase: athlete.weekNumber,
                                                 daysUntilPeak: daysUntilPeak)
        return status.state == .deload ? rule.deloaded() : rule
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
        // ROUND, don't truncate. Integer division made the default profile a
        // 4-movement session in every phase: sessionMinutes defaults to 45
        // (TrainingMemory.swift), ski off-season clamps it UP to its 50-minute
        // floor, and 50 / 11 truncates to 4. Every phase whose lower bound sits
        // between 44 and 54 landed on the same number, which is why the
        // eval report showed 4 movements everywhere and why any demand
        // weighted under 0.25 could never be expressed (four slots, quarter
        // granularity). 50 now rounds to 5.
        //
        // The 11-minute heuristic itself still over-estimates: `assemble`
        // measures that same off-season session at ~33 min, about 8.25 per
        // movement. Reconciling the two estimators is a separate change --
        // this one only stops the truncation.
        return max(3, min(6, Int((Double(minutes) / 11.0).rounded())))
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
    /// - Parameter sessionsInWeek: MUST match what generation used. Slots are
    ///   apportioned across the whole week now (see `weekSlots`), so the
    ///   quantisation floor is 1/(perSession * sessionsInWeek) rather than
    ///   1/perSession, and a per-session intent describes a coarser session
    ///   than the one produced.
    static func intendedSlotDistribution(for rule: PhaseRule,
                                         preferredMinutes: Int? = nil,
                                         sessionsInWeek: Int = 1,
                                         signature: Demand? = nil,
                                         pool: [SportMovement] = []) -> [Demand: Double] {
        let perSession = targetMovementCount(rule, preferredMinutes: preferredMinutes)
        let n = max(1, sessionsInWeek)
        // Sum what the generator will actually ask for, session by session,
        // INCLUDING the per-session signature guarantee. Modelling only the
        // raw week apportionment understates the signature and overstates
        // whichever group donates the slot, which is a real 0.25 L1 drift on
        // ski maintenance and climbing in-season.
        var out: [Demand: Double] = [:]
        var total = 0.0
        for i in 0..<n {
            let slots = guaranteeSignature(
                weekSlots(rule.demandWeights, perSession: perSession,
                          sessionsInWeek: n, sessionIndex: i),
                signature: signature, weights: rule.demandWeights, pool: pool)
            for (d, k) in slots {
                out[d, default: 0] += Double(k)
                total += Double(k)
            }
        }
        guard total > 0 else { return [:] }
        for k in out.keys { out[k]! /= total }
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
    private static func prescribe(_ m: SportMovement, demand: Demand, rule: PhaseRule,
                                  strategy: GeneratorStrategy = .auto) -> GeneratedExercise {
        let scheme = DemandScheme.scheme(for: demand, progression: rule.progression)
        let key = m.name.lowercased()
        // Sets: the strategy's intensity bias, clamped so a `push` can't run
        // away and a `deload` can't zero the movement out.
        let sets = max(1, Int((Double(scheme.setsMid) * strategy.intensityBias.setsMultiplier).rounded()))
        // A load target the coach named is appended to the notes rather than
        // replacing the injury caution, which is the one note that must survive.
        let loadNote = strategy.targetWeightOverrides[key].map { "target: \(Int($0.rounded())) lb" }
        let notes = [m.injuryCaution.map { "Caution: \($0)" }, loadNote]
            .compactMap { $0 }
            .joined(separator: " · ")
        return GeneratedExercise(
            id: "ss-\(m.exerciseId)",
            exerciseId: m.exerciseId,
            name: m.name,
            pattern: nil,
            isCompound: m.isCompound,
            sets: sets,
            reps: scheme.repsString,
            restSeconds: scheme.restSeconds,
            notes: notes.isEmpty ? nil : notes,
            rpe: strategy.rpeOverrides[key] ?? scheme.rpeString,
            tempo: strategy.tempoOverrides[key] ?? scheme.tempoString,
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
