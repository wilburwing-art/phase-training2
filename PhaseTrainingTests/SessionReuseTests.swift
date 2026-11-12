import XCTest
@testable import PhaseTraining

/// Repeat, save-as-routine and the History filter are value transforms over
/// `SavedSession`; these pin what each carries forward and what it drops.
final class SessionReuseTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_772_000_000) // 2026-02-25 UTC

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func set(_ n: Int, _ w: String, _ r: String, done: Bool = true, warmup: Bool = false) -> LoggedSet {
        LoggedSet(num: n, weight: w, reps: r, rpe: "", done: done, isWarmup: warmup)
    }

    private func exercise(_ name: String, sets: [LoggedSet], targetSets: Int = 3, targetReps: Int = 8,
                          superset: Int? = nil, repsLabel: String? = nil, note: String? = nil) -> LoggedExercise {
        LoggedExercise(id: "ex-\(name)", name: name, type: nil, unit: "lbs",
                       targetSets: targetSets, targetReps: targetReps, rest: 120,
                       sets: sets, prevSets: [], rpe: "7", tempo: nil,
                       supersetGroup: superset, note: note, repsLabel: repsLabel)
    }

    private func session(_ exercises: [LoggedExercise], name: String = "Leg day",
                         note: String? = nil, tags: [SessionTag] = []) -> SavedSession {
        SavedSession(templateId: "tmpl-1", name: name, category: "lift", startTime: start,
                     exercises: exercises, feel: nil, note: note,
                     endTime: start.addingTimeInterval(3000), duration: 3000,
                     sessionTags: tags.map(\.rawValue))
    }

    // MARK: - Repeat

    func test_repeat_keepsIdsAndDropsExercisesWithNoDoneSet() {
        let s = session([
            exercise("Back Squat", sets: [set(1, "135", "5", warmup: true), set(2, "225", "5"), set(3, "225", "4")],
                     superset: 1),
            exercise("Leg Curl", sets: [set(1, "", "10", done: false)]),
        ])
        let t = s.repeatTemplate()
        XCTAssertEqual(t.id, "tmpl-1")
        XCTAssertEqual(t.exercises.map(\.name), ["Back Squat"])
        let squat = t.exercises[0]
        XCTAssertEqual(squat.id, "ex-Back Squat")
        XCTAssertEqual(squat.targetSets, 2, "warm-up rows are not working sets")
        XCTAssertEqual(squat.targetReps, 5, "reps come from the first completed working set")
        XCTAssertEqual(squat.rest, 120)
        XCTAssertEqual(squat.supersetGroup, 1)
        XCTAssertEqual(squat.rpe, "7")
    }

    func test_repeat_keepsEveryRowAsWrittenWhenNothingWasDone() {
        let s = session([
            exercise("Back Squat", sets: [set(1, "", "", done: false)], targetSets: 4, targetReps: 6),
            exercise("Leg Curl", sets: [], targetSets: 3, targetReps: 12),
        ])
        let t = s.repeatTemplate()
        XCTAssertEqual(t.exercises.map(\.targetSets), [4, 3])
        XCTAssertEqual(t.exercises.map(\.targetReps), [6, 12])
    }

    func test_repeat_keepsAWrittenHoldPrescription() {
        let s = session([
            exercise("Side Plank", sets: [set(1, "", "45")], targetReps: 30, repsLabel: "30-60 sec"),
        ])
        let ex = s.repeatTemplate().exercises[0]
        XCTAssertEqual(ex.repsLabel, "30-60 sec")
        XCTAssertEqual(ex.targetReps, 30, "a timed row keeps its planned count")
    }

    // MARK: - Save as routine

    func test_asCustomRoutine_carriesPrescriptionSupersetAndResolvedId() {
        let s = session([
            exercise("Back Squat", sets: [set(1, "225", "5"), set(2, "225", "5")], superset: 2),
            exercise("Mystery Move", sets: [set(1, "10", "12")]),
        ])
        let r = s.asCustomRoutine(now: start) { $0 == "Back Squat" ? 42 : nil }
        XCTAssertEqual(r.name, "Leg day")
        XCTAssertEqual(r.createdAt, start)
        XCTAssertEqual(r.exercises.map(\.exerciseId), [42, 0])
        XCTAssertEqual(r.exercises.map(\.position), [1, 2])
        XCTAssertEqual(r.exercises[0].sets, 2)
        XCTAssertEqual(r.exercises[0].reps, "5")
        XCTAssertEqual(r.exercises[0].rest, "120s")
        XCTAssertEqual(r.exercises[0].supersetGroup, 2)
        XCTAssertEqual(r.exercises[1].reps, "12")
    }

    func test_asCustomRoutine_roundTripsThroughTheTemplateBridge() {
        let s = session([exercise("Back Squat", sets: [set(1, "225", "5"), set(2, "225", "5")])])
        let t = s.asCustomRoutine(exerciseId: { _ in nil }).toWorkoutTemplate()
        XCTAssertEqual(t.exercises.count, 1)
        XCTAssertEqual(t.exercises[0].targetSets, 2)
        XCTAssertEqual(t.exercises[0].targetReps, 5)
        XCTAssertEqual(t.exercises[0].rest, 120)
    }

    func test_asCustomRoutine_blankNameGetsAFallback() {
        let s = session([exercise("Back Squat", sets: [set(1, "225", "5")])], name: "  ")
        XCTAssertEqual(s.asCustomRoutine(exerciseId: { _ in nil }).name, "Saved workout")
    }

    // MARK: - History filter

    func test_filter_emptyMatchesEverything() {
        let s = session([exercise("Back Squat", sets: [])])
        XCTAssertFalse(HistoryFilter().isActive)
        XCTAssertTrue(HistoryFilter().matches(s, calendar: utc))
        XCTAssertTrue(HistoryFilter(query: "   ").matches(s, calendar: utc))
    }

    func test_filter_searchesNameExerciseNotesAndMonth() {
        let s = session([exercise("Back Squat", sets: [], note: "Seat 4")],
                        name: "Leg day", note: "Felt heavy")
        for q in ["leg", "SQUAT", "seat", "heavy", "february", "2026", "squat february"] {
            XCTAssertTrue(HistoryFilter(query: q).matches(s, calendar: utc), q)
        }
        for q in ["bench", "march", "squat march"] {
            XCTAssertFalse(HistoryFilter(query: q).matches(s, calendar: utc), q)
        }
    }

    func test_filter_tagsMustAllBePresent() {
        let s = session([exercise("Back Squat", sets: [])], tags: [.testDay])
        XCTAssertTrue(HistoryFilter(tags: [.testDay]).matches(s, calendar: utc))
        XCTAssertFalse(HistoryFilter(tags: [.testDay, .maxAttempt]).matches(s, calendar: utc))
        XCTAssertTrue(HistoryFilter(query: "test day").matches(s, calendar: utc), "tag labels are searchable")
        XCTAssertFalse(HistoryFilter(query: "bench", tags: [.testDay]).matches(s, calendar: utc))
    }

    func test_filter_applyAndTagsPresent() {
        let a = session([exercise("Back Squat", sets: [])], tags: [.lightDay])
        var b = session([exercise("Bench Press", sets: [])], name: "Push")
        b.startTime = start.addingTimeInterval(86400)
        XCTAssertEqual(HistoryFilter(query: "bench").apply(to: [a, b], calendar: utc).map(\.name), ["Push"])
        XCTAssertEqual(HistoryFilter().apply(to: [a, b], calendar: utc).count, 2)
        XCTAssertEqual(HistoryFilter.tagsPresent(in: [a, b]), [.lightDay])
        XCTAssertEqual(HistoryFilter.tagsPresent(in: [b]), [])
    }
}
