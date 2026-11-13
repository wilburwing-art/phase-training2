import XCTest
@testable import PhaseTraining

final class WarmUpRampTests: XCTestCase {

    private func freshStore(_ suite: String = #function) -> SessionStore {
        let name = "WarmUpRampTests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SessionStore(defaults: defaults)
    }

    // MARK: - warmUpRows

    func test_rampRowsScaleFirstWorkingWeightAndRoundToLoadable() {
        let rows = SessionStore.warmUpRows(WarmUpSet.standardRamp, firstWorkingWeight: "135", unit: "lbs")
        // 54 -> 55, 81 -> 80, 108 -> 110.
        XCTAssertEqual(rows.map(\.weight), ["55", "80", "110"])
        XCTAssertEqual(rows.map(\.reps), ["5", "5", "3"])
        XCTAssertTrue(rows.allSatisfy { $0.setType == .warmup && !$0.done })
    }

    func test_rampRowsUseKgStep() {
        let rows = SessionStore.warmUpRows(WarmUpSet.standardRamp, firstWorkingWeight: "100", unit: "kg")
        XCTAssertEqual(rows.map(\.weight), ["40", "60", "80"])
    }

    func test_rampRowsHaveEmptyWeightWithoutSuggestion() {
        for blank in ["", "  ", "abc", "0"] {
            let rows = SessionStore.warmUpRows(WarmUpSet.standardRamp, firstWorkingWeight: blank, unit: "lbs")
            XCTAssertEqual(rows.count, 3)
            XCTAssertTrue(rows.allSatisfy { $0.weight.isEmpty && $0.setType == .warmup }, "weight '\(blank)'")
        }
    }

    // MARK: - createSession

    private func template(ramp: [WarmUpSet]?, unit: String = "lbs") -> WorkoutTemplate {
        WorkoutTemplate(id: "ramp-test-\(UUID().uuidString)", name: "Press day", category: "Generated", exercises: [
            ExerciseTemplate(id: "ex-a", name: "Zz Ramp Press \(UUID().uuidString.prefix(6))", type: nil, unit: unit,
                             targetSets: 3, targetReps: 5, rest: 120, warmUpSets: ramp),
        ])
    }

