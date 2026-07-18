// CoachToolDecoderTests.swift — Phase 13 tool-input decoding.
//
// CoachToolDecoder.planEdits(for:in:) resolves yyyy-MM-dd dates against the
// supplied WeekPlan and emits [PlanEdit]. Silent skip when:
//   - date doesn't match any day in the plan
//   - required field missing for the op
//   - op string unrecognized
//
// These tests pin those behaviors so the model can't quietly corrupt the
// user's plan via a bad date or missing field.

import XCTest
@testable import PhaseTraining

final class CoachToolDecoderTests: XCTestCase {

    // MARK: - Fixture

    /// 7-day plan starting Monday 2026-05-18. Day0 = lift, Day1 = sport,
    /// Day3 = lift (Thursday), Day4 = rest (Friday), Day5 = sport.
    private func fixturePlan() -> (WeekPlan, df: DateFormatter) {
        // Match production's DateFormatter (CoachTools.planEdits) — neither
        // sets a timeZone, so both fall back to the system default. With
        // matching defaults the test passes on both a developer Mac
        // (typically MT/PT) and CI (UTC). Hardcoding Denver here caused
        // a 6-hour drift on UTC runners.
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let start = df.date(from: "2026-05-18")!
        let cal = Calendar.current
        let kinds: [DayKind] = [.lift, .sport, .rest, .lift, .rest, .sport, .rest]
        let titles = ["Push Day", "Climb", "Rest", "Pull Day", "Rest", "Trail run", "Rest"]
        let days = (0..<7).map { i in
            DayPlan(
                date: cal.date(byAdding: .day, value: i, to: start)!,
                kind: kinds[i],
                title: titles[i],
                routineId: kinds[i].isWorkout ? 100 + i : nil
            )
        }
        return (WeekPlan(days: days, generatedAt: Date(), inputsHash: "test"), df)
    }

    private func proposal(_ ops: [ProposalOp]) -> CoachProposal {
        CoachProposal(ops: ops, reasoning: "test")
    }

    // MARK: - decodeProposal (JSON → CoachProposal)

