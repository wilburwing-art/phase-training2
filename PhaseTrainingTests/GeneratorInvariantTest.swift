// GeneratorInvariantTest — the axis-2 / axis-3 complement to
// GeneratorSweepReportTest. The sweep answers "is each knob WIRED" (sensitivity):
// it can only tell you output MOVED, never that the move was correct, and OFAT
// can't see interactions. This file attacks both gaps with two oracle-free
// techniques that need no LLM grader and run deterministically in CI:
//
//   Part A — PROPERTY / INVARIANT assertions over a deterministic input GRID.
//     Fuzzing the whole input vector at once (not one knob at a time) is the
//     only cheap attack on OFAT's interaction blind spot: every cell is a
//     distinct (experience × focus × equipment × age × minutes) combination and
//     the invariants must hold in ALL of them.
//
//   Part B — METAMORPHIC relations. When you have no ground-truth "correct"
//     workout, you can still assert ORDERINGS between two outputs: more
//     readiness ⇒ volume non-decreasing, deload ≤ normal ≤ push, shorter budget
//     never adds work. These encode the sweep's informal "expected direction"
//     rubric as automated gates instead of a human eyeballing amber cells.
//
// Same isolation discipline as the sweep: a FIXED seed across every comparison
// so a delta is attributable to the input, not to the deterministic pick landing
// elsewhere. (Math.random is unavailable here; the grid is enumerated, not
// sampled — deterministic fuzz.)

import XCTest
@testable import PhaseTraining

final class GeneratorInvariantTest: XCTestCase {

    private let seed = "gen-invariant-1"

    // MARK: - Fixtures

    /// Baseline control, knobs overridable per grid cell. Mirrors
    /// GeneratorSweepReportTest.controlMemory so the two harnesses agree on what
    /// "baseline" means.
    private func mem(
        experience: ExperienceLevel = .intermediate,
        focus: PrimaryFocus = .hypertrophy,
        equipment: [Equipment] = [.fullGym],
        age: Int = 32,
        minutes: Int = 60,
        days: Int = 3
    ) -> TrainingMemory {
        var m = TrainingMemory()
        m.experience = experience
        m.focuses = [focus]
        m.equipment = equipment
        m.sessionMinutes = minutes
        m.liftDaysPerWeek = days
        m.age = age
        m.gender = .male
        return m
    }

    private func week(_ m: TrainingMemory,
                      _ c: GeneratorContext = .empty,
                      _ s: GeneratorStrategy = .auto) -> [GeneratedWorkout] {
        let profile = DemographicProfile.from(m)
        let days = max(0, min(7, m.liftDaysPerWeek))
        return (0..<days).map { i in
            WorkoutGenerator.generateLift(
                liftIndex: i, totalLifts: days, memory: m, profile: profile,
                hashSeed: seed, recentlyPicked: [], context: c, strategy: s)
        }
    }

    private func totalSets(_ w: [GeneratedWorkout]) -> Int {
        w.flatMap { $0.exercises }.reduce(0) { $0 + $1.sets }
    }
    private func movementCount(_ w: [GeneratedWorkout]) -> Int {
        w.reduce(0) { $0 + $1.exercises.count }
    }
    private func totalEstMin(_ w: [GeneratedWorkout]) -> Int {
        w.reduce(0) { $0 + $1.estimatedMinutes }
    }

    // MARK: - Part A: hard invariants over a fuzz grid

