// SessionStoreGoalMetricsTests.swift — the producers behind the goal progress
// bar. GoalTemplateTests covers the arithmetic with hand-passed values; these
// cover the data that feeds it.

import XCTest
@testable import PhaseTraining

final class SessionStoreGoalMetricsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "goal-metrics-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeStore() -> SessionStore {
        SessionStore(defaults: defaults, userDB: UserDatabase(path: ":memory:"))
    }

    private func set(_ w: String, _ r: String, done: Bool = true, warmup: Bool = false) -> LoggedSet {
        LoggedSet(num: 1, weight: w, reps: r, rpe: "", done: done, setType: warmup ? .warmup : .normal)
    }

    private func session(daysAgo: Int, _ exercises: [(String, [LoggedSet])]) -> SavedSession {
        let start = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        return SavedSession(
            templateId: "t", name: "S", category: "c", startTime: start,
            exercises: exercises.enumerated().map { i, e in
                LoggedExercise(id: "ex-\(i)-\(e.0)", name: e.0, type: "Barbell", unit: "lbs",
                               targetSets: e.1.count, targetReps: 5, rest: 90,
                               // Sets are keyed by number in the store, so
                               // each needs its own or only the first survives.
                               sets: e.1.enumerated().map { j, st in
                                   var st = st; st.num = j + 1; return st
                               }, prevSets: [])
            },
            feel: nil, note: nil, endTime: start.addingTimeInterval(3600), duration: 3600)
    }

    private func run(_ slug: String, minutes: Int, note: String?) -> SportLogEntry {
        SportLogEntry(date: Date(), sport: Sport(slug: slug, name: slug), durationMinutes: minutes,
                      intensity: .moderate, note: note, loggedAt: Date())
    }

    // MARK: - bestE1RMByExercise

    func testEmptyHistoryYieldsEmptyMap() {
        XCTAssertTrue(makeStore().bestE1RMByExercise().isEmpty)
    }

    func testBestIsEpleyOfTheStrongestDoneSet() throws {
        let store = makeStore()
        store.saveAll([session(daysAgo: 1, [("Bench Press", [set("200", "5"), set("225", "3")])])])
        let best = try XCTUnwrap(store.bestE1RMByExercise()["bench press"])
        // 200x5 = 233.33, 225x3 = 247.5, 225x3 wins.
        XCTAssertEqual(best, 247.5, accuracy: 0.01)
    }

    func testWarmupsUndoneAndZeroWeightSetsAreExcluded() {
        let store = makeStore()
        store.saveAll([session(daysAgo: 1, [("Squat", [
            set("500", "5", warmup: true),   // heavy warmup must not count
            set("400", "5", done: false),    // undone must not count
            set("0", "10"),                  // zero weight must not count
            set("225", "0"),                 // zero reps must not count
            set("185", "5"),                 // only this one counts
        ])])])
        XCTAssertEqual(store.bestE1RMByExercise()["squat"] ?? 0, 185 * (1 + 5.0 / 30), accuracy: 0.01)
    }

    func testExerciseWithNoQualifyingSetIsAbsentNotZero() {
        let store = makeStore()
        store.saveAll([session(daysAgo: 1, [("Deadlift", [set("315", "5", done: false)])])])
        XCTAssertNil(store.bestE1RMByExercise()["deadlift"])
    }

    func testCasingVariantsAcrossSessionsMergeUnderOneLowercasedKey() throws {
        let store = makeStore()
        store.saveAll([
            session(daysAgo: 10, [("Bench Press", [set("185", "5")])]),
            session(daysAgo: 2, [("bench PRESS", [set("205", "5")])]),
        ])
        let map = store.bestE1RMByExercise()
        XCTAssertEqual(map.keys.filter { $0.contains("bench") }, ["bench press"])
        XCTAssertEqual(try XCTUnwrap(map["bench press"]), 205 * (1 + 5.0 / 30), accuracy: 0.01)
    }

    func testOlderSessionCanHoldTheBest() throws {
        let store = makeStore()
        store.saveAll([
            session(daysAgo: 400, [("Row", [set("250", "5")])]),
            session(daysAgo: 1, [("Row", [set("150", "5")])]),
        ])
        XCTAssertEqual(try XCTUnwrap(store.bestE1RMByExercise()["row"]), 250 * (1 + 5.0 / 30), accuracy: 0.01)
    }

    // MARK: - fastestFiveKSeconds

    func testFastestFiveKPicksShortestAnnotatedRunAcrossCasing() {
        let store = makeStore()
        let logs = [
            run("running", minutes: 31, note: "parkrun 5k"),
            run("running", minutes: 27, note: "Tempo 5K PB"),
            run("running", minutes: 20, note: "easy loop"),   // fast but not annotated
        ]
        XCTAssertEqual(store.fastestFiveKSeconds(sportLogs: logs), 27 * 60)
    }

    func testTenKRunIsNotAFiveK() {
        let store = makeStore()
        XCTAssertNil(store.fastestFiveKSeconds(sportLogs: [run("running", minutes: 55, note: "10k race")]))
    }

    /// "15k" and "25k" contain the substring "5k". Matching on the bare
    /// substring would give a 15k run's time as the user's 5k PR.
    func testFifteenKRunIsNotAFiveK() {
        let store = makeStore()
        XCTAssertNil(store.fastestFiveKSeconds(sportLogs: [run("running", minutes: 80, note: "15k long run")]))
    
    }

    func testNonRunSportIsIgnoredEvenWithFiveKNote() {
        let store = makeStore()
        XCTAssertNil(store.fastestFiveKSeconds(sportLogs: [run("cycling", minutes: 25, note: "5k commute")]))
    }

    func testRunSlugVariantsCount() {
        let store = makeStore()
        XCTAssertEqual(store.fastestFiveKSeconds(sportLogs: [run("trail-running", minutes: 33, note: "5k")]), 33 * 60)
    }

    func testRunWithNoNoteAndEmptyLogsAreNil() {
        let store = makeStore()
        XCTAssertNil(store.fastestFiveKSeconds(sportLogs: [run("running", minutes: 25, note: nil)]))
        XCTAssertNil(store.fastestFiveKSeconds(sportLogs: []))
    }
}
