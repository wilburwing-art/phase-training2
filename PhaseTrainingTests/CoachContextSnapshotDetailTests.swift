// CoachContextSnapshotDetailTests.swift — guards build 106's two new
// snapshot blocks: LAST SESSION DETAIL + WEEK ADHERENCE.
//
// These are the highest-leverage signals to the LLM coach for workout
// planning quality (per the build-106 audit). If they ever stop appearing
// in the snapshot, the coach silently regresses to making decisions on
// thinner signal. Tests cover the formatting + the most important edges.

import XCTest
@testable import PhaseTraining

final class CoachContextSnapshotDetailTests: XCTestCase {

    // MARK: - LAST SESSION DETAIL

    func test_lastSessionDetail_rendersCollapsedWeightWhenConstant() {
        let session = SavedSession(
            templateId: "t1", name: "Push Day", category: "Lift",
            startTime: Date().addingTimeInterval(-86400),
            exercises: [
                LoggedExercise(
                    id: "e1", name: "Bench Press", type: nil, unit: "lb",
                    targetSets: 5, targetReps: 5, rest: 90,
                    sets: [
                        LoggedSet(num: 1, weight: "185", reps: "5", rpe: "8", done: true),
                        LoggedSet(num: 2, weight: "185", reps: "5", rpe: "8", done: true),
                        LoggedSet(num: 3, weight: "185", reps: "5", rpe: "9", done: true),
                        LoggedSet(num: 4, weight: "185", reps: "4", rpe: "9", done: true),
                        LoggedSet(num: 5, weight: "185", reps: "3", rpe: "9", done: true)
                    ],
                    prevSets: []
                )
            ],
            feel: nil, note: nil,
            endTime: Date().addingTimeInterval(-86400 + 3600),
            duration: 3600
        )
        guard let s = CoachContext.lastSessionDetailSection(sessions: [session]) else {
            return XCTFail("expected non-nil section")
        }
        XCTAssertTrue(s.contains("LAST SESSION DETAIL"))
        XCTAssertTrue(s.contains("Bench Press: 185 lb × 5,5,5,4,3"),
                      "constant-weight sets should collapse to a single weight + comma-listed reps")
        XCTAssertTrue(s.contains("top RPE 9"))
    }

    func test_lastSessionDetail_expandsWhenWeightsVary() {
        let session = SavedSession(
            templateId: "t2", name: "Squat Day", category: "Lift",
            startTime: Date().addingTimeInterval(-86400),
            exercises: [
                LoggedExercise(
                    id: "e2", name: "Back Squat", type: nil, unit: "lb",
                    targetSets: 3, targetReps: 5, rest: 180,
                    sets: [
                        LoggedSet(num: 1, weight: "225", reps: "5", rpe: "", done: true),
                        LoggedSet(num: 2, weight: "245", reps: "3", rpe: "", done: true),
                        LoggedSet(num: 3, weight: "265", reps: "1", rpe: "", done: true)
                    ],
                    prevSets: []
                )
            ],
            feel: nil, note: nil,
            endTime: Date(), duration: 3600
        )
        guard let s = CoachContext.lastSessionDetailSection(sessions: [session]) else {
            return XCTFail("expected non-nil section")
        }
        XCTAssertTrue(s.contains("225 lb×5, 245 lb×3, 265 lb×1"),
                      "varied weights should be listed per-set")
    }

    func test_lastSessionDetail_skipsWarmupsAndUndoneSets() {
        let session = SavedSession(
            templateId: "t3", name: "Push", category: "Lift",
            startTime: Date().addingTimeInterval(-3600),
            exercises: [
                LoggedExercise(
                    id: "e3", name: "Bench", type: nil, unit: "lb",
                    targetSets: 5, targetReps: 5, rest: 90,
                    sets: [
                        LoggedSet(num: 1, weight: "45", reps: "10", rpe: "", done: true, isWarmup: true),
                        LoggedSet(num: 2, weight: "135", reps: "5", rpe: "6", done: true, isWarmup: true),
                        LoggedSet(num: 3, weight: "185", reps: "5", rpe: "8", done: true),
                        LoggedSet(num: 4, weight: "185", reps: "5", rpe: "8", done: true),
                        LoggedSet(num: 5, weight: "185", reps: "5", rpe: "9", done: false)  // skipped
                    ],
                    prevSets: []
                )
            ],
            feel: nil, note: nil,
            endTime: Date(), duration: 3600
        )
        guard let s = CoachContext.lastSessionDetailSection(sessions: [session]) else {
            return XCTFail("expected non-nil section")
        }
        XCTAssertFalse(s.contains("45"), "warmup weights should not appear")
        XCTAssertFalse(s.contains("135"), "warmup weights should not appear")
        XCTAssertTrue(s.contains("Bench: 185 lb × 5,5"),
                      "only the 2 working sets that were actually done should render")
    }

