// WeeklyCoachIntentTests.swift — PR 5 of the weekly-coach roadmap.
//
// Pins the new intent vocabulary the painted strip in PR 6 will produce:
//   - LiftFocus override on a DayKindOverride.lift
//   - WeekTone bias on WeekOverrides
//   - outOfTown event kind → bodyweight `.lift` template
//
// Tests stay focused — the broader planner invariants (7 contiguous days,
// shape distribution, etc.) live in PlannerTests.swift and aren't repeated
// here.

import XCTest
@testable import PhaseTraining

final class WeeklyCoachIntentTests: XCTestCase {

    // MARK: - Helpers

    private func memory() -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        return m
    }

    private func mondayAnchor() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11   // Monday, May 11, 2026
        return Calendar.current.date(from: c)!
    }

    private func emptyRoutineCatalog() -> [BundledRoutineRow] { [] }

    // MARK: - LiftFocus

    func test_liftFocus_mapsToWorkoutFocus() {
        XCTAssertEqual(LiftFocus.push.asWorkoutFocus, .push)
        XCTAssertEqual(LiftFocus.pull.asWorkoutFocus, .pull)
        XCTAssertEqual(LiftFocus.legs.asWorkoutFocus, .legs)
        XCTAssertEqual(LiftFocus.upper.asWorkoutFocus, .upper)
        XCTAssertEqual(LiftFocus.lower.asWorkoutFocus, .lower)
        // fullBody resolves to fullBodyA (variety rotation A/B is an
        // internal generator concern, not user-facing)
        XCTAssertEqual(LiftFocus.fullBody.asWorkoutFocus, .fullBodyA)
    }

    func test_dayOverride_carriesFocus() {
        let override: DayKindOverride = .lift(routineId: nil, focus: .push)
        XCTAssertEqual(override.liftFocus, .push)
        // Restriction: focus only applies to .lift; other kinds report nil
        XCTAssertNil(DayKindOverride.rest.liftFocus)
        XCTAssertNil(DayKindOverride.sport(sportSlug: nil).liftFocus)
    }

    func test_dayOverride_lift_codableRoundTrip_oldPayloadDecodesWithoutFocus() throws {
        // Old persisted JSON shape pre-PR-5: { "lift": { "routineId": 237 } }
        // After adding focus, decoding must still work with focus = nil.
        let oldJSON = #"{"lift":{"routineId":237}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DayKindOverride.self, from: oldJSON)
        if case .lift(let id, let focus) = decoded {
            XCTAssertEqual(id, 237)
            XCTAssertNil(focus)
        } else {
            XCTFail("expected .lift, got \(decoded)")
        }
    }

    func test_dayOverride_lift_codableRoundTrip_newPayloadCarriesFocus() throws {
        let original: DayKindOverride = .lift(routineId: nil, focus: .legs)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DayKindOverride.self, from: encoded)
        XCTAssertEqual(decoded.liftFocus, .legs)
    }

    func test_liftFocusOverride_routineWinsOverFocus() {
        // When the override has BOTH a routineId and a focus, the routine
        // is more specific and should win — focus gets ignored.
        var m = memory()
        let monday = mondayAnchor()
        let routine = BundledRoutineRow(
            id: 99, name: "Hand-Picked Routine", slug: "hand-picked",
            description: nil, goal: "strength", difficulty: "intermediate",
            phase: nil, durationMinutes: 45, environment: "gym",
            exerciseCount: 5, setCount: 12
        )
        var overrides = WeekOverrides(weekStart: monday)
        overrides.dayOverrides[monday] = .lift(routineId: 99, focus: .push)

        let plan = Planner.generate(
            memory: m,
            overrides: overrides,
            routines: [routine],
            today: monday
        )
        let mondaySlot = plan.days[0]
        XCTAssertEqual(mondaySlot.kind, .lift)
        XCTAssertEqual(mondaySlot.title, "Hand-Picked Routine",
                       "routine name should win when both routineId + focus are set")
        XCTAssertEqual(mondaySlot.routineId, 99)
    }

    // MARK: - WeekTone

    func test_applyWeekTone_typicalIsIdentity() {
        let base = GeneratorStrategy.auto
        let out = Planner.applyWeekTone(base: base, tone: .typical, sessionMinutes: 60)
        XCTAssertEqual(out, base)
    }

    func test_applyWeekTone_nilIsIdentity() {
        let base = GeneratorStrategy.auto
        let out = Planner.applyWeekTone(base: base, tone: nil, sessionMinutes: 60)
        XCTAssertEqual(out, base)
    }

    func test_applyWeekTone_recoverySetsDeload() {
        let base = GeneratorStrategy.auto
        let out = Planner.applyWeekTone(base: base, tone: .recovery, sessionMinutes: 60)
        XCTAssertEqual(out.intensityBias, .deload)
    }

    func test_applyWeekTone_buildSetsPush() {
        let base = GeneratorStrategy.auto
        let out = Planner.applyWeekTone(base: base, tone: .build, sessionMinutes: 60)
        XCTAssertEqual(out.intensityBias, .push)
    }

    func test_applyWeekTone_busyCompressesDuration() {
        let base = GeneratorStrategy.auto
        let out = Planner.applyWeekTone(base: base, tone: .busy, sessionMinutes: 60)
        // .busy multiplier is 0.7 → 60 * 0.7 = 42
        XCTAssertEqual(out.durationMinutes, 42)
        // intensityBias still .normal (busy uses time budget, not intensity)
        XCTAssertEqual(out.intensityBias, .normal)
    }

    func test_applyWeekTone_doesNotOverrideExplicitLLMIntensity() {
        // LLM said "push hard" — recovery tone must NOT overwrite.
        var base = GeneratorStrategy.auto
        base.intensityBias = .push
        let out = Planner.applyWeekTone(base: base, tone: .recovery, sessionMinutes: 60)
        XCTAssertEqual(out.intensityBias, .push,
                       "explicit LLM bias should win over tone-derived bias")
    }

    func test_applyWeekTone_doesNotOverrideExplicitLLMDuration() {
        // LLM set a specific duration; busy tone must NOT compress it further.
        var base = GeneratorStrategy.auto
        base.durationMinutes = 30
        let out = Planner.applyWeekTone(base: base, tone: .busy, sessionMinutes: 60)
        XCTAssertEqual(out.durationMinutes, 30,
                       "explicit LLM durationMinutes should win over tone compression")
    }

    func test_applyWeekTone_durationClampedTo15Minimum() {
        let base = GeneratorStrategy.auto
        // 15min * 0.7 = 10.5 → would round to 10, clamp pushes to 15
        let out = Planner.applyWeekTone(base: base, tone: .busy, sessionMinutes: 15)
        XCTAssertEqual(out.durationMinutes, 15,
                       "duration should never drop below the 15-minute floor")
    }

    // MARK: - WeekOverrides.weekTone field

    func test_weekTone_defaultsToNil() {
        let o = WeekOverrides(weekStart: mondayAnchor())
        XCTAssertNil(o.weekTone)
    }

    func test_weekOverrides_codableRoundTrip_withWeekTone() throws {
        var o = WeekOverrides(weekStart: mondayAnchor())
        o.weekTone = .recovery
        let encoded = try JSONEncoder().encode(o)
        let decoded = try JSONDecoder().decode(WeekOverrides.self, from: encoded)
        XCTAssertEqual(decoded.weekTone, .recovery)
    }

    func test_weekOverrides_codableRoundTrip_oldPayloadWithoutWeekTone() throws {
        // Build an "old shape" payload by encoding a WeekOverrides instance,
        // then surgically deleting the weekTone field from the JSON before
        // decoding. Avoids guessing the [Date: Foo] dictionary on-wire
        // format (which Swift encodes as a flat array of [k, v, k, v...]).
        var fresh = WeekOverrides(weekStart: mondayAnchor())
        fresh.weekTone = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let encoded = try encoder.encode(fresh)

        // Strip the weekTone key from the encoded JSON to simulate a
        // pre-PR-5 payload (the field literally didn't exist back then).
        var dict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        dict["weekTone"] = nil
        XCTAssertNil(dict["weekTone"], "verify weekTone is absent in this synthetic old shape")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(WeekOverrides.self, from: strippedData)
        XCTAssertNil(decoded.weekTone,
                     "decode should succeed and produce weekTone = nil for old payloads")
    }

    // MARK: - outOfTown event

    func test_outOfTown_producesBodyweightLiftDay() {
        let m = memory()
        let monday = mondayAnchor()
        let wednesday = Calendar.current.date(byAdding: .day, value: 2, to: monday)!
        var overrides = WeekOverrides(weekStart: monday)
        overrides.events = [WeekEvent(
            date: wednesday,
            title: "",
            kind: .outOfTown,
            sport: nil
        )]

        let plan = Planner.generate(
            memory: m,
            overrides: overrides,
            routines: emptyRoutineCatalog(),
            today: monday
        )
        let wedSlot = plan.days[2]
        XCTAssertEqual(wedSlot.kind, .lift, "out-of-town should render as .lift")
        XCTAssertTrue(wedSlot.protected, "event-driven days are protected")
        XCTAssertNotNil(wedSlot.generatedWorkout)
        XCTAssertEqual(wedSlot.generatedWorkout?.exercises.count, 5,
                       "travel template should ship the 5 bodyweight exercises")
        XCTAssertTrue(wedSlot.title.lowercased().contains("travel") ||
                      wedSlot.title.lowercased().contains("bodyweight"),
                      "title should signal the day is a travel/bodyweight one")
    }

    func test_outOfTown_titleOverrideUsesUserText() {
        let m = memory()
        let monday = mondayAnchor()
        let friday = Calendar.current.date(byAdding: .day, value: 4, to: monday)!
        var overrides = WeekOverrides(weekStart: monday)
        overrides.events = [WeekEvent(
            date: friday,
            title: "Boston trip",
            kind: .outOfTown,
            sport: nil
        )]

        let plan = Planner.generate(
            memory: m,
            overrides: overrides,
            routines: emptyRoutineCatalog(),
            today: monday
        )
        let fridaySlot = plan.days[4]
        XCTAssertEqual(fridaySlot.title, "Boston trip",
                       "user-provided event title should be respected")
        // Workout still gets populated
        XCTAssertNotNil(fridaySlot.generatedWorkout)
    }
}
