import XCTest
@testable import PhaseTraining

/// The inputs that arrived after `FilterCompositionTests` was written: the
/// training goal (build 155) and readiness set-scaling (T2-10). Each had a
/// single-factor test only, which is the shape that hid a 17.5% defect in
/// September (gap pass 2026-10-31, item 7). This crosses them with injuries,
/// equipment and phase through the production entry point, and adds the
/// direction gates the June metamorphic suite carried for the old engine.
final class GeneratorCompositionTests: XCTestCase {

    private static let sports = ["alpine-skiing", "climbing"]
    private static let injuries: [String?] = [nil, "pfps", "lumbar-disc-herniation", "shoulder-impingement"]
    private static let gear: [[Equipment]] = [[.bodyweight], [.dumbbells, .pullUpBar], [.fullGym]]
    private static let readiness: [Double?] = [nil, 0.0, 1.0]
    private static let declaredEmptyStates = ["authored-no-fit", "no-supported-sport"]

    private func memory(_ slug: String, phase: SeasonPhase, goal: TrainingGoal,
                        injury: String? = nil, equipment: [Equipment] = [.fullGym]) -> TrainingMemory {
        var m = TrainingMemory()
        let sport = Sport.resolve(slug: slug)
        m.primarySport = sport
        m.sports = [sport]
        m.seasonsBySport = [sport: phase]
        m.defaultSeason = phase
        m.trainingGoal = goal
        m.equipment = equipment
        m.experience = .intermediate
        m.userInjuries = injury.map { [UserInjury(slug: $0)] } ?? []
        return m
    }

    private func context(_ r: Double?) -> GeneratorContext {
        var ctx = GeneratorContext.empty
        if let r { ctx.readinessScore = r; ctx.hasReadinessData = true }
        return ctx
    }

    private func generate(_ m: TrainingMemory, slot: Int, readiness: Double?, seed: String) -> GeneratedWorkout {
        WorkoutGenerator.generateLift(liftIndex: slot, totalLifts: 3, memory: m,
                                      profile: DemographicProfile.from(m), hashSeed: seed,
                                      context: context(readiness))
    }

    // MARK: - Contract over the cross product

    func test_goalAndReadinessComposeWithInjuryAndEquipment() {
        var checked = 0
        for slug in Self.sports {
            for goal in TrainingGoal.allCases {
                for r in Self.readiness {
                    for injury in Self.injuries {
                        for equipment in Self.gear {
                            for phase in SeasonPhase.allCases {
                                let m = memory(slug, phase: phase, goal: goal, injury: injury, equipment: equipment)
                                let profile = DemographicProfile.from(m)
                                let allowed = profile.allowedEquipmentSlugs
                                for slot in 0..<3 {
                                    let ctx = "[\(slug)/\(goal.rawValue)/r=\(r.map { "\($0)" } ?? "nil")"
                                        + "/\(injury ?? "none")/\(equipment.map(\.rawValue).joined(separator: "+"))"
                                        + "/\(phase.rawValue)/slot \(slot)]"
                                    let w = generate(m, slot: slot, readiness: r, seed: "gcomp-\(ctx)")
                                    checked += 1
                                    if w.exercises.isEmpty {
                                        XCTAssertTrue(Self.declaredEmptyStates.contains(w.provenance),
                                                      "\(ctx) undeclared empty day '\(w.provenance)'")
                                        XCTAssertFalse(w.summary.isEmpty, "\(ctx) empty day with no explanation")
                                        continue
                                    }
                                    XCTAssertGreaterThanOrEqual(w.exercises.count, AuthoredRoutineSelector.minimumMovements,
                                                                "\(ctx) served \(w.exercises.count) movements")
                                    let reqs = CoachDatabase.shared.requiredEquipmentSlugs(
                                        forExerciseIds: Set(w.exercises.map(\.exerciseId)))
                                    for ex in w.exercises where ex.exerciseId > 0 {
                                        XCTAssertFalse(profile.excludedExerciseIds.contains(ex.exerciseId),
                                                       "\(ctx) served contraindicated '\(ex.name)'")
                                        let need = reqs[ex.exerciseId] ?? []
                                        // An empty allowed set is full gym: unrestricted.
                                        XCTAssertTrue(allowed.isEmpty || need.isEmpty || need.isSubset(of: allowed),
                                                      "\(ctx) served '\(ex.name)' needing \(need)")
                                        XCTAssertGreaterThanOrEqual(ex.sets, 1, "\(ctx) '\(ex.name)' has no sets")
                                        XCTAssertFalse(ex.reps.isEmpty, "\(ctx) '\(ex.name)' has no reps")
                                    }
                                    XCTAssertEqual(Set(w.exercises.map(\.exerciseId)).count, w.exercises.count,
                                                   "\(ctx) duplicate movement")
                                }
                            }
                        }
                    }
                }
            }
        }
        print("GENERATOR-COMPOSITION checked \(checked) days")
        XCTAssertGreaterThan(checked, 4000, "grid collapsed")
    }

