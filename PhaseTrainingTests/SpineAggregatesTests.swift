// SpineAggregatesTests.swift — 5a: per-spine aggregates on device.

import XCTest
@testable import PhaseTraining

final class SpineAggregatesTests: XCTestCase {

    private let monday = Date(timeIntervalSince1970: 1_759_104_000) // 2025-09-29, a Monday UTC

    private func o(_ routine: Int?, _ kind: DayOutcomeKind, day: Int = 0,
                   dropped: [String] = [], swaps: [ExerciseSwapPair] = []) -> DayOutcome {
        DayOutcome(sessionId: Double.random(in: 0...1e9), date: monday.addingTimeInterval(Double(day) * 86_400),
                   kind: kind, plannedDayKind: .lift, plannedTitle: nil, plannedRoutineId: routine,
                   plannedExercises: ["A", "B", "C", "D"], plannedWorkingSets: 12, plannedMinutes: nil,
                   targetMinutes: nil, loggedTemplateId: "", loggedTitle: "", loggedExercises: [],
                   completedWorkingSets: 0, durationMinutes: 0, swaps: swaps, dropped: dropped, added: [],
                   recordedAt: monday)
    }

    func test_countsCompletionDropPositionSwapsAndWeeks() throws {
        let swap = ExerciseSwapPair(planned: "B", logged: "B2")
        let rows = [o(7, .asPlanned), o(7, .modified, day: 2, dropped: ["D"], swaps: [swap]),
                    o(7, .modified, day: 9, dropped: ["b", "D"], swaps: [swap]), o(7, .abandoned, day: 10, dropped: ["C", "D"]),
                    o(9, .asPlanned), o(nil, .asPlanned)]
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let all = SpineAggregates.make(outcomes: rows, calendar: utc)
        XCTAssertEqual(all.map(\.routineId), [7, 9], "outcomes with no routine are not a spine")
        let a = try XCTUnwrap(all.first)
        XCTAssertEqual(a.sessions, 4)
        XCTAssertEqual(a.byKind[.modified], 2)
        XCTAssertEqual(a.completionRate, 0.25, accuracy: 1e-9)
        // First drops at positions 3 (D), 1 (b, case-insensitive), 2 (C): median 2.
        XCTAssertEqual(a.medianFirstDropPosition, 2)
        XCTAssertEqual(a.substitutions.first?.pair, swap)
        XCTAssertEqual(a.substitutions.first?.count, 2)
        XCTAssertEqual(a.weeks.count, 2, "days 0 and 2 share an ISO week; 9 and 10 share the next")
    }

    func test_noDrops_meansNoMedian_andEmptyInputIsEmpty() {
        XCTAssertNil(SpineAggregates.make(outcomes: [o(3, .asPlanned)]).first?.medianFirstDropPosition)
        XCTAssertTrue(SpineAggregates.make(outcomes: []).isEmpty)
    }

    func test_outcomeRecordsTheAuthoredRoutine_includingADisplacedOriginal() {
        var planned = GeneratedWorkout(title: "Spine", summary: "", exercises: [], estimatedMinutes: 45, provenance: "Authored")
        planned.authoredRoutineId = 295
        let day = DayPlan(date: monday, kind: .lift, title: "Spine", routineId: nil,
                          generatedWorkout: planned, generatedReason: "test")
        let session = SavedSession(templateId: "x", name: "x", category: "", startTime: monday, exercises: [],
                                   feel: nil, note: nil, endTime: monday, duration: 0)
        XCTAssertEqual(DayOutcome.derive(session: session, plannedDay: day, displaced: nil,
                                         abandoned: false, targetMinutes: nil, now: monday).plannedRoutineId, 295)
        let displaced = DisplacedPlan(kind: .lift, title: "Spine", workout: planned, reason: nil, routineId: nil)
        let customDay = DayPlan(date: monday, kind: .lift, title: "Mine", routineId: nil,
                                generatedWorkout: GeneratedWorkout(title: "Mine", summary: "", exercises: [],
                                                                   estimatedMinutes: 30, provenance: "custom"),
                                generatedReason: "test")
        XCTAssertEqual(DayOutcome.derive(session: session, plannedDay: customDay, displaced: displaced,
                                         abandoned: false, targetMinutes: nil, now: monday).plannedRoutineId, 295,
                       "a switched day credits the spine the planner scheduled")
    }
}