    func test_lastSessionDetail_returnsNilWhenNoRecentSessions() {
        XCTAssertNil(CoachContext.lastSessionDetailSection(sessions: []))
    }

    func test_lastSessionDetail_skipsSessionsOlderThan14Days() {
        let session = SavedSession(
            templateId: "t4", name: "Stale", category: "Lift",
            startTime: Date().addingTimeInterval(-60 * 86400),
            exercises: [
                LoggedExercise(
                    id: "e4", name: "Bench", type: nil, unit: "lb",
                    targetSets: 5, targetReps: 5, rest: 90,
                    sets: [LoggedSet(num: 1, weight: "185", reps: "5", rpe: "", done: true)],
                    prevSets: []
                )
            ],
            feel: nil, note: nil,
            endTime: Date(), duration: 3600
        )
        XCTAssertNil(CoachContext.lastSessionDetailSection(sessions: [session]),
                     "sessions older than 14d shouldn't surface — signal stales")
    }

    // MARK: - WEEK ADHERENCE

    func test_weekAdherence_marksCompletedAndSkipped() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!

        let plan = WeekPlan(
            days: (0..<7).map { i in
                let date = cal.date(byAdding: .day, value: -6 + i, to: today)!
                let kind: DayKind = (i == 3 || i == 5) ? .lift : .rest  // 2 planned lifts
                return DayPlan(date: date, kind: kind, title: kind == .lift ? "Push Day" : "Rest")
            },
            generatedAt: Date(), inputsHash: "test"
        )
        // Completed one of the two planned lifts.
        let completedSession = SavedSession(
            templateId: "t", name: "Push Day", category: "Lift",
            startTime: threeDaysAgo,
            exercises: [
                LoggedExercise(
                    id: "e", name: "Bench", type: nil, unit: "lb",
                    targetSets: 3, targetReps: 5, rest: 90,
                    sets: [
                        LoggedSet(num: 1, weight: "185", reps: "5", rpe: "", done: true),
                        LoggedSet(num: 2, weight: "185", reps: "5", rpe: "", done: true),
                        LoggedSet(num: 3, weight: "185", reps: "5", rpe: "", done: true)
                    ],
                    prevSets: []
                )
            ],
            feel: nil, note: nil, endTime: twoDaysAgo, duration: 3600
        )
        guard let s = CoachContext.weekAdherenceSection(
            plan: plan, sessions: [completedSession], now: today
        ) else { return XCTFail("expected non-nil section") }
        XCTAssertTrue(s.contains("WEEK ADHERENCE"))
        XCTAssertTrue(s.contains("✓ completed"), "the day with a session should mark completed")
        XCTAssertTrue(s.contains("✗ skipped"), "the planned-lift day with no session should mark skipped")
        XCTAssertTrue(s.contains("1/2 past planned sessions completed"),
                      "tally should reflect 1 of 2 past planned sessions completed")
    }

    func test_weekAdherence_todayDoesNotCountAsSkipped() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let plan = WeekPlan(
            days: (0..<7).map { i in
                let date = cal.date(byAdding: .day, value: -6 + i, to: today)!
                let kind: DayKind = (i == 6) ? .lift : .rest  // today is the only planned lift
                return DayPlan(date: date, kind: kind, title: kind == .lift ? "Pull" : "Rest")
            },
            generatedAt: Date(), inputsHash: "test"
        )
        guard let s = CoachContext.weekAdherenceSection(
            plan: plan, sessions: [], now: today
        ) else { return XCTFail("expected non-nil section") }
        XCTAssertTrue(s.contains("planned (today)"),
                      "today's planned lift should show as 'planned (today)', not 'skipped'")
        XCTAssertTrue(s.contains("no past planned sessions"),
                      "tally should report no past planned sessions in this window")
    }
}