    func testDecodeProposalFromJSON() throws {
        let json = #"""
        {
          "edits": [
            {"op": "move", "fromDate": "2026-05-21", "toDate": "2026-05-22"},
            {"op": "shorten", "date": "2026-05-22", "toMinutes": 30}
          ],
          "reasoning": "Lighter Friday."
        }
        """#
        let p = try XCTUnwrap(CoachToolDecoder.decodeProposal(from: Data(json.utf8)))
        XCTAssertEqual(p.ops.count, 2)
        XCTAssertEqual(p.ops.first?.op, "move")
        XCTAssertEqual(p.reasoning, "Lighter Friday.")
        XCTAssertEqual(p.status, .pending)
    }

    // MARK: - move

    func testMoveResolvesDateToDayIdAndKeepsTargetDate() {
        let (plan, df) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "move", fromDate: "2026-05-21", toDate: "2026-05-22")
        ]), in: plan)
        XCTAssertEqual(edits.count, 1)
        if case .move(let dayId, let toDate) = edits[0] {
            XCTAssertEqual(dayId, plan.days[3].id, "Thursday is index 3")
            XCTAssertEqual(toDate, df.date(from: "2026-05-22"))
        } else { XCTFail("Expected .move") }
    }

    func testMoveSkippedWhenFromDateNotInPlan() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "move", fromDate: "2030-01-01", toDate: "2030-01-02")
        ]), in: plan)
        XCTAssertTrue(edits.isEmpty)
    }

    func testMoveSkippedWhenToDateMalformed() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "move", fromDate: "2026-05-21", toDate: "not-a-date")
        ]), in: plan)
        XCTAssertTrue(edits.isEmpty)
    }

    // MARK: - swap_kind

    func testSwapKindHappyPath() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "swap_kind", date: "2026-05-21", kind: "rest", title: "Rest")
        ]), in: plan)
        XCTAssertEqual(edits.count, 1)
        if case .swapKind(let dayId, let to, let title, _, _, _) = edits[0] {
            XCTAssertEqual(dayId, plan.days[3].id)
            XCTAssertEqual(to, .rest)
            XCTAssertEqual(title, "Rest")
        } else { XCTFail("Expected .swapKind") }
    }

    func testSwapKindFillsDefaultTitleWhenOmitted() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "swap_kind", date: "2026-05-21", kind: "sport")
        ]), in: plan)
        if case .swapKind(_, _, let title, _, _, _) = edits[0] {
            XCTAssertEqual(title, "Sport")
        } else { XCTFail() }
    }

    func testSwapKindSkippedWhenKindUnknown() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "swap_kind", date: "2026-05-21", kind: "yoga")
        ]), in: plan)
        XCTAssertTrue(edits.isEmpty)
    }

    // MARK: - protect_day

    func testProtectDayHappyPath() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "protect_day", date: "2026-05-23", eventTitle: "5k race")
        ]), in: plan)
        XCTAssertEqual(edits.count, 1)
        if case .protectDay(let dayId, let title) = edits[0] {
            XCTAssertEqual(dayId, plan.days[5].id)
            XCTAssertEqual(title, "5k race")
        } else { XCTFail() }
    }

    func testProtectDaySkippedWhenEventTitleEmpty() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "protect_day", date: "2026-05-23", eventTitle: "")
        ]), in: plan)
        XCTAssertTrue(edits.isEmpty)
    }

    // MARK: - shorten

    func testShortenClampedToRange() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "shorten", date: "2026-05-18", toMinutes: 5),    // below 15
            ProposalOp(op: "shorten", date: "2026-05-21", toMinutes: 999)   // above 180
        ]), in: plan)
        XCTAssertEqual(edits.count, 2)
        if case .shorten(_, let m1) = edits[0] { XCTAssertEqual(m1, 15) }
        if case .shorten(_, let m2) = edits[1] { XCTAssertEqual(m2, 180) }
    }

    func testShortenSkippedWhenMinutesMissing() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "shorten", date: "2026-05-18")
        ]), in: plan)
        XCTAssertTrue(edits.isEmpty)
    }

    // MARK: - add_session

    func testAddSessionHappyPath() {
        let (plan, df) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "add_session", date: "2026-05-22", kind: "lift", title: "Bonus pull")
        ]), in: plan)
        XCTAssertEqual(edits.count, 1)
        if case .addSession(let date, let kind, let title, _, _, _) = edits[0] {
            XCTAssertEqual(date, df.date(from: "2026-05-22"))
            XCTAssertEqual(kind, .lift)
            XCTAssertEqual(title, "Bonus pull")
        } else { XCTFail() }
    }

    // MARK: - add_session (sport session — closes the MTB coach dead-end)

    func testAddSessionSportCarriesSportSlugAndNote() {
        let (plan, df) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "add_session", date: "2026-05-22", kind: "sport",
                       title: "MTB", sportSlug: "mountain-biking",
                       note: "4x8min threshold climbs, 90s spin recovery")
        ]), in: plan)
        XCTAssertEqual(edits.count, 1)
        guard case .addSession(let date, let kind, _, _, let sport, let note) = edits[0] else {
            return XCTFail("Expected .addSession")
        }
        XCTAssertEqual(date, df.date(from: "2026-05-22"))
        XCTAssertEqual(kind, .sport)
        XCTAssertEqual(sport?.slug, "mountain-biking")
        XCTAssertEqual(note, "4x8min threshold climbs, 90s spin recovery")
    }

    func testApplyEditAddSportSessionSetsSportAndNotes() {
        let (plan0, df) = fixturePlan()
        var plan = plan0
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "add_session", date: "2026-05-22", kind: "sport",
                       title: "MTB", sportSlug: "cycling", note: "Z2 ride, 60min")
        ]), in: plan)
        XCTAssertEqual(edits.count, 1)
        PlanStore.applyEdit(edits[0], to: &plan)
        let cal = Calendar.current
        guard let day = plan.days.first(where: { cal.isDate($0.date, inSameDayAs: df.date(from: "2026-05-22")!) }) else {
            return XCTFail("day not found")
        }
        XCTAssertEqual(day.kind, .sport)
        XCTAssertEqual(day.sport?.slug, "cycling")
        XCTAssertEqual(day.notes, "Z2 ride, 60min")
    }

    // MARK: - remove_session

    func testRemoveSessionHappyPath() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "remove_session", date: "2026-05-21")
        ]), in: plan)
        XCTAssertEqual(edits.count, 1)
        if case .removeSession(let dayId) = edits[0] {
            XCTAssertEqual(dayId, plan.days[3].id)
        } else { XCTFail() }
    }

    // MARK: - mixed + unknown op

    func testUnknownOpSkippedButOthersSucceed() {
        let (plan, _) = fixturePlan()
        let edits = CoachToolDecoder.planEdits(for: proposal([
            ProposalOp(op: "teleport", date: "2026-05-18"),                     // unknown
            ProposalOp(op: "remove_session", date: "2026-05-21")                // valid
        ]), in: plan)
        XCTAssertEqual(edits.count, 1)
        if case .removeSession = edits[0] {} else { XCTFail("Expected the valid op to survive") }
    }

    // MARK: - decodeWorkoutProposal (build 99 — date field)

    func testWorkoutProposalUsesInputDateWhenProvided() {
        // The model targeted Thursday explicitly. Decoder must thread that
        // date through, not fall back to "today".
        let json = #"""
        {
          "changes": [{"op": "swap", "fromName": "Deadlift", "toName": "Trap Bar Deadlift"}],
          "reasoning": "Easier on the lower back.",
          "date": "2026-05-21"
        }
        """#
        let proposal = CoachToolDecoder.decodeWorkoutProposal(
            from: Data(json.utf8), fallbackDate: "2026-05-18")
        XCTAssertEqual(proposal?.dateString, "2026-05-21",
                       "Input date must win over fallback")
    }

    func testWorkoutProposalFallsBackWhenDateOmitted() {
        // No `date` in the input → fallback (today) is used. Preserves the
        // pre-build-99 behavior for plain "swap deadlifts" prompts.
        let json = #"""
        {
          "changes": [{"op": "adjust", "exerciseName": "Bench Press", "sets": 3}],
          "reasoning": "Drop a set."
        }
        """#
        let proposal = CoachToolDecoder.decodeWorkoutProposal(
            from: Data(json.utf8), fallbackDate: "2026-05-18")
        XCTAssertEqual(proposal?.dateString, "2026-05-18")
    }

    func testWorkoutProposalFallsBackWhenDateEmpty() {
        // Empty string is treated the same as missing — guards against the
        // model returning "" when it means "use the default".
        let json = #"""
        {
          "changes": [{"op": "swap", "fromName": "Squat", "toName": "Front Squat"}],
          "reasoning": "Lighter on the back.",
          "date": ""
        }
        """#
        let proposal = CoachToolDecoder.decodeWorkoutProposal(
            from: Data(json.utf8), fallbackDate: "2026-05-18")
        XCTAssertEqual(proposal?.dateString, "2026-05-18")
    }
}
