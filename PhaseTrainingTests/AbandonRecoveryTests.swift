// AbandonRecoveryTests.swift — 11c 3.2.
//
// A Pain stop with joints picked on AbandonReasonSheet writes a hurt report
// (FeedbackEntry, difficulty nil) through SessionStore.onHurtReported, before
// onSessionSaved, and MuscleRecovery eases the muscles around each joint.

import XCTest
@testable import PhaseTraining

final class AbandonRecoveryTests: XCTestCase {

    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11; c.hour = 18
        return Calendar.current.date(from: c)!
    }

    private func store() -> SessionStore {
        SessionStore(defaults: UserDefaults(suiteName: "abandon-recovery-\(UUID().uuidString)")!,
                     userDB: UserDatabase(path: ":memory:"))
    }

    private func session(done: Int, total: Int) -> ActiveSession {
        let sets = (0..<total).map {
            LoggedSet(num: $0 + 1, weight: "100", reps: "8", rpe: "", done: $0 < done)
        }
        let ex = LoggedExercise(id: "ex-1", name: "Barbell Back Squat", type: nil, unit: "lbs",
                                targetSets: total, targetReps: 8, rest: 90,
                                sets: sets, prevSets: [])
        return ActiveSession(templateId: "legs-1", name: "Leg day", category: "lift",
                             startTime: monday(), exercises: [ex], feel: nil, note: nil)
    }

    func test_painStopWithAreas_reportsHurt_andTheEntryKeepsTheAreas() throws {
        let s = store()
        var hurt: FeedbackEntry?
        var abandon: AbandonedWorkoutEntry?
        s.onHurtReported = { hurt = $0 }
        s.onAbandonRecorded = { abandon = $0 }
        let end = monday().addingTimeInterval(1800)

        s.saveAbandoned(session(done: 2, total: 12), reason: .pain, note: "left knee",
                        hurtAreas: ["knee", "hip", "knee"], endTime: end)

        let report = try XCTUnwrap(hurt)
        XCTAssertEqual(report.hurtAreas, ["hip", "knee"])
        XCTAssertNil(report.difficulty, "a pain stop is not a too-hard vote")
        XCTAssertEqual(report.date, end)
        XCTAssertEqual(report.sessionId, "legs-1")
        XCTAssertEqual(abandon?.hurtAreas, ["hip", "knee"])
    }

    func test_painStopAboveTheAbandonThreshold_stillReportsHurt() {
        let s = store()
        var hurt: FeedbackEntry?
        var abandon: AbandonedWorkoutEntry?
        s.onHurtReported = { hurt = $0 }
        s.onAbandonRecorded = { abandon = $0 }

        s.saveAbandoned(session(done: 10, total: 12), reason: .pain, note: nil, hurtAreas: ["shoulder"])

        XCTAssertNil(abandon, "83% done is a short workout, no abandonment")
        XCTAssertEqual(hurt?.hurtAreas, ["shoulder"])
    }

    func test_otherReasonsOrNoAreas_reportNothing() {
        for (reason, areas) in [(AbandonReason.feltOff, ["knee"]), (.timeOut, ["knee"]), (.pain, [])] {
            let s = store()
            var hurt: FeedbackEntry?
            var abandon: AbandonedWorkoutEntry?
            s.onHurtReported = { hurt = $0 }
            s.onAbandonRecorded = { abandon = $0 }
            s.saveAbandoned(session(done: 1, total: 12), reason: reason, note: nil, hurtAreas: areas)
            XCTAssertNil(hurt, "\(reason) \(areas)")
            XCTAssertNotNil(abandon)
            XCTAssertNil(abandon?.hurtAreas, "\(reason) \(areas)")
        }
    }

    /// RootTabView's onSessionSaved runs applyRecovery; the report has to be
    /// in memory by then.
    func test_hurtReport_firesBeforeSessionSaved() {
        let s = store()
        var order: [String] = []
        s.onHurtReported = { _ in order.append("hurt") }
        s.onSessionSaved = { _, _ in order.append("saved") }
        s.saveAbandoned(session(done: 1, total: 12), reason: .pain, note: nil, hurtAreas: ["knee"])
        XCTAssertEqual(order, ["hurt", "saved"])
    }

    func test_reportedKnee_easesQuadsAndHamstringsTheNextDay_andExpires() throws {
        let end = monday().addingTimeInterval(1800)
        let report = try XCTUnwrap(AbandonedWorkoutEntry.painFeedback(
            reason: .pain, hurtAreas: ["knee"], sessionId: nil, at: end))
        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        let thursday = Calendar.current.date(byAdding: .day, value: 3, to: monday())!

        let next = MuscleRecovery.status(on: tuesday, exposures: [], soreness: [],
                                         feedback: [report], now: monday())
        XCTAssertEqual(next.eased, ["quads", "hamstrings"])
        XCTAssertTrue(next.blocked.isEmpty)

        let later = MuscleRecovery.status(on: thursday, exposures: [], soreness: [],
                                          feedback: [report], now: monday())
        XCTAssertTrue(later.eased.isEmpty)
    }

    func test_everySheetJointMapsToABucket() {
        for area in FeedbackEntry.hurtAreaOptions {
            XCTAssertFalse(MuscleRecovery.buckets(forHurtArea: area).isEmpty, area)
        }
    }

    /// One too-hard vote stays under the two-vote trim; a pain report counted
    /// as a vote would push it over.
    func test_painReport_isNotCountedAsTooHard() throws {
        let now = monday().addingTimeInterval(3600)
        let report = AbandonedWorkoutEntry.painFeedback(
            reason: .pain, hurtAreas: ["knee"], sessionId: "legs-1", at: monday())!
        let m = TrainingMemory()
        let tooHard = FeedbackEntry(date: monday(), sessionId: "x", difficulty: "too_hard")
        let withPain = Planner.applyRecentSignalBias(memory: m, feedback: [tooHard, report], now: now)
        let without = Planner.applyRecentSignalBias(memory: m, feedback: [tooHard], now: now)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        XCTAssertEqual(try enc.encode(withPain), try enc.encode(without))
    }
}
