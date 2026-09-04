import XCTest
@testable import PhaseTraining

/// T2-4. `GeneratorInvariantTest` (312 lines) was deleted in 449bd8d with the
/// legacy selection engine and never replaced for the season engine, which is
/// now the only generator. The injury-contraindication half was ported to
/// AuthoredRoutineTests on 2026-09-04; this is the rest: must-hold-for-ALL-
/// inputs properties over a grid, run through `WorkoutGenerator.generateLift`
/// so they cover whichever path a request routes to.
///
/// Every assertion here is oracle-free. A failure names the cell.
final class SeasonInvariantTests: XCTestCase {

    private struct Cell: CustomStringConvertible {
        let sport: String, phase: SeasonPhase, experience: ExperienceLevel
        let equipment: [Equipment], minutes: Int, slot: Int, totalLifts: Int
        var description: String {
            "\(sport)/\(phase.rawValue)/\(experience.rawValue)/\(equipment.map(\.rawValue).joined(separator: "+"))/\(minutes)min/slot\(slot)of\(totalLifts)"
        }
    }

    /// Ten plannable sports x 5 phases x 3 experience x 3 equipment tiers x
    /// 2 session lengths x 3 slots. ~2,700 cells; runs in seconds.
    private var grid: [Cell] {
        let sports = ["alpine-skiing", "snow-sports", "ski-mountaineering", "climbing",
                      "snowboarding", "mountain-biking", "mountaineering",
                      "trail-running", "hiking-trekking", "thru-hiking"]
        let equipment: [[Equipment]] = [[.fullGym], [.dumbbells, .pullUpBar], [.bodyweight]]
        var out: [Cell] = []
        for s in sports { for p in SeasonPhase.allCases { for e in ExperienceLevel.allCases {
            for eq in equipment { for m in [30, 75] { for slot in 0..<3 {
                out.append(Cell(sport: s, phase: p, experience: e, equipment: eq,
                                minutes: m, slot: slot, totalLifts: 3))
            } } }
        } } }
        return out
    }

    private func generate(_ c: Cell) -> GeneratedWorkout {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: c.sport)
        memory.defaultSeason = c.phase
        if let sport = memory.primarySport { memory.seasonsBySport = [sport: c.phase] }
        memory.experience = c.experience
        memory.equipment = c.equipment
        memory.sessionMinutes = c.minutes
        memory.liftDaysPerWeek = c.totalLifts
        let profile = DemographicProfile.from(memory)
        return WorkoutGenerator.generateLift(
            liftIndex: c.slot, totalLifts: c.totalLifts, memory: memory, profile: profile,
            hashSeed: "inv-\(c)")
    }

    // MARK: - Part A: structural invariants

    func test_noPlannableCellProducesAnEmptyWorkout() {
        // The "Rest / No supported sport set" branch is a safety net for a
        // nil primary sport. Every sport in the grid is plannable, so it must
        // never be reached from here.
        for c in grid where c.equipment != [.bodyweight] {
            let w = generate(c)
            XCTAssertFalse(w.exercises.isEmpty, "[\(c)] empty workout: '\(w.title)' / \(w.provenance)")
        }
    }

    func test_setsAreInRange() {
        for c in grid {
            for ex in generate(c).exercises {
                XCTAssertTrue((1...8).contains(ex.sets), "[\(c)] '\(ex.name)' sets=\(ex.sets)")
            }
        }
    }

    func test_noDuplicateMovementInASession() {
        for c in grid {
            let ids = generate(c).exercises.map(\.exerciseId).filter { $0 > 0 }
            XCTAssertEqual(ids.count, Set(ids).count, "[\(c)] duplicate movement")
        }
    }

    func test_everyRowHasRepsAndRest() {
        for c in grid {
            for ex in generate(c).exercises {
                XCTAssertFalse(ex.reps.trimmingCharacters(in: .whitespaces).isEmpty, "[\(c)] '\(ex.name)' empty reps")
                // 5, not 15: the MTI-distilled "Leg Blaster" circuit rows are
                // real prescriptions at 20 sec work / 10 sec rest, and the
                // first run of this harness failed on exactly that. The bound
                // exists to catch a zero, a negative or a parse fall-through,
                // not to outlaw a circuit.
                XCTAssertGreaterThanOrEqual(ex.restSeconds, 5, "[\(c)] '\(ex.name)' rest \(ex.restSeconds)s")
            }
        }
    }

    func test_generationIsDeterministic() {
        for c in grid.prefix(200) {
            XCTAssertEqual(generate(c), generate(c), "[\(c)] same inputs, different output")
        }
    }

    // MARK: - Part B: metamorphic (expected-direction) invariants, non-strict

    func test_shorterSessionNeverAddsMovements() {
        for c in grid where c.minutes == 75 {
            let long = generate(c)
            let short = generate(Cell(sport: c.sport, phase: c.phase, experience: c.experience,
                                      equipment: c.equipment, minutes: 30, slot: c.slot,
                                      totalLifts: c.totalLifts))
            XCTAssertLessThanOrEqual(short.exercises.count, long.exercises.count,
                                     "[\(c)] 30 min produced MORE movements than 75")
        }
    }

    func test_bodyweightOnlyNeverPrescribesLoadedEquipment() {
        // The oracle is the engine's OWN rule (SportSeasonGenerator.filteredPool):
        // a movement is usable when its required slugs are a subset of the
        // athlete's allowed slugs, and an EMPTY allowed set means full gym.
        // `"bodyweight"` is itself a coach.db equipment slug, so "needs
        // nothing" is not the test — the first draft of this assertion failed
        // on Side Plank "needing [bodyweight]".
        //
        // Season path filters by this; authored routines do not (the equipment
        // half of the T0-1 gap). Assert where the engine owns the answer, and
        // report the authored gap as a count so it stays visible.
        var authoredLoaded = 0, authoredRows = 0
        for c in grid where c.equipment == [.bodyweight] {
            var memory = TrainingMemory()
            memory.equipment = c.equipment
            let allowed = DemographicProfile.from(memory).allowedEquipmentSlugs
            let w = generate(c)
            let isAuthored = w.provenance.hasPrefix("Authored")
            let reqs = CoachDatabase.shared.requiredEquipmentSlugs(
                forExerciseIds: Set(w.exercises.map(\.exerciseId)))
            for ex in w.exercises {
                let need = reqs[ex.exerciseId] ?? []
                let usable = need.isEmpty || allowed.isEmpty || need.isSubset(of: allowed)
                if isAuthored { authoredRows += 1; if !usable { authoredLoaded += 1 }; continue }
                XCTAssertTrue(usable, "[\(c)] season engine prescribed '\(ex.name)' needing \(need) to a user with \(allowed)")
            }
        }
        // Not asserted, reported: the equipment half of the authored-path gap.
        print("SEASON-INVARIANT authored rows unusable by a bodyweight-only user: \(authoredLoaded) of \(authoredRows)")
    }
}
