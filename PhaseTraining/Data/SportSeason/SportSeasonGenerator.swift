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
                                strategy: GeneratorStrategy = .auto,
                                complement: ComplementSlot? = nil,
                                pushSets: ClosedRange<Int>? = nil) -> GeneratedWorkout {
        // What the recovery gate cost this session: the blocked areas among
        // the movements the same session picks when nothing is blocked. The
        // pool alone would overstate it (a complement day's pool holds leg
        // movements it never picks).
        var skippedAreas: [String] = []
        if !athlete.blockedBuckets.isEmpty {
            var open = athlete
            open.blockedBuckets = []
            let ungated = generateSession(open, sessionIndex: sessionIndex,
                                          adjacentSportDay: adjacentSportDay,
                                          sessionsInWeek: sessionsInWeek,
                                          strategy: strategy, complement: complement,
                                          pushSets: pushSets)
            let hit = ungated.exercises.reduce(into: Set<String>()) {
                $0.formUnion(WorkoutGenerator.primaryMuscleBuckets(exerciseId: $1.exerciseId))
            }.intersection(athlete.blockedBuckets)
            skippedAreas = MuscleBucket.allCases.map(\.rawValue).filter(hit.contains)
        }
        // A complement session (SessionMix) keeps the phase's progression,
        // volume cap and length, swaps in its focus's demand mix, and draws
        // from the general-fitness pool instead of the sport's.
        let phaseRule = PhaseRule.resolve(sportSlug: athlete.sportSlug,
                                          variant: athlete.variant, season: athlete.season)
        let rule = complement.map { phaseRule.complement($0.focus) } ?? phaseRule
        let cycle = cycleStatus(athlete)
        let signature = complement == nil ? signatureDemand(athlete.sportSlug) : nil
        let sessionIndex = complement == nil ? sessionIndex : 0
        let sessionsInWeek = complement == nil ? sessionsInWeek : 1
        // Pool first: redistribution needs to know which demands this sport can
        // actually serve.
        let unrecovered = filteredPool(athlete, phase: athlete.season,
                                       poolSport: complement == nil ? nil : complementPoolSlug)
        // Rule one: a movement whose prime mover is still recovering on this
        // date never reaches the session. Its demand falls through to the
        // shortfall backfill like any other emptied demand.
        let blockedIds = movementIds(in: unrecovered, loading: athlete.blockedBuckets)
        let pool = unrecovered.filter { !blockedIds.contains($0.exerciseId) }
        // Movements whose primary muscle is only part-recovered (or reported
        // mildly sore). Resolved once per session: the lookup goes through
        // coach.db.
        let soreIds = movementIds(in: pool, loading: athlete.easedBuckets)
        let weights = applyInjuryRedistribution(rule.demandWeights,
                                                flagged: athlete.flaggedDemands,
                                                available: Set(pool.flatMap(\.demands)))
        let slotTag = "-s\(sessionIndex)" + (complement.map { "-\($0.focus.rawValue)\($0.repeatNumber)" } ?? "")
        let seed = "\(athlete.sportSlug)-\(athlete.season.rawValue)-w\(athlete.weekNumber)" + slotTag
        // Anchor lifts are seeded by the mesocycle block, not the week, so the
        // same squat or press comes back in weeks 1 to 3 and the athlete can
        // add load to it (finding 9). Accessories keep the weekly seed.
        let cycleLength = MesocycleProgression.cycleLength(for: athlete.season)
        let blockLength = cycleLength > 0 ? cycleLength : 4
        let anchorSeed = "\(athlete.sportSlug)-\(athlete.season.rawValue)-b\((max(1, athlete.weekNumber) - 1) / blockLength)"
            + slotTag

        let target = targetMovementCount(rule, preferredMinutes: athlete.preferredSessionMinutes)
        let slots = guaranteeSignature(
            weekSlots(weights, perSession: target,
                      sessionsInWeek: max(1, sessionsInWeek),
                      sessionIndex: sessionIndex),
            signature: signature,
            weights: weights,
            pool: pool)
        // Fatigue-shedding phases (in-season / transition / event taper — all
        // the deferToSport phases) bias selection toward lighter movements so
        // the session lands under the fatigue ceiling naturally. Building phases
        // (off / pre) don't — they chase the harder lifts.
        let preferLowFatigue = rule.deferToSport
        // R3-2. `guaranteeSignature` returns the slots untouched when the pool
        // can serve none of the signature demand, which is what a full injury
        // filter produces: a carpal-tunnel climber's pre-season came back with
        // three bodyTension slots and zero finger work under a session whose
        // objective still read "Max finger strength". The redistribution is
        // right; being quiet about it is not.
        let signatureUnavailable: Bool = {
            guard let sig = signature,
                  weights[sig, default: 0] > 0 else { return false }
            return !pool.contains { $0.serves(sig) }
        }()

        var picks: [Pick] = []
        var used = Set<Int>()
        var shortfall = 0
        // Pressing movements, read only when the week sets this session's
        // push sets (see `pushSets` below).
        let pushDemand: Demand = complement == nil ? .upperStrength : .upperPush
        let pushFloor = pushSets?.lowerBound ?? 0
        let pushCeiling = pushSets?.upperBound ?? Int.max
        let pushIds: Set<Int> = pushSets != nil ? Set(pool.filter { m in
            !Set(CoachDatabase.shared.patternsForExercise(m.exerciseId)).isDisjoint(with: Self.pushPatterns)
        }.map(\.exerciseId)) : []
        let squatIds = Set(pool.filter { m in
            Self.heavyLegDemands.contains { m.serves($0) }
                && CoachDatabase.shared.patternsForExercise(m.exerciseId).contains("squat")
        }.map(\.exerciseId))
        // Loadability (finding 6): when the athlete owns something to load a
        // movement with, a strength slot prefers a barbell, dumbbell, machine
        // or bar movement over a bodyweight one, and "(Knees)" and band
        // regressions sink below both. Beginners keep the old ranking: the
        // regressions are for them, and for the bodyweight tier.
        let loadAware = athlete.experience != .beginner
            && (athlete.availableEquipmentSlugs.isEmpty
                || !athlete.availableEquipmentSlugs.isDisjoint(with: Self.loadingEquipment))
        let loadRank: [Int: Int] = loadAware ? {
            let reqs = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: Set(pool.map(\.exerciseId)))
            return Dictionary(uniqueKeysWithValues: pool.map { m in
                (m.exerciseId, Self.loadRank(m, required: reqs[m.exerciseId] ?? []))
            })
        }() : [:]
        func squatCapped(_ m: SportMovement, _ demand: Demand, _ chosen: [Pick]) -> Bool {
            Self.heavyLegDemands.contains(demand) && squatIds.contains(m.exerciseId)
                && chosen.contains { Self.heavyLegDemands.contains($0.demand) && squatIds.contains($0.movement.exerciseId) }
        }
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
            let isAnchor = anchorDemands.contains(demand)
            let isStrengthSlot = loadAware && Self.strengthDemands.contains(demand)
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
                    // A session owing push sets fills its upper slot with a
                    // press before a pull.
                    if demand == pushDemand, !pushIds.isEmpty {
                        let lq = pushIds.contains(lhs.exerciseId), rq = pushIds.contains(rhs.exerciseId)
                        if lq != rq { return lq }
                    }
                    // Sore tier: a movement that loads a sore muscle as its
                    // prime mover ranks below every other movement serving
                    // the same demand. Below the primary-demand check for the
                    // same reason rotation is: soreness changes which movement
                    // serves a demand, never whether it is served.
                    let ls = soreIds.contains(lhs.exerciseId), rs = soreIds.contains(rhs.exerciseId)
                    if ls != rs { return !ls }
                    // Load tier, strength slots only. Below the primary-demand
                    // and sore checks for the same reason they sit there: it
                    // changes which movement serves a demand, never whether.
                    if isStrengthSlot {
                        let ll = loadRank[lhs.exerciseId] ?? 1, rl = loadRank[rhs.exerciseId] ?? 1
                        if ll != rl { return ll < rl }
                    }
                    // Rotation tier: 0 fresh, 1 recent, 2 rejected by the user
                    // (affinity <= sink threshold). A rejected movement still
                    // ranks inside its primary-demand group, so a demand whose
                    // only movement the user dislikes is still served.
                    // Anchors skip the recency tier for the same reason they
                    // skip the weekly seed: last week's squat is this week's.
                    let lt = rotationTier(lhs, athlete, anchor: isAnchor)
                    let rt = rotationTier(rhs, athlete, anchor: isAnchor)
                    if lt != rt { return lt < rt }
                    if preferLowFatigue && lhs.fatigueCost != rhs.fatigueCost {
                        return lhs.fatigueCost < rhs.fatigueCost             // lighter first
                    }
                    // Preference breaks ties INSIDE a tier, so a favorite
                    // returns each time it rotates out of the recent window
                    // without defeating rotation.
                    let la = athlete.affinity(for: lhs.name), ra = athlete.affinity(for: rhs.name)
                    if la != ra { return la > ra }
                    let tie = isAnchor ? anchorSeed : seed
                    return djb2("\(tie)-\(demand.rawValue)-\(lhs.exerciseId)")
                         < djb2("\(tie)-\(demand.rawValue)-\(rhs.exerciseId)")
                }
            // One bilateral squat pattern among the heavy leg demands per
            // session (finding 5: an eccentric back squat and a back squat in
            // one session). A slot left with only another squat goes to the
            // shortfall backfill below instead.
            var taken = 0
            for m in candidates where taken < count && !squatCapped(m, demand, picks) {
                picks.append(Pick(movement: m, demand: demand))
                used.insert(m.exerciseId)
                taken += 1
            }
            // Track the shortfall. A short candidate list yields fewer
            // movements and the slot is LOST: an equipment-restricted or
            // injury-filtered athlete got a session below the documented
            // 3-movement floor with no explanation.
            shortfall += max(0, count - taken)
        }

        // Backfill from any demand that still has candidates, so the session
        // keeps its intended size. Ordered by the rule's own weights, so what
        // replaces a dropped slot is still phase-appropriate.
        func backfillCandidates(_ chosen: [Pick]) -> [Pick] {
            var byWeight = rule.demandWeights.sorted {
                $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue
            }.map(\.key)
            // A complement day whose own demands ran dry (an injury that rules
            // out most pulling, say) backfills from the other upper-body and
            // core demands. Legs only when the focus already trains legs: a
            // skier's complement day never turns into leg work. Pulling and
            // arms only when the focus already trains them or the sport is
            // legs-dominant, for the same reason: a climber's complement day
            // filled with rows and curls leaves the next climbing session's
            // back and biceps blocked by the recovery gate.
            if complement != nil {
                let climberSpare = SessionMix.family(forSport: athlete.sportSlug) == .upperDominant
                var spare: [Demand] = [.core, .upperPush, .upperPull, .arms].filter {
                    !climberSpare || ($0 != .upperPull && $0 != .arms) || rule.demandWeights[$0] != nil
                }
                if rule.demandWeights[.legStrength] != nil { spare.append(.legStrength) }
                byWeight += spare.filter { !byWeight.contains($0) }
            }
            var out: [Pick] = []
            var seen = Set(chosen.map(\.movement.exerciseId))
            for demand in byWeight {
                for m in pool.filter({ $0.serves(demand) && !seen.contains($0.exerciseId)
                                        && !squatCapped($0, demand, chosen + out) })
                    .sorted(by: {
                        // Backfill only sinks rejected movements; it does not
                        // chase favorites, which would bypass rotation.
                        let l = isRejected($0, athlete), r = isRejected($1, athlete)
                        if l != r { return !l }
                        let ls = soreIds.contains($0.exerciseId), rs = soreIds.contains($1.exerciseId)
                        if ls != rs { return !ls }
                        return djb2("\(seed)-backfill-\($0.exerciseId)") < djb2("\(seed)-backfill-\($1.exerciseId)")
                    }) {
                    out.append(Pick(movement: m, demand: demand))
                    seen.insert(m.exerciseId)
                }
            }
            return out
        }
        if shortfall > 0 {
            picks += backfillCandidates(picks).prefix(shortfall)
        }

        picks = enforceFatigueCap(picks, cap: rule.sessionVolumeCap,
                                  phase: athlete.season, signature: signature)
        // Complement days load what the sport does not, so they never defer.
        let lightened = complement == nil && rule.deferToSport && adjacentSportDay
        if lightened { picks = lighten(picks) }

        // The build weeks of a progressive-overload block ramp the anchor
        // lifts' effort; a deload week holds the band.
        let rampWeek: Int? = rule.progression == .progressiveOverload
            && (cycle.state == .build || cycle.state == .deloadNextWeek) ? cycle.weekOfCycle : nil
        // The muscles the sport sessions train (RecoveryWeekProbeTests reads
        // the same buckets).
        let sportMuscles: Set<String> = SessionMix.family(forSport: athlete.sportSlug) == .upperDominant
            ? ["back", "forearms", "biceps"] : ["quads", "hamstrings", "glutes"]
        func row(_ p: Pick) -> Row {
            let e = prescribe(p.movement, demand: p.demand, rule: rule, strategy: strategy, goal: athlete.goal,
                              experience: athlete.experience, age: athlete.age, rampWeek: rampWeek)
            // A cited protocol keeps its own sets; everything else may move
            // within the athlete's ceiling while the session is fitted. On a
            // complement day a movement that loads the sport's own muscles
            // keeps its prescribed sets until the session cannot otherwise
            // reach its length floor: the fit once raised a climber's
            // Romanian deadlifts to five sets the day before a climbing
            // session, and the recovery gate took that session's back.
            let stretch = max(e.sets, athlete.experience == .beginner ? 3 : 5)
            let held = complement != nil && !sportMuscles.isDisjoint(with: loadedBuckets(p.movement.exerciseId))
            let ceiling = p.movement.protocolSets ?? (held ? e.sets : stretch)
            // Training order is read from the goal-neutral prescription: the
            // goal re-bands reps and RPE (endurance drops to RPE 6-7), and a
            // goal must change how a movement is dosed, never where it sits.
            let neutral = athlete.goal == .sportPerformance ? e
                : prescribe(p.movement, demand: p.demand, rule: rule, strategy: strategy, goal: .sportPerformance,
                            experience: athlete.experience, age: athlete.age, rampWeek: rampWeek)
            return Row(pick: p, exercise: e, maxSets: ceiling, fixedSets: p.movement.protocolSets != nil,
                       order: trainingOrder(p.demand, neutral),
                       uncapped: held && p.movement.protocolSets == nil ? stretch : nil)
        }
        var rows = picks.map(row)
        // The week's pressing (finding 11). `pushSets` is the share of upper
        // push sets this session owes: a legs-dominant week's floor
        // (SessionMix.pushFloor), or the range that puts a climber's week
        // between 1:2 and 1:1 push to pull. The floor goes to the pressing
        // rows, adding a press from the pool when the rows held cannot reach
        // it at their set ceilings, and fitting never trims below it. The
        // ceiling caps the presses, dropping the last of them while more
        // than three movements remain, and fitting adds no press past it.
        if pushFloor > 0 {
            while true {
                let pressing = rows.indices.filter { pushIds.contains(rows[$0].pick.movement.exerciseId) }
                if pressing.reduce(0, { $0 + rows[$1].maxSets }) >= pushFloor || pressing.count >= 3 {
                    var owed = pushFloor
                    for i in pressing { rows[i].floorSets = 0 }
                    while owed > 0, let i = pressing.filter({ rows[$0].floorSets < rows[$0].maxSets })
                        .min(by: { rows[$0].floorSets < rows[$1].floorSets }) {
                        rows[i].floorSets += 1
                        owed -= 1
                    }
                    for i in pressing { rows[i].exercise.sets = max(rows[i].exercise.sets, rows[i].floorSets) }
                    break
                }
                let taken = Set(rows.map(\.pick.movement.exerciseId))
                guard let press = pool
                    .filter({ pushIds.contains($0.exerciseId) && !taken.contains($0.exerciseId) && $0.serves(pushDemand) })
                    .sorted(by: {
                        let l = loadRank[$0.exerciseId] ?? 1, r = loadRank[$1.exerciseId] ?? 1
                        if l != r { return l < r }
                        return djb2("\(anchorSeed)-press-\($0.exerciseId)") < djb2("\(anchorSeed)-press-\($1.exerciseId)")
                    }).first
                else {
                    for i in pressing { rows[i].floorSets = rows[i].maxSets; rows[i].exercise.sets = rows[i].maxSets }
                    break
                }
                rows.append(row(Pick(movement: press, demand: pushDemand)))
            }
        }
        if pushCeiling < Int.max {
            func pressing() -> [Int] { rows.indices.filter { pushIds.contains(rows[$0].pick.movement.exerciseId) } }
            while pressing().count > pushCeiling, rows.count > 3, let last = pressing().last {
                rows.remove(at: last)
            }
            var left = pushCeiling
            var caps = Dictionary(uniqueKeysWithValues: pressing().map { ($0, 0) })
            while left > 0, let i = caps.keys.filter({ caps[$0]! < rows[$0].maxSets })
                .min(by: { caps[$0]! != caps[$1]! ? caps[$0]! < caps[$1]! : $0 < $1 }) {
                caps[i]! += 1
                left -= 1
            }
            for (i, cap) in caps {
                rows[i].uncapped = rows[i].uncapped ?? rows[i].maxSets
                rows[i].maxSets = max(1, cap)
                rows[i].exercise.sets = min(rows[i].exercise.sets, rows[i].maxSets)
            }
        }
        if let budget = athlete.preferredSessionMinutes {
            rows = fitToBudget(rows, budget: budget, rule: rule, lightened: lightened,
                               signature: signature,
                               extra: { current in
                                   let cost = current.reduce(0) { $0 + $1.pick.movement.fatigueCost }
                                   return backfillCandidates(current.map(\.pick))
                                       .first { cost + $0.movement.fatigueCost <= rule.sessionVolumeCap
                                           && (pushCeiling == Int.max || !pushIds.contains($0.movement.exerciseId))
                                           && !((athlete.season == .inSeason || athlete.season == .maintenance)
                                                && $0.movement.fatigueCost >= 5) }
                                       .map(row)
                               })
        }
        // Mesocycle deload, after fitting so the fit cannot pad it back.
        // Protocol sets stay as cited here and below.
        if cycle.state == .deload {
            for i in rows.indices where !rows[i].fixedSets {
                rows[i].exercise.sets = max(1, Int((Double(rows[i].exercise.sets) * deloadSetsFactor).rounded()))
            }
        }
        // The coach's intensity bias, clamped so a `push` can't run away and a
        // `deload` can't zero the movement out. Rounded away from 1 so the
        // bias always moves a two- or three-set row.
        let setsMul = strategy.intensityBias.setsMultiplier
        if setsMul != 1 {
            for i in rows.indices where !rows[i].fixedSets {
                let scaled = (Double(rows[i].exercise.sets) * setsMul).rounded(setsMul > 1 ? .up : .down)
                rows[i].exercise.sets = max(1, Int(scaled))
            }
        }
        picks = rows.map(\.pick)
        let orderKeys = rows.map(\.order)
        var exercises = rows.map(\.exercise)
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
        // A part-recovered prime mover that stayed in the session (its
        // demand had no other movement) caps at RPE 7.
        exercises = exercises.map { ex in
            guard soreIds.contains(ex.exerciseId) else { return ex }
            var e = ex
            e.rpe = e.rpe.map { capRPE($0, to: 7.0) } ?? "7"
            return e
        }
        // Training order (finding 5): explosive work first while fresh, then
        // the heavy compounds heaviest first, then the rest, then core and
        // prehab, then conditioning. Stable, so ties keep the pick order.
        let ordered = zip(picks, exercises).enumerated().sorted {
            let a = orderKeys[$0.offset], b = orderKeys[$1.offset]
            return a != b ? a < b : $0.offset < $1.offset
        }
        picks = ordered.map(\.element.0)
        exercises = ordered.map(\.element.1)
        return assemble(exercises, picks: picks, athlete: athlete, rule: rule,
                        sessionIndex: sessionIndex, lightened: lightened,
                        signatureUnavailable: signatureUnavailable,
                        complement: complement,
                        easedAreas: easedAreas(picks: picks, soreIds: soreIds, athlete: athlete),
                        skippedAreas: skippedAreas)
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
    /// coach.db `sport_movements.sport` for the complement pool.
    static let complementPoolSlug = "general-fitness"

    static func poolSlug(for sportSlug: String) -> String {
        SportProfile.of(sportSlug).poolSlug(for: sportSlug)
    }

    private static func filteredPool(_ athlete: AthleteState, phase: SeasonPhase,
                                     poolSport: String? = nil) -> [SportMovement] {
        // eventPrep draws from BOTH its own pool and the pre-season pool: for
        // skiing it's literally "pre-season tapered" (same movements); for
        // climbing it's antagonist-heavy, so its distinct event_prep-tagged
        // movements must surface alongside the sharp pre-season ones. Accepting
        // either tag covers both without duplicating phase tags across the seed.
        let raw = CoachDatabase.shared.sportMovements(sport: poolSport ?? poolSlug(for: athlete.sportSlug))
            .filter { m in
                let phaseOK = (phase == .eventPrep)
                    ? (m.allowed(in: .eventPrep) || m.allowed(in: .preSeason))
                    : m.allowed(in: phase)
                return phaseOK
                    && m.allowed(for: athlete.variant)
                    && m.minExperienceRank <= athlete.experience.seasonRank
                    && !athlete.contraindicatedExerciseIDs.contains(m.exerciseId)
                    // A dislike is a hard drop, unlike a sunk affinity (which
                    // only ranks last). No fallback: an emptied demand goes
                    // through the same shortfall backfill as any other.
                    && !athlete.isDisliked(m.name)
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
        SportProfile.of(sportSlug).signature
    }

    /// Sports the season engine generates for. The live Planner routes these to
    /// `generateSession`; everything else falls through to the legacy generator.
    static func supports(_ sportSlug: String?) -> Bool {
        guard let s = sportSlug else { return false }
        return SportProfile.of(s).usesSeasonEngine
    }

    /// Default variant until the variant picker lands (M4): ski → inbounds,
    /// climbing → sportRoute.
    static func defaultVariant(forSport sportSlug: String?) -> SportVariant {
        guard let s = sportSlug else { return .inbounds }
        if SportProfile.of(s).rules == .climbing { return .sportRoute }
        // A ski-mountaineering primary trained as a resort skier until 2026-11.
        return s == "ski-mountaineering" ? .skimo : .inbounds
    }

    /// Where this week sits in its mesocycle (T1-8). `weekNumber` is
    /// 1-indexed weeks into the phase, the same value the badge reads.
    static func cycleStatus(_ athlete: AthleteState) -> MesocycleProgression.Status {
        let daysUntilPeak = athlete.targetObjectiveDate.map {
            Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0
        }
        return MesocycleProgression.status(phase: athlete.season,
                                           weeksInPhase: athlete.weekNumber,
                                           daysUntilPeak: daysUntilPeak)
    }

    /// The one deload dose, for every sport (finding 9, 2026-11-10 audit).
    /// A deload week is the build week's session, same movements and RPE,
    /// at this share of its sets: the badge says "Volume -30%, intensity
    /// holds". It replaced re-resolving the session under the `.deload`
    /// progression with a cut fatigue cap, which removed 46% of a ski week's
    /// sets and 13% of a climbing week's because the cap bit differently on
    /// each pool. `.taper` and `.peak` are expressed by the eventPrep rule's
    /// own weights and cap, and `.deloadNextWeek` is a warning, not a dose.
    static let deloadSetsFactor = 0.7

    private static func targetMovementCount(_ rule: PhaseRule,
                                            preferredMinutes: Int? = nil) -> Int {
        // T2-7: honor the user's declared session length. The phase rule's
        // ceiling still bounds it (a 90-minute preference cannot inflate an
        // in-season taper past what the phase intends), but its floor no
        // longer does: a skier who has 30 minutes gets a 30-minute session,
        // where clamping up to the rule's 50-minute floor used to hand them
        // 44 to 56 (finding 4, 2026-11-10 audit).
        let ruleMinutes = rule.sessionMinutesTarget
        let minutes = preferredMinutes.map { min($0, ruleMinutes.upperBound) } ?? ruleMinutes.upperBound
        // ROUND, don't truncate (integer division once made every phase a
        // 4-movement session). The divisor is what `assemble` measures one
        // movement at, about 8 minutes; the 11 used before under-filled a
        // 75-minute budget to 28 minutes on average. `fitToBudget` settles
        // the remainder with sets.
        // The fatigue cap bounds it too: more slots than the cap can hold only
        // make `enforceFatigueCap` shed the heaviest movement, which in-season
        // is the max-strength lift the phase exists to keep.
        let capCount = max(4, Int(Double(rule.sessionVolumeCap) / 2.5))
        return max(3, min(7, capCount, Int((Double(minutes) / minutesPerMovement).rounded())))
    }

    /// Measured minutes per season-engine movement (sets x (rest + 40 s)).
    static let minutesPerMovement = 8.0

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

    /// 0 fresh, 1 recently picked, 2 rejected by the user's affinity. An
    /// anchor is never "recent": it is meant to repeat inside its block.
    static func rotationTier(_ m: SportMovement, _ athlete: AthleteState, anchor: Bool = false) -> Int {
        if isRejected(m, athlete) { return 2 }
        return !anchor && athlete.recentMovementIDs.contains(m.exerciseId) ? 1 : 0
    }

    static let pushPatterns: Set<String> = ["horizontal-push", "vertical-push"]

    /// Demands prescribed as loaded strength work (3 to 5 sets at RPE 7-8).
    static let strengthDemands: Set<Demand> = [
        .maxStrength, .upperStrength, .pullStrength, .legStrength, .upperPush, .upperPull,
    ]

    /// Equipment that puts load on a movement, or (bar, dip station, rings)
    /// makes bodyweight a full strength load.
    static let loadingEquipment: Set<String> = [
        "barbell", "dumbbells", "kettlebell", "cable-machine", "landmine", "weight-plates",
        "sandbag", "smith-machine", "leg-press", "hack-squat", "belt-squat", "leg-curl-machine",
        "leg-extension", "lat-pulldown", "cable-crossover", "chest-press-machine",
        "shoulder-press-machine", "hip-ad-ab-machine", "pull-up-bar", "dip-station",
        "gymnastic-rings", "weight-vest",
    ]

    /// 0 loadable, 1 bodyweight, 2 a regression: a "(Knees)" variant or any
    /// movement that needs a band.
    static func loadRank(_ m: SportMovement, required: Set<String>) -> Int {
        if m.name.localizedCaseInsensitiveContains("(knees)")
            || required.contains(where: { $0.hasPrefix("band-") || $0 == "mini-band" }) { return 2 }
        return required.isDisjoint(with: loadingEquipment) ? 1 : 0
    }

    /// Demands whose heavy picks may hold at most one bilateral squat.
    static let heavyLegDemands: Set<Demand> = [.maxStrength, .eccentricLeg, .legStrength]

    /// Sort key for a session's rows: explosive (tempo X) 0; a compound at
    /// RPE 7+ is 1, ordered by its low rep count so the heaviest lift leads;
    /// other strength and accessory work 2; core and prehab 3; conditioning 4.
    private static func trainingOrder(_ demand: Demand, _ e: GeneratedExercise) -> (Int, Int) {
        if e.tempo?.uppercased().contains("X") == true { return (0, 0) }
        if demand == .aerobicUphill { return (4, 0) }
        if demand == .core || demand == .prehab { return (3, 0) }
        let rpeLow = Int(e.rpe?.prefix { $0.isNumber } ?? "") ?? 0
        if e.isCompound, rpeLow >= 7, let reps = Int(e.reps.prefix { $0.isNumber }) {
            return (1, reps)
        }
        return (2, 0)
    }

    /// Demands whose pick is the session's anchor lift: the loaded strength,
    /// power and finger work a block progresses. Everything else is an
    /// accessory and rotates week to week.
    static let anchorDemands: Set<Demand> = [
        .maxStrength, .upperStrength, .pullStrength, .legStrength, .upperPush, .upperPull,
        .eccentricLeg, .fingerStrength, .contactStrength, .power,
    ]

    static func isRejected(_ m: SportMovement, _ athlete: AthleteState) -> Bool {
        athlete.affinity(for: m.name) <= AthleteState.affinitySinkThreshold
    }

    /// Ids of the pool movements whose primary muscle is in `buckets`.
    private static func movementIds(in pool: [SportMovement], loading buckets: Set<String>) -> Set<Int> {
        guard !buckets.isEmpty else { return [] }
        return Set(pool.filter {
            !WorkoutGenerator.primaryMuscleBuckets(exerciseId: $0.exerciseId).isDisjoint(with: buckets)
        }.map(\.exerciseId))
    }

    /// Sore areas the session actually had to work around: a demand with no
    /// other movement kept a sore prime mover, or the tier moved one out. The
    /// session summary names these so the user sees why the workout changed.
    private static func easedAreas(picks: [Pick], soreIds: Set<Int>, athlete: AthleteState) -> [String] {
        guard !athlete.easedBuckets.isEmpty else { return [] }
        let kept = picks.filter { soreIds.contains($0.movement.exerciseId) }
            .reduce(into: Set<String>()) {
                $0.formUnion(WorkoutGenerator.primaryMuscleBuckets(exerciseId: $1.movement.exerciseId))
            }
        let areas = kept.isEmpty ? athlete.easedBuckets : kept.intersection(athlete.easedBuckets)
        return MuscleBucket.allCases.map(\.rawValue).filter(areas.contains)
    }

    private static func djb2(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }

    // MARK: - Fatigue cap

    private struct Pick { let movement: SportMovement; let demand: Demand }

    /// A pick with its prescription, carried together so the session's
    /// provenance (demand list) stays aligned with its exercise rows through
    /// fitting and ordering.
    private struct Row {
        let pick: Pick
        var exercise: GeneratedExercise
        /// Most sets the fitting pass may raise this row to.
        var maxSets: Int
        /// A cited protocol's sets, which fitting never moves.
        let fixedSets: Bool
        /// Sort key for training order (`trainingOrder`).
        let order: (Int, Int)
        /// Sets this row holds toward the week's push floor; fitting never
        /// trims below them.
        var floorSets = 0
        /// The ceiling a push cap or a held sport muscle replaced, given
        /// back when the session cannot otherwise reach its length floor.
        var uncapped: Int? = nil
    }

    /// Buckets a movement loads as a prime mover or a secondary one, the
    /// two roles `MuscleFreshness` charges.
    static func loadedBuckets(_ exerciseId: Int) -> Set<String> {
        Set(CoachDatabase.shared.musclesForExercise(exerciseId)
            .filter { $0.role == "primary" || $0.role == "secondary" }
            .compactMap { MuscleBucket.bucket(forSlug: $0.slug)?.rawValue })
    }

    /// Minutes one row costs: work plus rest per set. The one estimator, used
    /// by `assemble` for `estimatedMinutes` and by `fitToBudget`.
    static func minutes(_ e: GeneratedExercise) -> Int {
        Int(ceil(Double(e.sets) * (Double(e.restSeconds) + 40) / 60))
    }

    // MARK: - Session length

    /// Fit a session to the athlete's declared minutes (finding 4 of the
    /// 2026-11-10 generator audit: a 75-minute budget averaged 28 minutes and
    /// a 30-minute ski session ran 44 to 56).
    ///
    /// The session is sized to `min(budget, phase ceiling)`: the phase's
    /// `sessionMinutesTarget` still caps what a long budget can buy (T2-7), so
    /// an in-season or deload session at a 75-minute budget stays a
    /// 45-minute one.
    ///
    /// Over the budget: take sets off the row with the most, down to two, then
    /// drop the last non-signature movement while more than three remain, then
    /// go to one set. Under the goal (85% of that size, or its 60% floor for a
    /// lightened sport-adjacent session, so it stays the shorter of the two):
    /// raise sets first, fewest-set row first, up to each row's ceiling; only
    /// when no row can rise add a movement, inside the phase's fatigue cap.
    /// Nothing is raised or added past the budget itself.
    private static func fitToBudget(_ input: [Row], budget: Int, rule: PhaseRule,
                                    lightened: Bool, signature: Demand?,
                                    extra: ([Row]) -> Row?) -> [Row] {
        var rows = input
        guard !rows.isEmpty, budget > 0 else { return rows }
        func total() -> Int { rows.reduce(0) { $0 + minutes($1.exercise) } }
        let size = Double(min(budget, rule.sessionMinutesTarget.upperBound))
        let floor = Int((0.6 * size).rounded(.up))
        let goal = lightened ? floor : max(floor, Int((0.85 * size).rounded()))

        func trimOneSet(floorSets: Int) -> Bool {
            guard let i = rows.indices
                .filter({ !rows[$0].fixedSets && rows[$0].exercise.sets > max(floorSets, rows[$0].floorSets) })
                .max(by: { rows[$0].exercise.sets != rows[$1].exercise.sets
                    ? rows[$0].exercise.sets < rows[$1].exercise.sets : $0 < $1 })
            else { return false }
            rows[i].exercise.sets -= 1
            return true
        }
        func dropOne() -> Bool {
            guard rows.count > 3 else { return false }
            let sigCount = signature.map { s in rows.filter { $0.pick.demand == s }.count } ?? 0
            guard let i = rows.indices.reversed().first(where: {
                rows[$0].floorSets == 0 && (rows[$0].pick.demand != signature || sigCount > 1)
            }) else { return false }
            rows.remove(at: i)
            return true
        }
        while total() > budget {
            if trimOneSet(floorSets: 2) || dropOne() || trimOneSet(floorSets: 1) { continue }
            break
        }

        func raiseOneSet() -> Bool {
            let room = budget - total()
            guard let i = rows.indices
                .filter({ i in
                    var e = rows[i].exercise
                    guard !rows[i].fixedSets, e.sets < rows[i].maxSets else { return false }
                    let before = minutes(e)
                    e.sets += 1
                    return minutes(e) - before <= room
                })
                .min(by: { rows[$0].exercise.sets < rows[$1].exercise.sets })
            else { return false }
            rows[i].exercise.sets += 1
            return true
        }
        while total() < goal {
            if raiseOneSet() { continue }
            guard rows.count < 8, let more = extra(rows),
                  total() + minutes(more.exercise) <= budget else { break }
            rows.append(more)
        }
        // Length outranks the push cap and the held sport muscles: a session
        // still under its floor raises those rows to their own ceilings.
        if total() < floor {
            for i in rows.indices { if let c = rows[i].uncapped { rows[i].maxSets = c } }
            while total() < floor, raiseOneSet() {}
        }
        return rows
    }

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
                                  strategy: GeneratorStrategy = .auto,
                                  goal: TrainingGoal = .sportPerformance,
                                  experience: ExperienceLevel = .intermediate,
                                  age: Int? = nil,
                                  rampWeek: Int? = nil) -> GeneratedExercise {
        let mainLifts: Set<Demand> = [.maxStrength, .upperStrength, .pullStrength, .legStrength]
        var scheme = DemandScheme.scheme(for: demand, progression: rule.progression, goal: goal)
            .adjusted(experience: experience, age: age,
                      mainLift: mainLifts.contains(demand) && rule.progression == .progressiveOverload)
        if let w = rampWeek, anchorDemands.contains(demand) { scheme = scheme.ramped(weekOfCycle: w) }
        let key = m.name.lowercased()
        // A movement carrying a cited protocol (R3-9) keeps its own sets, reps
        // and rest: the no-hang finger pull is 5 sets of 3 to 4 three-second
        // pulls and was being served as 5x8s holds from the fingerStrength
        // scheme. The strategy's set multiplier lands after `fitToBudget`,
        // like readiness, so a coach's push or deload survives the fitting.
        let sets = m.protocolSets ?? scheme.setsMid
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
            reps: m.protocolReps ?? scheme.reps(forCatalog: m.catalogReps),
            restSeconds: m.protocolRestSeconds ?? scheme.restSeconds,
            notes: notes.isEmpty ? nil : notes,
            rpe: strategy.rpeOverrides[key] ?? scheme.rpeString,
            tempo: strategy.tempoOverrides[key] ?? scheme.tempoString,
            source: .recipe)
    }

    /// Short, human label for a session title. Prefers the catalog's own name
    /// so a new sport needs no change here.
    // MARK: - Assembly

    private static func assemble(_ exercises: [GeneratedExercise], picks: [Pick],
                                 athlete: AthleteState, rule: PhaseRule,
                                 sessionIndex: Int, lightened: Bool,
                                 signatureUnavailable: Bool = false,
                                 complement: ComplementSlot? = nil,
                                 easedAreas: [String] = [],
                                 skippedAreas: [String] = []) -> GeneratedWorkout {
        let minutes = exercises.reduce(0) { $0 + Self.minutes($1) }
        let demandMix = picks.map { $0.demand.rawValue }
        // No sport name: Today's caption already says it, and
        // "Skiing / Snowboarding · Pre-season — Session 4" ran to three lines
        // of displayL and clipped in the title wheel. The season stays so
        // wheel stops sampled from other seasons read apart. Also keep focus
        // words ("push", "leg", ...) out: PlanValidator.resolveFocus infers
        // focus from title text.
        let title = complement?.title ?? "\(athlete.season.label) · Session \(sessionIndex + 1)"
        var summary = "\(exercises.count) movements · ~\(minutes) min"
        if signatureUnavailable, let sig = signatureDemand(athlete.sportSlug) {
            summary += " · no \(sig.plainLabel) work: your injuries rule out every option"
        }
        if !skippedAreas.isEmpty {
            let names = skippedAreas.compactMap { MuscleBucket(rawValue: $0)?.label.lowercased() }
            summary += " · no \(ListFormatter.localizedString(byJoining: names)) work, still recovering"
        }
        if !easedAreas.isEmpty {
            let names = easedAreas.compactMap { MuscleBucket(rawValue: $0)?.label.lowercased() }
            summary += " · eased for sore \(ListFormatter.localizedString(byJoining: names))"
        }
        var prov = complement.map { "complement · \($0.focus.rawValue) · \(rule.objective)" }
            ?? "\(athlete.sportSlug) · \(athlete.variant.rawValue) · \(rule.objective)"
        if lightened { prov += " · lightened (sport day adjacent)" }
        prov += " · demands: \(demandMix.joined(separator: "/"))"
        // A real WorkoutFocus (not nil) so downstream consolidation / split
        // analytics / LLM-refinement anchoring keep working. Season sessions are
        // whole-body by construction → fullBodyA.
        var workout = GeneratedWorkout(
            title: title, summary: summary, exercises: exercises,
            estimatedMinutes: minutes, provenance: prov,
            focus: complement?.focus.workoutFocus ?? .fullBodyA)
        if !athlete.easedBuckets.isEmpty {
            workout.soreAreas = MuscleBucket.allCases.map(\.rawValue).filter(athlete.easedBuckets.contains)
        }
        if !athlete.blockedBuckets.isEmpty {
            workout.blockedAreas = MuscleBucket.allCases.map(\.rawValue).filter(athlete.blockedBuckets.contains)
        }
        workout.skippedAreas = skippedAreas.isEmpty ? nil : skippedAreas
        return workout
    }
}
