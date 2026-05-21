import XCTest
@testable import PhaseTraining

final class SessionStorePRTests: XCTestCase {

    private func freshStore(_ suite: String = #function) -> SessionStore {
        let defaults = UserDefaults(suiteName: "SessionStorePRTests.\(suite)")!
        defaults.removePersistentDomain(forName: "SessionStorePRTests.\(suite)")
        return SessionStore(defaults: defaults)
    }

    /// Helper: build a saved session with a single exercise + a list of
    /// (weight, reps) tuples for the sets. All sets marked done.
    private func savedSession(
        templateId: String = "t",
        exerciseName: String,
        sets: [(weight: String, reps: String)],
        endTime: Date = Date()
    ) -> SavedSession {
        let logged = LoggedExercise(
            id: exerciseName,
            name: exerciseName,
            type: nil,
            unit: "lbs",
            targetSets: sets.count,
            targetReps: 5,
            rest: 90,
            sets: sets.enumerated().map { i, s in
                LoggedSet(num: i + 1, weight: s.weight, reps: s.reps, rpe: "", done: true)
            },
            prevSets: []
        )
        return SavedSession(
            templateId: templateId, name: exerciseName, category: "",
            startTime: endTime.addingTimeInterval(-3600),
            exercises: [logged],
            feel: nil, note: nil,
            endTime: endTime, duration: 3600
        )
    }

    /// Build a LoggedExercise inline for the "in-progress" PR query.
    private func loggedExercise(
        name: String,
        sets: [(weight: String, reps: String, done: Bool)]
    ) -> LoggedExercise {
        LoggedExercise(
            id: name, name: name, type: nil, unit: "lbs",
            targetSets: sets.count, targetReps: 5, rest: 90,
            sets: sets.enumerated().map { i, s in
                LoggedSet(num: i + 1, weight: s.weight, reps: s.reps, rpe: "", done: s.done)
            },
            prevSets: []
        )
    }

    // MARK: - Empty-history case

    func test_firstEverWorkout_isAllPRs() {
        let store = freshStore()
        let ex = loggedExercise(name: "Bench Press", sets: [
            (weight: "135", reps: "5", done: true),
            (weight: "135", reps: "5", done: true),
        ])
        let prs = store.personalRecords(in: [ex])
        XCTAssertEqual(prs.count, 1, "Two same-weight sets dedup to one (exercise, reps) PR")
        XCTAssertEqual(prs.first?.weight, 135)
        XCTAssertNil(prs.first?.previousBest, "First ever rep×weight has no prior best")
    }

    // MARK: - Beats prior