    // MARK: - Direction gates

    /// Strength work reads fewer reps than size, and size fewer than
    /// endurance, row by row on the same movements. Non-strict: cited
    /// protocols and sport-quality demands keep their own numbers.
    static func isSubsequence(_ a: [Int], of b: [Int]) -> Bool {
        var it = b.makeIterator()
        return a.allSatisfy { x in
            while let y = it.next() { if y == x { return true } }
            return false
        }
    }

    func test_goalDirection_strengthRepsAtMostSizeAtMostEndurance() {
        var compared = 0, moved = 0
        for slug in Self.sports {
            for phase in SeasonPhase.allCases {
                for slot in 0..<3 {
                    let seed = "gdir-\(slug)-\(phase.rawValue)-\(slot)"
                    let byGoal = [TrainingGoal.strength, .size, .endurance].map {
                        generate(memory(slug, phase: phase, goal: $0), slot: slot, readiness: nil, seed: seed)
                    }
                    // The goal sets rest (180 s strength, 45 s endurance), and
                    // the session is fitted to its minutes, so a strength
                    // session may hold fewer movements than an endurance one.
                    // Before the fit (finding 4) all three had the same list
                    // whatever the minutes. What holds: the goal never swaps
                    // a movement, so each list is an ordered subsequence of
                    // the longest, and rows compare on the movements shared.
                    let lists = byGoal.map { $0.exercises.map(\.exerciseId) }
                    let longest = lists.max { $0.count < $1.count } ?? []
                    guard lists.allSatisfy({ Self.isSubsequence($0, of: longest) }) else {
                        XCTFail("[\(slug)/\(phase.rawValue)/\(slot)] the goal changed which movements were picked: \(lists)")
                        continue
                    }
                    let shared = byGoal[0].exercises.map(\.exerciseId).filter { id in lists.allSatisfy { $0.contains(id) } }
                    for id in shared {
                        let rows = byGoal.map { $0.exercises.first { $0.exerciseId == id }! }
                        let reps = rows.map { Self.leadingNumber($0.reps) }
                        guard let s = reps[0], let z = reps[1], let e = reps[2] else { continue }
                        compared += 1
                        if s != e { moved += 1 }
                        let name = rows[0].name
                        XCTAssertLessThanOrEqual(s, z, "[\(slug)/\(phase.rawValue)/\(slot)] \(name): strength \(s) > size \(z)")
                        XCTAssertLessThanOrEqual(z, e, "[\(slug)/\(phase.rawValue)/\(slot)] \(name): size \(z) > endurance \(e)")
                    }
                }
            }
        }
        print("GOAL-DIRECTION compared \(compared) rows, \(moved) moved")
        XCTAssertGreaterThan(moved, 10, "the goal moved almost nothing; the gate is not exercising anything")
    }

    /// Lower readiness never adds sets: 0 <= 0.5 <= 1, row by row.
    func test_readinessDirection_setsNeverRiseAsReadinessFalls() {
        var compared = 0, moved = 0
        for slug in Self.sports {
            for phase in SeasonPhase.allCases {
                for slot in 0..<3 {
                    let seed = "rdir-\(slug)-\(phase.rawValue)-\(slot)"
                    let m = memory(slug, phase: phase, goal: .sportPerformance)
                    let byReadiness = [0.0, 0.5, 1.0].map { generate(m, slot: slot, readiness: $0, seed: seed) }
                    guard byReadiness.allSatisfy({ $0.exercises.map(\.exerciseId) == byReadiness[0].exercises.map(\.exerciseId) })
                    else { continue }  // a different pick is not a set-count question
                    for i in byReadiness[0].exercises.indices {
                        let sets = byReadiness.map { $0.exercises[i].sets }
                        compared += 1
                        if sets[0] != sets[2] { moved += 1 }
                        let name = byReadiness[0].exercises[i].name
                        XCTAssertLessThanOrEqual(sets[0], sets[1], "[\(slug)/\(phase.rawValue)/\(slot)] \(name)")
                        XCTAssertLessThanOrEqual(sets[1], sets[2], "[\(slug)/\(phase.rawValue)/\(slot)] \(name)")
                    }
                }
            }
        }
        print("READINESS-DIRECTION compared \(compared) rows, \(moved) moved")
        XCTAssertGreaterThan(compared, 50)
        XCTAssertGreaterThan(moved, 10, "readiness moved almost nothing; the gate is not exercising anything")
    }

    private static func leadingNumber(_ s: String) -> Int? {
        let digits = s.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }
}
