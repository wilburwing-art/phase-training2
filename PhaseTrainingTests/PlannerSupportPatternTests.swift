// PlannerSupportPatternTests.swift — characterization tests for
// Planner.applySupportPattern, the primary/support de-confliction pass
// (PLAN-primary-support.md, phase 2 wiring).
//
// Like PlannerTaperPromotionTests, this exercises the pure slot-array
// transform directly with hand-built [DayPlan?] fixtures — no
// Planner.generate, no coach.db, no wall clock. Dates anchor to a fixed
// Monday so weekday mapping is deterministic across CI clocks.

import XCTest
@testable import PhaseTraining

final class PlannerSupportPatternTests: XCTestCase {

    // MARK: - Fixtures (mirror PlannerTaperPromotionTests conventions)

    private func mondayAnchor() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11   // Monday, May 11, 2026
        return Calendar.current.date(from: c)!
    }

    private func weekDates() -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: mondayAnchor())
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    /// A synthetic lift workout with a controllable exercise count / load.
    private func liftWorkout(_ tag: String, count: Int = 4, sets: Int = 4) -> GeneratedWorkout {
        let ex = (0..<count).map { i in
            GeneratedExercise(id: "\(tag)-\(i)", exerciseId: 2000 + i,
                              name: "\(tag) ex\(i)", isCompound: i == 0,
                              sets: sets, reps: "5", restSeconds: 120, rpe: "8")
        }
        return GeneratedWorkout(title: "Lift \(tag)", summary: "\(count) movements",
                                exercises: ex, estimatedMinutes: 45,
                                provenance: "test", focus: .fullBodyA)
    }

    /// Build a week of slots. `lifts` maps slot index → workout for lift days.
    private func makeSlots(_ kinds: [DayKind], dates: [Date],
                           lifts: [Int: GeneratedWorkout] = [:],
                           protectedIdx: Set<Int> = []) -> [DayPlan?] {
        kinds.enumerated().map { i, kind in
            DayPlan(date: dates[i], kind: kind,
                    title: kind == .lift ? "Lift" : (kind == .sport ? "Sport" : "Rest"),
                    generatedWorkout: lifts[i],
                    protected: protectedIdx.contains(i),
                    generatedReason: "fixture")
        }
    }

    private func sport(_ slug: String) -> Sport { Sport.catalog.first { $0.slug == slug }! }

    /// Ski-primary memory with a declared climbing support pattern.
    private func memory(_ days: [(Weekday, SupportMagnitude)],
                        variant: SportVariant = .sportRoute) -> TrainingMemory {
        var m = TrainingMemory()
        m.primarySport = sport("alpine-skiing")
        m.seasonsBySport = [sport("alpine-skiing"): .offSeason]
        m.defaultSeason = .offSeason
        m.supportPattern = SupportPattern(
            sportSlug: "climbing", variant: variant,
            days: days.map { SupportDay(weekday: $0.0, magnitude: $0.1) })
        return m
    }

    // Weekday → slot index (Monday-first week): monday(1) → 0 … sunday(7) → 6.
    private func idx(_ w: Weekday) -> Int { w.rawValue - 1 }

    // MARK: - Stamping

    func test_support_day_stamped_onto_rest_slot() {
        let dates = weekDates()
        // Mon lift, Tue rest, Wed rest, Thu lift, Fri rest, Sat rest, Sun rest.
        var slots = makeSlots([.lift, .rest, .rest, .lift, .rest, .rest, .rest], dates: dates,
                              lifts: [0: liftWorkout("A"), 3: liftWorkout("B")])
        let m = memory([(.saturday, .big)])
        Planner.applySupportPattern(&slots, memory: m, calendar: .current)

        let sat = slots[idx(.saturday)]!
        XCTAssertEqual(sat.kind, .sport)
        XCTAssertEqual(sat.sport?.slug, "climbing")
        XCTAssertTrue(sat.title.lowercased().contains("big"), "magnitude in title: \(sat.title)")
        XCTAssertTrue(sat.generatedReason?.contains("Sat") == true)
    }

    func test_stamp_skips_protected_and_lift_slots() {
        let dates = weekDates()
        // Declare a support day on Monday (a LIFT) and Tuesday (PROTECTED rest).
        var slots = makeSlots([.lift, .rest, .rest, .lift, .rest, .rest, .rest], dates: dates,
                              lifts: [0: liftWorkout("A"), 3: liftWorkout("B")],
                              protectedIdx: [1])
        let m = memory([(.monday, .medium), (.tuesday, .medium)])
        Planner.applySupportPattern(&slots, memory: m, calendar: .current)

        XCTAssertEqual(slots[idx(.monday)]!.kind, .lift, "must not overwrite a lift day")
        XCTAssertEqual(slots[idx(.tuesday)]!.kind, .rest, "must not overwrite a protected slot")
        XCTAssertEqual(slots[idx(.tuesday)]!.generatedReason, "fixture")
    }

    // MARK: - Lift reflow

    func test_lift_in_big_day_buffer_is_lightened() {
        let dates = weekDates()
        // Fri lift, Sat big trad/alpine climb (restDaysBefore 2 → Fri violates).
        var slots = makeSlots([.rest, .rest, .rest, .rest, .lift, .rest, .rest], dates: dates,
                              lifts: [4: liftWorkout("Fri", count: 5)])
        let m = memory([(.saturday, .big)], variant: .tradAlpine)
        Planner.applySupportPattern(&slots, memory: m, calendar: .current)

        let fri = slots[idx(.friday)]!
        XCTAssertLessThan(fri.generatedWorkout!.exercises.count, 5, "buffer collision lightens the lift")
        XCTAssertGreaterThanOrEqual(fri.generatedWorkout!.exercises.count, 3, "floor 3")
        XCTAssertNotEqual(fri.generatedReason, "fixture", "adjustment reason recorded")
    }

    func test_lift_far_from_support_is_untouched() {
        let dates = weekDates()
        // Mon lift, Sat medium sport climb (restDaysBefore 1) — Mon is far.
        var slots = makeSlots([.lift, .rest, .rest, .rest, .rest, .rest, .rest], dates: dates,
                              lifts: [0: liftWorkout("Mon", count: 4)])
        let m = memory([(.saturday, .medium)])   // sportRoute medium = 0.3 equiv, no budget drop
        Planner.applySupportPattern(&slots, memory: m, calendar: .current)

        let mon = slots[idx(.monday)]!
        XCTAssertEqual(mon.generatedWorkout!.exercises.count, 4)
        XCTAssertEqual(mon.generatedReason, "fixture")
    }

    // MARK: - Safety

    func test_no_support_pattern_is_a_noop() {
        let dates = weekDates()
        var m = TrainingMemory()
        m.primarySport = sport("alpine-skiing")
        m.supportPattern = nil
        var slots = makeSlots([.lift, .rest, .rest, .lift, .rest, .rest, .rest], dates: dates,
                              lifts: [0: liftWorkout("A"), 3: liftWorkout("B")])
        let before = slots
        Planner.applySupportPattern(&slots, memory: m, calendar: .current)
        XCTAssertEqual(slots, before, "no pattern → single-sport behavior unchanged")
    }
}