    /// Every (experience × focus × equipment × age × minutes) combination must
    /// satisfy the structural invariants. A failure here is a real bug surfaced
    /// in a corner OFAT never visits — e.g. the advanced-isolation set count is
    /// uncapped in `prescription` and only the [1,8] clamp saves it.
    func test_invariants_hold_across_input_grid() throws {
        let equipmentSets: [[Equipment]] = [
            [.fullGym], [.bodyweight], [.dumbbells, .bands, .pullUpBar],
        ]
        var cells = 0
        for experience in [ExperienceLevel.beginner, .intermediate, .advanced] {
            for focus in PrimaryFocus.allCases {
                for equipment in equipmentSets {
                    for age in [18, 32, 70] {
                        for minutes in [20, 60, 120] {
                            cells += 1
                            let m = mem(experience: experience, focus: focus,
                                        equipment: equipment, age: age, minutes: minutes)
                            let w = week(m)
                            let where_ = "exp=\(experience) focus=\(focus.rawValue) "
                                + "equip=\(equipment.map { "\($0)" }.joined(separator: "+")) "
                                + "age=\(age) min=\(minutes)"

                            for day in w {
                                XCTAssertFalse(day.exercises.isEmpty,
                                    "empty day [\(where_)] — graceful-degradation floor failed to backfill")
                                XCTAssertGreaterThanOrEqual(day.estimatedMinutes, 1,
                                    "estMin < 1 [\(where_)]")

                                // No exercise repeats within a day (pickedIds gate).
                                let ids = day.exercises.map { $0.exerciseId }
                                XCTAssertEqual(Set(ids).count, ids.count,
                                    "duplicate exercise within a day [\(where_)]")

                                for ex in day.exercises {
                                    XCTAssertTrue((1...8).contains(ex.sets),
                                        "sets \(ex.sets) out of [1,8] for \(ex.name) [\(where_)]")
                                    XCTAssertGreaterThanOrEqual(ex.restSeconds, 0,
                                        "negative rest for \(ex.name) [\(where_)]")
                                    XCTAssertFalse(
                                        ex.reps.trimmingCharacters(in: .whitespaces).isEmpty,
                                        "empty reps for \(ex.name) [\(where_)]")
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(cells, 100, "grid collapsed — check the loop bounds")
    }

    /// A disliked keyword must never appear in any picked exercise name, in ANY
    /// grid cell. Output-only assertion (no catalog join), fuzzed over the grid.
    func test_dislike_keyword_never_appears() throws {
        for kw in ["barbell", "machine"] {
            for experience in [ExperienceLevel.intermediate, .advanced] {
                for focus in PrimaryFocus.allCases {
                    var m = mem(experience: experience, focus: focus)
                    m.dislikes = [kw]
                    for day in week(m) {
                        for ex in day.exercises {
                            XCTAssertFalse(ex.name.lowercased().contains(kw),
                                "disliked '\(kw)' leaked: \(ex.name) [exp=\(experience) focus=\(focus.rawValue)]")
                        }
                    }
                }
            }
        }
    }

    /// A contraindicated exercise must NEVER appear for a user carrying that
    /// injury. Output-only assertion is impossible (the contra set lives in
    /// coach.db), so we cross-check against the SAME table the generator filters
    /// on (`exercise_injury_relevance`) as an independent oracle — and prove the
    /// probe is non-vacuous by a DIFFERENTIAL: without the injury those exact ids
    /// DO get picked, so their absence WITH the injury is the filter working, not
    /// an empty pool. (The false-confidence trap this guards: a vacuous green.)
    func test_invariant_no_contraindicated_exercise_for_injury() throws {
        try XCTSkipUnless(CoachDatabase.shared.isOpen, "coach.db not open — can't probe contraindications")
        let probeSeeds = ["gen-invariant-1", "gen-invariant-2", "gen-invariant-3"]

        // Set of contra'd ids that actually surface in a focus×seed sweep.
        func contraHits(injury slug: String?, contra: Set<Int>) -> Set<Int> {
            var hits: Set<Int> = []
            for focus in PrimaryFocus.allCases {
                var m = mem(focus: focus)
                if let slug { m.userInjuries = [UserInjury(slug: slug)] }
                let profile = DemographicProfile.from(m)
                let days = max(0, min(7, m.liftDaysPerWeek))
                for s in probeSeeds {
                    for i in 0..<days {
                        let w = WorkoutGenerator.generateLift(
                            liftIndex: i, totalLifts: days, memory: m, profile: profile,
                            hashSeed: s, recentlyPicked: [], context: .empty, strategy: .auto)
                        for ex in w.exercises where contra.contains(ex.exerciseId) { hits.insert(ex.exerciseId) }
                    }
                }
            }
            return hits
        }

        // lumbar-disc-herniation has the densest contra list — a real differential.
        let denseSlug = "lumbar-disc-herniation"
        let contra = CoachDatabase.shared.contraindicatedExerciseIds(forInjurySlugs: [denseSlug])
        XCTAssertFalse(contra.isEmpty, "no contraindications tagged for \(denseSlug) — DB probe is vacuous")
        XCTAssertTrue(contraHits(injury: denseSlug, contra: contra).isEmpty,
            "contraindicated exercise generated for \(denseSlug)")
        XCTAssertFalse(contraHits(injury: nil, contra: contra).isEmpty,
            "no contra'd ex for \(denseSlug) appears even WITHOUT the injury — "
            + "differential can't prove the filter (sparse pool); pick a denser probe")

        // rotator-cuff-injury is known-sparse (sweep flagged it) — safety-only,
        // no differential requirement.
        let sparseSlug = "rotator-cuff-injury"
        let contraS = CoachDatabase.shared.contraindicatedExerciseIds(forInjurySlugs: [sparseSlug])
        XCTAssertFalse(contraS.isEmpty, "no contraindications tagged for \(sparseSlug)")
        XCTAssertTrue(contraHits(injury: sparseSlug, contra: contraS).isEmpty,
            "contraindicated exercise generated for \(sparseSlug)")
    }

    // MARK: - Part B: metamorphic orderings (oracle-free direction checks)

    /// deload (×0.7) ≤ normal (×1.0) ≤ push (×1.15) in total weekly sets.
    func test_metamorphic_intensityBias_monotone_volume() throws {
        let m = mem()
        func sets(_ bias: GeneratorStrategy.IntensityBias) -> Int {
            var s = GeneratorStrategy.auto; s.intensityBias = bias
            return totalSets(week(m, .empty, s))
        }
        let deload = sets(.deload), normal = sets(.normal), push = sets(.push)
        XCTAssertLessThanOrEqual(deload, normal, "deload added volume vs normal (\(deload) > \(normal))")
        XCTAssertLessThanOrEqual(normal, push, "push removed volume vs normal (\(push) < \(normal))")
    }

    /// Higher readiness ⇒ volume non-decreasing (lerp 0.6→1.0), gated on
    /// hasReadinessData. Equal scores must produce equal volume.
    func test_metamorphic_readiness_monotone_volume() throws {
        let m = mem()
        func sets(_ score: Double) -> Int {
            var c = GeneratorContext.empty; c.readinessScore = score; c.hasReadinessData = true
            return totalSets(week(m, c, .auto))
        }
        let lo = sets(0.0), mid = sets(0.5), hi = sets(1.0)
        XCTAssertLessThanOrEqual(lo, mid, "0.0 readiness gave more volume than 0.5 (\(lo) > \(mid))")
        XCTAssertLessThanOrEqual(mid, hi, "0.5 readiness gave more volume than 1.0 (\(mid) > \(hi))")
    }

    /// More experience ⇒ volume non-decreasing (beginner ≤3, intermediate ≤4,
    /// advanced compound +1). Held at normal intensity, no readiness scaling.
    /// CAVEAT: unlike intensityBias/readiness/age (which scale sets but never
    /// change WHICH exercises are picked), experience CAN change selection —
    /// beginners are excluded from advanced staples (WG:544). So this ordering
    /// also assumes stable compound/isolation composition across levels; a future
    /// catalog change that flips a slot's role between levels could break it.
    func test_metamorphic_experience_monotone_volume() throws {
        func sets(_ e: ExperienceLevel) -> Int { totalSets(week(mem(experience: e))) }
        let beg = sets(.beginner), inter = sets(.intermediate), adv = sets(.advanced)
        XCTAssertLessThanOrEqual(beg, inter, "beginner outvolumed intermediate (\(beg) > \(inter))")
        XCTAssertLessThanOrEqual(inter, adv, "intermediate outvolumed advanced (\(inter) > \(adv))")
    }

    /// age ≥ 55 drops one work set per exercise (floored at 1) ⇒ an older
    /// lifter's total volume is ≤ a younger lifter's, all else equal.
    func test_metamorphic_age55_drops_volume() throws {
        let young = totalSets(week(mem(age: 32)))
        let old = totalSets(week(mem(age: 70)))
        XCTAssertLessThanOrEqual(old, young, "age-70 volume \(old) exceeded age-32 \(young)")
    }

    /// Shorter session budget never ADDS work: as minutes fall, both movement
    /// count and estimated minutes are non-increasing. Uses a hypertrophy push
    /// day (has droppable accessory slots) so the budget gate actually bites.
    func test_metamorphic_shorter_budget_never_adds() throws {
        func plan(_ minutes: Int) -> (count: Int, est: Int) {
            var s = GeneratorStrategy.auto; s.focus = .push
            let w = week(mem(focus: .hypertrophy, minutes: minutes), .empty, s)
            return (movementCount(w), totalEstMin(w))
        }
        let ladder = [20, 30, 45, 60, 90].map(plan)
        for i in 1..<ladder.count {
            XCTAssertLessThanOrEqual(ladder[i - 1].count, ladder[i].count,
                "fewer minutes produced MORE movements at step \(i): \(ladder)")
            XCTAssertLessThanOrEqual(ladder[i - 1].est, ladder[i].est,
                "fewer minutes produced MORE est-min at step \(i): \(ladder)")
        }
    }

    // MARK: - Part C: named pairwise interactions (the sweep's open #3)
    // OFAT moves readiness and intensityBias on SEPARATE axes, so it can never
    // see them stack. These cells exercise the corners where two regulators
    // compound — the class of bug the sweep is structurally blind to.

    /// readiness × deload: the two set-suppressors multiply (×0.6 × ×0.7 = ×0.42
    /// at the worst corner). The floor must still hold (no zero-set exercise),
    /// and stacking a second suppressor must never ADD volume vs either alone.
    func test_interaction_readiness_x_deload_floors_and_monotone() throws {
        let m = mem()
        func setsList(readiness: Double?, bias: GeneratorStrategy.IntensityBias) -> [Int] {
            var c = GeneratorContext.empty
            if let r = readiness { c.readinessScore = r; c.hasReadinessData = true }
            var s = GeneratorStrategy.auto; s.intensityBias = bias
            return week(m, c, s).flatMap { $0.exercises.map(\.sets) }
        }
        let stacked = setsList(readiness: 0.0, bias: .deload)   // ×0.42
        XCTAssertFalse(stacked.isEmpty, "no exercises generated under readiness×deload")
        XCTAssertTrue(stacked.allSatisfy { $0 >= 1 },
            "set count floored below 1 under readiness×deload stacking: \(stacked)")
        let total: ([Int]) -> Int = { $0.reduce(0, +) }
        let readinessOnly = total(setsList(readiness: 0.0, bias: .normal))   // ×0.6
        let deloadOnly = total(setsList(readiness: 1.0, bias: .deload))      // ×0.7
        let both = total(stacked)
        XCTAssertLessThanOrEqual(both, readinessOnly,
            "deload stacked onto low readiness ADDED volume (\(both) > \(readinessOnly))")
        XCTAssertLessThanOrEqual(both, deloadOnly,
            "low readiness stacked onto deload ADDED volume (\(both) > \(deloadOnly))")
    }

    /// soreness × focus: when the sore areas ARE the day's prime movers, the
    /// pick-time sore-area exclusion strips the focus's main candidates — the
    /// worst case for the picker. Two assertions: (1) the day still produces work
    /// (graceful degradation, doesn't collapse to empty), and (2) the exclusion
    /// actually FIRED. A non-empty-only check would pass even if `recentSoreAreas`
    /// were dead (the H11 builder/consumer-drift class this harness exists to
    /// catch), so diff the picks against the healthy day to prove interaction.
    func test_interaction_soreness_x_focus_excludes_and_degrades() throws {
        var s = GeneratorStrategy.auto; s.focus = .push
        let m = mem(focus: .hypertrophy)
        let healthy = week(m, .empty, s)
        var c = GeneratorContext.empty
        c.recentSoreAreas = ["chest", "shoulders", "triceps"]   // == push prime movers
        let sore = week(m, c, s)

        for day in sore {
            XCTAssertFalse(day.exercises.isEmpty,
                "push day collapsed to empty when all its prime movers were sore-excluded")
        }
        let healthyIds = Set(healthy.flatMap { $0.exercises.map(\.exerciseId) })
        let soreIds = Set(sore.flatMap { $0.exercises.map(\.exerciseId) })
        XCTAssertNotEqual(healthyIds, soreIds,
            "sore push week picked the SAME exercises as healthy — recentSoreAreas exclusion did not fire")
    }
}