    func test_beatsPriorWeightAtSameReps_emitsPR() {
        let store = freshStore()
        // Prior session: bench 135 × 5.
        store.saveAll([savedSession(exerciseName: "Bench Press",
                                    sets: [("135", "5")],
                                    endTime: Date().addingTimeInterval(-86400))])

        let ex = loggedExercise(name: "Bench Press",
                                sets: [(weight: "140", reps: "5", done: true)])
        let prs = store.personalRecords(in: [ex])
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs.first?.weight, 140)
        XCTAssertEqual(prs.first?.previousBest, 135)
    }

    // MARK: - Same or less

    func test_sameWeightAsPrior_isNotPR() {
        let store = freshStore()
        store.saveAll([savedSession(exerciseName: "Bench Press",
                                    sets: [("135", "5")],
                                    endTime: Date().addingTimeInterval(-86400))])

        let ex = loggedExercise(name: "Bench Press",
                                sets: [(weight: "135", reps: "5", done: true)])
        XCTAssertTrue(store.personalRecords(in: [ex]).isEmpty)
    }

    // MARK: - Cross-template (the upgrade over old impl)

    func test_priorWasUnderDifferentTemplate_stillCounts() {
        let store = freshStore()
        // Old plan: bench under "push-A" template.
        store.saveAll([savedSession(templateId: "push-A",
                                    exerciseName: "Bench Press",
                                    sets: [("135", "5")],
                                    endTime: Date().addingTimeInterval(-86400))])

        // New plan regenerated → different templateId → same exercise hits a PR.
        let ex = loggedExercise(name: "Bench Press",
                                sets: [(weight: "140", reps: "5", done: true)])
        let prs = store.personalRecords(in: [ex])
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs.first?.previousBest, 135,
                       "PR detection should look across templates by exercise name")
    }

    // MARK: - Per-rep specificity

    func test_PR_isPerRepCount_independent() {
        let store = freshStore()
        store.saveAll([savedSession(exerciseName: "Squat",
                                    sets: [("225", "5"), ("185", "10")],
                                    endTime: Date().addingTimeInterval(-86400))])

        // Today: 230×5 (PR), 185×10 (tie, not PR).
        let ex = loggedExercise(name: "Squat", sets: [
            (weight: "230", reps: "5", done: true),
            (weight: "185", reps: "10", done: true),
        ])
        let prs = store.personalRecords(in: [ex])
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs.first?.reps, 5)
    }

    // MARK: - Unfinished sets don't qualify

    func test_undoneSets_areIgnored() {
        let store = freshStore()
        let ex = loggedExercise(name: "Bench Press", sets: [
            (weight: "200", reps: "5", done: false),   // not done — ignored
        ])
        XCTAssertTrue(store.personalRecords(in: [ex]).isEmpty)
    }

    // MARK: - Historical walk (allPersonalRecords)

    func test_allPersonalRecords_emitsEventsNewestFirstWithProgressingPriorBest() {
        let store = freshStore()
        let now = Date()
        // 3 sessions, oldest → newest: 135, 145, 155 all at 5 reps.
        store.saveAll([
            savedSession(exerciseName: "Bench Press", sets: [("155", "5")],
                         endTime: now.addingTimeInterval(-1 * 86400)),
            savedSession(exerciseName: "Bench Press", sets: [("145", "5")],
                         endTime: now.addingTimeInterval(-3 * 86400)),
            savedSession(exerciseName: "Bench Press", sets: [("135", "5")],
                         endTime: now.addingTimeInterval(-5 * 86400)),
        ])

        let events = store.allPersonalRecords()
        XCTAssertEqual(events.count, 3, "Each progressing session sets a new PR")
        // Newest first
        XCTAssertEqual(events[0].weight, 155)
        XCTAssertEqual(events[0].previousBest, 145)
        XCTAssertEqual(events[1].weight, 145)
        XCTAssertEqual(events[1].previousBest, 135)
        XCTAssertEqual(events[2].weight, 135)
        XCTAssertNil(events[2].previousBest, "First-ever 5-rep bench has no prior best")
    }

    func test_allPersonalRecords_dedupsPerExercisePerRepsWithinSession() {
        let store = freshStore()
        // Two sets at same (exercise, reps, weight) in one session → one PR.
        store.saveAll([
            savedSession(exerciseName: "Squat",
                         sets: [("225", "5"), ("225", "5")])
        ])
        XCTAssertEqual(store.allPersonalRecords().count, 1)
    }

    func test_allPersonalRecords_isEmptyWhenNoCompletedWeightedSets() {
        let store = freshStore()
        XCTAssertTrue(store.allPersonalRecords().isEmpty)
    }

    // MARK: - Warmup-set exclusion (correctness invariant)

    /// A warmup set heavier than any working set must NEVER fire a PR.
    /// This is the load-bearing invariant for the warmup column.
    func test_warmupSet_neverCountsAsPR_inProgressFlow() {
        let store = freshStore()
        let logged = LoggedExercise(
            id: "Bench Press", name: "Bench Press", type: nil, unit: "lbs",
            targetSets: 2, targetReps: 5, rest: 90,
            sets: [
                LoggedSet(num: 1, weight: "999", reps: "5", rpe: "", done: true, isWarmup: true),
                LoggedSet(num: 2, weight: "135", reps: "5", rpe: "", done: true, isWarmup: false),
            ],
            prevSets: []
        )
        let prs = store.personalRecords(in: [logged])
        XCTAssertEqual(prs.count, 1, "Working set fires PR; warmup does not")
        XCTAssertEqual(prs.first?.weight, 135,
                       "PR weight reflects working set, not the heavier warmup")
    }

    func test_warmupSet_neverCountsAsPR_acrossHistory() {
        let store = freshStore()
        // Save a session where the warmup is heavier than the working set.
        let now = Date()
        let warmupHeavy = LoggedExercise(
            id: "Bench Press", name: "Bench Press", type: nil, unit: "lbs",
            targetSets: 2, targetReps: 5, rest: 90,
            sets: [
                LoggedSet(num: 1, weight: "315", reps: "5", rpe: "", done: true, isWarmup: true),
                LoggedSet(num: 2, weight: "135", reps: "5", rpe: "", done: true, isWarmup: false),
            ],
            prevSets: []
        )
        let session = SavedSession(
            templateId: "t", name: "Bench Press", category: "",
            startTime: now.addingTimeInterval(-3600),
            exercises: [warmupHeavy],
            feel: nil, note: nil,
            endTime: now, duration: 3600
        )
        store.saveAll([session])

        let events = store.allPersonalRecords()
        XCTAssertEqual(events.count, 1, "Only the working set should produce a PR event")
        XCTAssertEqual(events.first?.weight, 135,
                       "Historical-walk PR must come from the working set, not the warmup")
    }
}