    func test_sessionStartInsertsRampAheadOfWorkingSets() {
        let store = freshStore()
        let session = store.createSession(from: template(ramp: WarmUpSet.standardRamp))
        let sets = session.exercises[0].sets
        XCTAssertEqual(sets.count, 6)
        XCTAssertEqual(sets.map(\.setType), [.warmup, .warmup, .warmup, .normal, .normal, .normal])
        XCTAssertEqual(sets.map(\.num), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(session.exercises[0].targetSets, 3, "target counts working sets only")
    }

    func test_noRampLeavesSetsUntouched() {
        let store = freshStore()
        let session = store.createSession(from: template(ramp: nil))
        XCTAssertEqual(session.exercises[0].sets.count, 3)
        XCTAssertTrue(session.exercises[0].sets.allSatisfy { $0.setType != .warmup })
    }

    func test_bodyweightRowGetsNoRamp() {
        let store = freshStore()
        let session = store.createSession(from: template(ramp: WarmUpSet.standardRamp,
                                                         unit: LoggedExercise.bodyweightUnit))
        XCTAssertEqual(session.exercises[0].sets.count, 3)
    }

    func test_toWorkoutTemplateCarriesRamp() {
        let gex = GeneratedExercise(id: "g1", exerciseId: 1, name: "Bench", isCompound: true,
                                    sets: 3, reps: "5", restSeconds: 120,
                                    warmUpSets: WarmUpSet.standardRamp)
        let plain = GeneratedExercise(id: "g2", exerciseId: 2, name: "Curl", isCompound: false,
                                      sets: 3, reps: "10", restSeconds: 60)
        let tmpl = GeneratedWorkout(title: "t", summary: "", exercises: [gex, plain],
                                    estimatedMinutes: 30, provenance: "").toWorkoutTemplate(id: "x")
        XCTAssertEqual(tmpl.exercises[0].warmUpSets, WarmUpSet.standardRamp)
        XCTAssertNil(tmpl.exercises[1].warmUpSets)
    }

    // MARK: - Old payloads

    func test_exerciseTemplateWithoutWarmUpFieldDecodes() throws {
        let json = #"{"id":"a","name":"Bench","unit":"lbs","targetSets":3,"targetReps":5,"rest":90}"#
        let t = try JSONDecoder().decode(ExerciseTemplate.self, from: Data(json.utf8))
        XCTAssertNil(t.warmUpSets)
    }

    func test_exerciseTemplateRoundTripsRamp() throws {
        let t = ExerciseTemplate(id: "a", name: "Bench", type: nil, unit: "lbs",
                                 targetSets: 3, targetReps: 5, rest: 90,
                                 warmUpSets: WarmUpSet.standardRamp)
        let back = try JSONDecoder().decode(ExerciseTemplate.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
    }

    // MARK: - Ramp stays out of PR, volume and e1RM math

    func test_rampExcludedFromPRVolumeAndE1RM() {
        let store = freshStore()
        let name = "Bench Press"
        var session = store.createSession(from: WorkoutTemplate(
            id: "ramp-math-\(UUID().uuidString)", name: "Press", category: "Generated",
            exercises: [ExerciseTemplate(id: "b", name: name, type: nil, unit: "lbs",
                                         targetSets: 1, targetReps: 5, rest: 120,
                                         warmUpSets: WarmUpSet.standardRamp)]))
        // Working set 135x5; ramp rows carry heavier-looking junk so any leak shows.
        session.exercises[0].sets[3].weight = "135"
        session.exercises[0].sets[3].reps = "5"
        for i in 0..<3 {
            session.exercises[0].sets[i].weight = "500"
            session.exercises[0].sets[i].reps = "20"
        }
        for i in session.exercises[0].sets.indices { session.exercises[0].sets[i].done = true }

        let prs = store.personalRecords(in: session.exercises)
        XCTAssertEqual(prs.map(\.weight), [135])

        XCTAssertEqual(session.workingVolume(usesImperial: true), 135 * 5, accuracy: 0.001)

        let saved = SavedSession(templateId: "t", name: "Press", category: "",
                                 startTime: Date().addingTimeInterval(-3600),
                                 exercises: session.exercises, feel: nil, note: nil,
                                 endTime: Date(), duration: 3600)
        let rows = StrengthStandards.rows(from: [saved], bodyweightKg: BodyMetrics.lbToKg(180), gender: .male)
        XCTAssertEqual(rows.first?.bestWeightLb ?? 0, 135, accuracy: 0.5)
    }

    // MARK: - previousSet alignment

    func test_previousSetSkipsRampOnBothSides() {
        let prev = [
            LoggedSet(num: 1, weight: "50", reps: "5", rpe: "", done: true, setType: .warmup),
            LoggedSet(num: 2, weight: "135", reps: "5", rpe: "", done: true),
            LoggedSet(num: 3, weight: "140", reps: "5", rpe: "", done: true),
        ]
        let ex = LoggedExercise(
            id: "e", name: "Bench", type: nil, unit: "lbs", targetSets: 2, targetReps: 5, rest: 90,
            sets: [
                LoggedSet(num: 1, weight: "55", reps: "5", rpe: "", done: false, setType: .warmup),
                LoggedSet(num: 2, weight: "80", reps: "5", rpe: "", done: false, setType: .warmup),
                LoggedSet(num: 3, weight: "135", reps: "5", rpe: "", done: false),
                LoggedSet(num: 4, weight: "140", reps: "5", rpe: "", done: false),
            ],
            prevSets: prev)
        XCTAssertNil(ex.previousSet(forRow: 0))
        XCTAssertNil(ex.previousSet(forRow: 1))
        XCTAssertEqual(ex.previousSet(forRow: 2)?.weight, "135")
        XCTAssertEqual(ex.previousSet(forRow: 3)?.weight, "140")
        XCTAssertNil(ex.previousSet(forRow: 9))
    }
}
