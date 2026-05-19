import XCTest
@testable import PhaseTraining

final class SessionStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        // Best-effort wipe in case of suite reuse.
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - createSession

    func testCreateSessionUpper1HasSixExercisesWithCorrectSetCounts() {
        let store = SessionStore(defaults: defaults)
        let session = store.createSession(templateId: "upper-1")

        XCTAssertEqual(session.templateId, "upper-1")
        XCTAssertEqual(session.name, "Upper Body Day 1")
        XCTAssertEqual(session.category, "Push / Pull / Accessories")
        XCTAssertEqual(session.exercises.count, 6)

        let expectedCounts = [5, 4, 4, 4, 3, 3]
        XCTAssertEqual(session.exercises.map { $0.sets.count }, expectedCounts)
        XCTAssertEqual(session.exercises.map { $0.id }, ["bench", "pullup", "ohp", "row", "skull", "facepull"])
    }

    /// Leak #2 regression: prior weight should follow the exercise NAME
    /// across templates. Before the cross-template fallback, a "Bench Press"
    /// inside template "A" couldn't see a "Bench Press" logged inside
    /// template "B" — the autofill column stayed empty even though the user
    /// had progressive-overload data sitting right there in history.
    func testCreateSessionAutofillsAcrossDifferentTemplateIds() {
        let store = SessionStore(defaults: defaults)

        // Prior session under template "A". Two completed bench sets at 225×5.
        let prior = SavedSession(
            templateId: "A",
            name: "Push A",
            category: "Push",
            startTime: Date().addingTimeInterval(-7 * 86400),
            exercises: [
                LoggedExercise(
                    id: "rex-bench-A",  // Note different id than the new template's exercise id.
                    name: "Bench Press",
                    type: "Barbell", unit: "lbs",
                    targetSets: 3, targetReps: 5, rest: 120,
                    sets: [
                        LoggedSet(num: 1, weight: "225", reps: "5", rpe: "8", done: true),
                        LoggedSet(num: 2, weight: "225", reps: "5", rpe: "8", done: true),
                        LoggedSet(num: 3, weight: "230", reps: "3", rpe: "9", done: true),
                    ],
                    prevSets: []
                )
            ],
            feel: nil, note: nil,
            endTime: Date().addingTimeInterval(-7 * 86400 + 3600),
            duration: 3600
        )
        store.saveAll([prior])

        // New workout under template "B" containing Bench Press with a
        // different exercise id. Without the cross-template fallback, prev
        // would be empty here.
        let newTemplate = WorkoutTemplate(
            id: "B", name: "Push B", category: "Push",
            exercises: [
                ExerciseTemplate(id: "gex-bench-B", name: "Bench Press",
                                 type: "Barbell", unit: "lbs",
                                 targetSets: 3, targetReps: 5, rest: 120)
            ]
        )
        let session = store.createSession(from: newTemplate)
        let bench = session.exercises[0]

        // Autofill should now reflect the cross-template prior.
        XCTAssertEqual(bench.sets.first?.weight, "225",
                       "cross-template prev should populate the weight column")
        XCTAssertEqual(bench.sets.first?.reps, "5",
                       "cross-template prev should populate the reps column")
        XCTAssertFalse(bench.prevSets.isEmpty,
                       "prevSets array should expose the cross-template history to LogScreen")
    }

    /// Sanity: when the user has done the SAME template before, that path
    /// still wins (no regression from the fallback being introduced).
    func testCreateSessionPrefersSameTemplatePriorOverCrossTemplate() {
        let store = SessionStore(defaults: defaults)

        // Older session under "B" — should be picked.
        let sameTemplate = SavedSession(
            templateId: "B", name: "Push B", category: "Push",
            startTime: Date().addingTimeInterval(-3 * 86400),
            exercises: [
                LoggedExercise(
                    id: "gex-bench-B", name: "Bench Press",
                    type: "Barbell", unit: "lbs",
                    targetSets: 3, targetReps: 5, rest: 120,
                    sets: [LoggedSet(num: 1, weight: "240", reps: "5", rpe: "8", done: true)],
                    prevSets: []
                )
            ],
            feel: nil, note: nil,
            endTime: Date().addingTimeInterval(-3 * 86400 + 3600),
            duration: 3600
        )
        // Newer session under "A" — should NOT shadow B's template-match.
        let crossTemplate = SavedSession(
            templateId: "A", name: "Push A", category: "Push",
            startTime: Date().addingTimeInterval(-1 * 86400),
            exercises: [
                LoggedExercise(
                    id: "rex-bench-A", name: "Bench Press",
                    type: "Barbell", unit: "lbs",
                    targetSets: 3, targetReps: 5, rest: 120,
                    sets: [LoggedSet(num: 1, weight: "225", reps: "5", rpe: "8", done: true)],
                    prevSets: []
                )
            ],
            feel: nil, note: nil,
            endTime: Date().addingTimeInterval(-1 * 86400 + 3600),
            duration: 3600
        )
        store.saveAll([sameTemplate, crossTemplate])

        let session = store.createSession(from: WorkoutTemplate(
            id: "B", name: "Push B", category: "Push",
            exercises: [
                ExerciseTemplate(id: "gex-bench-B", name: "Bench Press",
                                 type: "Barbell", unit: "lbs",
                                 targetSets: 3, targetReps: 5, rest: 120)
            ]
        ))
        XCTAssertEqual(session.exercises[0].sets.first?.weight, "240",
                       "template-match (240) should win over cross-template (225)")
    }

    func testCreateSessionWithNoPriorHistoryHasEmptyWeightsAndTargetReps() {
        let store = SessionStore(defaults: defaults)
        let session = store.createSession(templateId: "upper-1")

        for ex in session.exercises {
            for set in ex.sets {
                XCTAssertEqual(set.weight, "")
                XCTAssertEqual(set.reps, String(ex.targetReps))
                XCTAssertEqual(set.rpe, "")
                XCTAssertFalse(set.done)
            }
            XCTAssertTrue(ex.prevSets.isEmpty)
        }
    }

    func testCreateSessionWithPriorHistoryPullsWeightAndRepsForward() {
        let store = SessionStore(defaults: defaults)

        // Hand-build a prior saved session for upper-1 with bench at 225x5 across 5 sets.
        let priorBenchSets = (0..<5).map { i in
            LoggedSet(num: i + 1, weight: "225", reps: "5", rpe: "8", done: true)
        }
        let priorBench = LoggedExercise(
            id: "bench", name: "Bench Press", type: "Barbell", unit: "lbs",
            targetSets: 5, targetReps: 5, rest: 120,
            sets: priorBenchSets, prevSets: []
        )
        let priorPullups = LoggedExercise(
            id: "pullup", name: "Pull Up", type: nil, unit: "+lbs",
            targetSets: 4, targetReps: 5, rest: 120,
            sets: (0..<4).map { LoggedSet(num: $0 + 1, weight: "45", reps: "5", rpe: "7", done: true) },
            prevSets: []
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let prior = SavedSession(
            templateId: "upper-1",
            name: "Upper Body Day 1",
            category: "Push / Pull / Accessories",
            startTime: start,
            exercises: [priorBench, priorPullups],
            feel: "OK",
            note: nil,
            endTime: start.addingTimeInterval(3600),
            duration: 3600
        )
        store.saveAll([prior])

        let session = store.createSession(templateId: "upper-1")
        let bench = session.exercises.first { $0.id == "bench" }!
        XCTAssertEqual(bench.sets.count, 5)
        for set in bench.sets {
            XCTAssertEqual(set.weight, "225")
            XCTAssertEqual(set.reps, "5")
            XCTAssertEqual(set.rpe, "")
            XCTAssertFalse(set.done)
        }
        XCTAssertEqual(bench.prevSets.count, 5)
        XCTAssertEqual(bench.prevSets.first?.weight, "225")

        let pullup = session.exercises.first { $0.id == "pullup" }!
        XCTAssertEqual(pullup.sets.count, 4)
        for set in pullup.sets {
            XCTAssertEqual(set.weight, "45")
            XCTAssertEqual(set.reps, "5")
        }

        // Exercises without prior data still fall back to defaults.
        let ohp = session.exercises.first { $0.id == "ohp" }!
        XCTAssertTrue(ohp.prevSets.isEmpty)
        for set in ohp.sets {
            XCTAssertEqual(set.weight, "")
            XCTAssertEqual(set.reps, "8")
        }
    }

    // MARK: - stats

    func testStatsAveragesRpeAcrossDoneSets() {
        // Hand-build a session with 10 total sets, 3 done at RPE 7,8,9 → avg 8.0.
        let doneSets: [LoggedSet] = [
            LoggedSet(num: 1, weight: "100", reps: "5", rpe: "7", done: true),
            LoggedSet(num: 2, weight: "100", reps: "5", rpe: "8", done: true),
            LoggedSet(num: 3, weight: "100", reps: "5", rpe: "9", done: true),
            LoggedSet(num: 4, weight: "",    reps: "5", rpe: "",  done: false),
            LoggedSet(num: 5, weight: "",    reps: "5", rpe: "",  done: false),
        ]
        let pendingSets: [LoggedSet] = (1...5).map {
            LoggedSet(num: $0, weight: "", reps: "5", rpe: "", done: false)
        }
        let exA = LoggedExercise(
            id: "bench", name: "Bench Press", type: "Barbell", unit: "lbs",
            targetSets: 5, targetReps: 5, rest: 120,
            sets: doneSets, prevSets: []
        )
        let exB = LoggedExercise(
            id: "pullup", name: "Pull Up", type: nil, unit: "+lbs",
            targetSets: 5, targetReps: 5, rest: 120,
            sets: pendingSets, prevSets: []
        )
        let session = ActiveSession(
            templateId: "upper-1",
            name: "Upper Body Day 1",
            category: "Push / Pull / Accessories",
            startTime: Date(),
            exercises: [exA, exB],
            feel: nil,
            note: nil
        )

        let store = SessionStore(defaults: defaults)
        let stats = store.stats(for: session)
        XCTAssertEqual(stats.totalSets, 10)
        XCTAssertEqual(stats.doneSets, 3)
        XCTAssertEqual(stats.avgRpe, "8.0")
    }

    // MARK: - active-session roundtrip

    func testActiveSessionRoundtripSurvivesInstanceSwap() {
        let store1 = SessionStore(defaults: defaults)
        let original = store1.createSession(templateId: "upper-1")
        store1.saveActive(original)

        let store2 = SessionStore(defaults: defaults)
        let loaded = store2.loadActive()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.templateId, original.templateId)
        XCTAssertEqual(loaded?.name, original.name)
        XCTAssertEqual(loaded?.category, original.category)
        XCTAssertEqual(loaded?.exercises.count, original.exercises.count)
        XCTAssertEqual(loaded?.exercises.map { $0.sets.count },
                       original.exercises.map { $0.sets.count })

        // active property auto-loaded on init too.
        XCTAssertEqual(store2.active?.templateId, original.templateId)
    }
}
