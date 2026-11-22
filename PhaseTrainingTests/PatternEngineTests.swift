// PatternEngineTests.swift — A4: suggestions from repeated behavior.
//
// Rules at, below and past their thresholds (session length, equipment
// stops, dropped exercise, viewed routine); the 28-day window; the cap;
// stable ids; dismiss cooldown and post-accept suppression; each accept action
// through PlanStore; the bundled-to-saved routine copy; the check-in counter
// with the new step; and the coach block leaving browse data out.

import XCTest
@testable import PhaseTraining

final class PatternEngineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    // MARK: - Fixtures

    private func outcome(_ daysAgo: Double, kind: DayOutcomeKind = .modified,
                         minutes: Int = 45, target: Int? = 45,
                         dropped: [String] = [], swaps: [ExerciseSwapPair] = []) -> DayOutcome {
        DayOutcome(sessionId: daysAgo * 1000 + Double(minutes), date: self.daysAgo(daysAgo), kind: kind,
                   plannedDayKind: .lift, plannedTitle: "Lower A",
                   plannedExercises: ["Back Squat", "Walking Lunge"], plannedWorkingSets: 8,
                   plannedMinutes: 45, targetMinutes: target,
                   loggedTemplateId: "gen-x", loggedTitle: "Lower A", loggedExercises: [],
                   completedWorkingSets: 8, durationMinutes: minutes,
                   swaps: swaps, dropped: dropped, added: [], recordedAt: self.daysAgo(daysAgo))
    }

    private func visit(_ daysAgo: Double, routine id: Int, name: String = "Ski Legs", opens: Int = 1) -> ExploreSession {
        let at = self.daysAgo(daysAgo)
        return ExploreSession(surface: .workoutCategory, startedAt: at, endedAt: at,
                              opens: Array(repeating: ExploreOpen(kind: .routine, id: String(id), name: name,
                                                                  query: nil, at: at), count: opens))
    }

    private func inputs(outcomes: [DayOutcome] = [], abandoned: [AbandonedWorkoutEntry] = [],
                        explore: [ExploreSession] = [], minutes: Int = 45,
                        affinities: [String: Int] = [:], saved: Set<String> = [],
                        decisions: [SuggestionDecision] = []) -> PatternEngine.Inputs {
        .init(outcomes: outcomes, abandoned: abandoned, explore: explore, sessionMinutes: minutes,
              affinities: affinities, savedRoutineNames: saved, decisions: decisions)
    }

    private func run(_ i: PatternEngine.Inputs) -> [Suggestion] { PatternEngine.suggestions(i, now: now) }

    // MARK: - Sessions run long

    func test_sessionLength_firesAtThreeOverrunsOfFive_andScalesTheLength() throws {
        let o = [outcome(1, minutes: 65), outcome(3, minutes: 60), outcome(5, minutes: 70),
                 outcome(7, minutes: 45), outcome(9, minutes: 44)]
        let s = try XCTUnwrap(run(inputs(outcomes: o)).first { $0.rule == .sessionLength })
        // median overrun 65 against 45: 45 * 45 / 65 = 31.2, rounds to 30.
        XCTAssertEqual(s.action, .setSessionMinutes(30))
        XCTAssertEqual(s.id, "sessionLength")
    }

    func test_sessionLength_twoOverrunsIsBelowThreshold() {
        let o = [outcome(1, minutes: 65), outcome(3, minutes: 60), outcome(5, minutes: 45)]
        XCTAssertFalse(run(inputs(outcomes: o)).contains { $0.rule == .sessionLength })
    }

    func test_sessionLength_ignoresSwitchedAndUnplannedDays() {
        let o = [outcome(1, kind: .switched, minutes: 90), outcome(2, kind: .unplanned, minutes: 90),
                 outcome(3, kind: .switched, minutes: 90)]
        XCTAssertTrue(run(inputs(outcomes: o)).isEmpty, "the planner did not size those sessions")
    }

    func test_sessionLength_firesOnTwoTimeOutAbandons() throws {
        let a = [AbandonedWorkoutEntry(date: daysAgo(2), plannedTitle: "A", reason: .timeOut, completionRatio: 0.4),
                 AbandonedWorkoutEntry(date: daysAgo(9), plannedTitle: "B", reason: .timeOut, completionRatio: 0.3)]
        let s = try XCTUnwrap(run(inputs(abandoned: a)).first)
        XCTAssertEqual(s.action, .setSessionMinutes(35))
    }

    func test_sessionLength_otherAbandonReasonsDoNotCount() {
        let a = [AbandonedWorkoutEntry(date: daysAgo(2), plannedTitle: "A", reason: .pain, completionRatio: 0.4),
                 AbandonedWorkoutEntry(date: daysAgo(9), plannedTitle: "B", reason: .timeOut, completionRatio: 0.3)]
        XCTAssertTrue(run(inputs(abandoned: a)).isEmpty)
    }

    func test_sessionLength_neverSuggestsBelow20OrAboveCurrent() throws {
        let o = (0..<3).map { outcome(Double($0 + 1), minutes: 200, target: 30) }
        let s = try XCTUnwrap(run(inputs(outcomes: o, minutes: 30)).first)
        XCTAssertEqual(s.action, .setSessionMinutes(20))
    }

    // MARK: - Equipment unavailable

    private func stop(_ daysAgo: Double, _ reason: AbandonReason = .equipmentUnavailable) -> AbandonedWorkoutEntry {
        AbandonedWorkoutEntry(date: self.daysAgo(daysAgo), plannedTitle: "A", reason: reason, completionRatio: 0.3)
    }

    func test_equipment_firesOnTwoStops_andNotOnOne() throws {
        XCTAssertTrue(run(inputs(abandoned: [stop(2)])).isEmpty)
        let s = try XCTUnwrap(run(inputs(abandoned: [stop(2), stop(9)])).first)
        XCTAssertEqual(s.id, "equipmentUnavailable")
        XCTAssertEqual(s.rule, .equipmentUnavailable)
        XCTAssertEqual(s.action, .reviewEquipment)
        XCTAssertEqual(s.acceptLabel, "Review my equipment")
        XCTAssertEqual(s.evidence, "2 workouts in the last 4 weeks stopped because equipment was unavailable.")
        XCTAssertEqual(s.eventDates, [daysAgo(2), daysAgo(9)])
    }

    func test_equipment_otherReasonsAndOldStopsDoNotCount() {
        XCTAssertTrue(run(inputs(abandoned: [stop(2), stop(3, .feltOff), stop(4, .pain)])).isEmpty)
        XCTAssertTrue(run(inputs(abandoned: [stop(2), stop(30)])).isEmpty, "the second stop is outside 28 days")
    }

    func test_equipment_andTimeOutStops_raiseTwoSeparateSuggestions() {
        let a = [stop(1), stop(3), stop(2, .timeOut), stop(5, .timeOut)]
        XCTAssertEqual(run(inputs(abandoned: a)).map(\.rule), [.sessionLength, .equipmentUnavailable])
    }

    func test_equipment_acceptedReturnsOnlyOnTwoNewStops() {
        let accepted = [SuggestionDecision(suggestionId: "equipmentUnavailable", accepted: true, at: daysAgo(5))]
        XCTAssertTrue(run(inputs(abandoned: [stop(1), stop(8), stop(10)], decisions: accepted)).isEmpty,
                      "one stop since the accept")
        XCTAssertEqual(run(inputs(abandoned: [stop(1), stop(3), stop(8)], decisions: accepted)).map(\.id),
                       ["equipmentUnavailable"])
    }

    // MARK: - Dropped exercise

    func test_dropped_firesAtThree_andNotAtTwo() {
        let two = [outcome(1, dropped: ["Walking Lunge"]), outcome(4, dropped: ["walking lunge"])]
        XCTAssertTrue(run(inputs(outcomes: two)).isEmpty)
        let three = two + [outcome(8, dropped: ["Walking Lunge"])]
        let s = run(inputs(outcomes: three)).first
        XCTAssertEqual(s?.id, "droppedExercise:walking lunge")
        XCTAssertEqual(s?.action, .sinkExercise(name: "Walking Lunge"))
    }

    func test_dropped_ignoresAbandonedSessions_andAlreadySunkExercises() {
        let abandoned = (1...3).map { outcome(Double($0), kind: .abandoned, dropped: ["Walking Lunge"]) }
        XCTAssertTrue(run(inputs(outcomes: abandoned)).isEmpty)
        let fine = (1...3).map { outcome(Double($0), dropped: ["Walking Lunge"]) }
        XCTAssertTrue(run(inputs(outcomes: fine, affinities: ["walking lunge": -2])).isEmpty)
    }

    func test_window_excludesEventsOlderThan28Days() {
        let o = [outcome(1, dropped: ["Walking Lunge"]), outcome(10, dropped: ["Walking Lunge"]),
                 outcome(29, dropped: ["Walking Lunge"])]
        XCTAssertTrue(run(inputs(outcomes: o)).isEmpty)
    }

    // MARK: - Viewed routine

    func test_viewedRoutine_countsVisitsNotTaps() {
        let tapsInOneVisit = [visit(1, routine: 12, opens: 5)]
        XCTAssertTrue(run(inputs(explore: tapsInOneVisit)).isEmpty)
        let threeVisits = [visit(1, routine: 12), visit(5, routine: 12), visit(9, routine: 12)]
        XCTAssertEqual(run(inputs(explore: threeVisits)).first?.action, .saveRoutine(routineId: 12, name: "Ski Legs"))
    }

    func test_viewedRoutine_skipsOneAlreadySaved() {
        let v = [visit(1, routine: 12), visit(5, routine: 12), visit(9, routine: 12)]
        XCTAssertTrue(run(inputs(explore: v, saved: ["ski legs"])).isEmpty)
    }

    // MARK: - Cap, order, decisions

    func test_capsAtThree() {
        let drops = ["A", "B", "C", "D"].flatMap { name in (1...3).map { outcome(Double($0), dropped: [name]) } }
        XCTAssertEqual(run(inputs(outcomes: drops)).count, PatternEngine.maxSuggestions)
    }

    func test_dismissed_staysQuietFor8Weeks_thenReturns() {
        let o = (1...3).map { outcome(Double($0), dropped: ["Walking Lunge"]) }
        let id = "droppedExercise:walking lunge"
        let recent = SuggestionDecision(suggestionId: id, accepted: false, at: daysAgo(10))
        XCTAssertTrue(run(inputs(outcomes: o, decisions: [recent])).isEmpty)
        let old = SuggestionDecision(suggestionId: id, accepted: false, at: daysAgo(60))
        XCTAssertEqual(run(inputs(outcomes: o, decisions: [old])).count, 1)
    }

    func test_accepted_returnsOnlyWhenEvidenceRebuildsAfterTheAccept() {
        let id = "sessionLength"
        let accept = SuggestionDecision(suggestionId: id, accepted: true, at: daysAgo(6))
        let before = [outcome(7, minutes: 70), outcome(8, minutes: 70), outcome(9, minutes: 70)]
        XCTAssertTrue(run(inputs(outcomes: before, decisions: [accept])).isEmpty,
                      "the sessions that justified the accept must not re-fire it")
        let after = [outcome(1, minutes: 70), outcome(2, minutes: 70), outcome(3, minutes: 70)]
        XCTAssertEqual(run(inputs(outcomes: after, decisions: [accept])).first?.id, id)
    }

    func test_ids_areStableAcrossRuns() {
        let o = (1...3).map { outcome(Double($0), dropped: ["Walking Lunge"]) }
        XCTAssertEqual(run(inputs(outcomes: o)).map(\.id), run(inputs(outcomes: o)).map(\.id))
    }

    // MARK: - Accept actions through PlanStore

    private struct Rig {
        let plan: PlanStore
        let memory: MemoryStore
        let custom: CustomRoutineStore
    }

    private func rig() -> Rig {
        let suite = "pattern-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let plan = PlanStore(defaults: d, today: now)
        let memory = MemoryStore(defaults: d)
        let custom = CustomRoutineStore(defaults: d, userDB: UserDatabase(path: ":memory:"))
        plan.memoryStore = memory
        plan.customStore = custom
        plan.exploreSessionsSince = { _ in [] }
        return Rig(plan: plan, memory: memory, custom: custom)
    }

    private func suggestion(_ action: SuggestionAction, id: String) -> Suggestion {
        Suggestion(id: id, rule: .sessionLength, title: "t", evidence: "e", acceptLabel: "a",
                   action: action, eventDates: [])
    }

    func test_accept_setsSessionMinutes_andRecordsTheDecision() {
        let r = rig()
        XCTAssertTrue(r.plan.acceptSuggestion(suggestion(.setSessionMinutes(30), id: "sessionLength"), now: now))
        XCTAssertEqual(r.memory.memory.sessionMinutes, 30)
        XCTAssertEqual(r.memory.memory.suggestionDecisions.map(\.accepted), [true])
    }

    func test_accept_sinksTheExercise_foldingCaseVariants() {
        let r = rig()
        r.memory.update { $0.exerciseAffinities = ["walking lunge": 2, "Walking Lunge": 1] }
        r.plan.acceptSuggestion(suggestion(.sinkExercise(name: "Walking Lunge"), id: "d"), now: now)
        XCTAssertEqual(r.memory.memory.exerciseAffinities, ["Walking Lunge": AthleteState.affinitySinkThreshold])
    }

    func test_accept_savesTheBundledRoutineWithItsRows() throws {
        let r = rig()
        let rows = CoachDatabase.shared.exercises(forRoutineId: 3)
        XCTAssertGreaterThan(rows.count, 2, "fixture routine 3 must exist in the bundled catalog")
        XCTAssertTrue(r.plan.acceptSuggestion(suggestion(.saveRoutine(routineId: 3, name: "Saved"), id: "v"), now: now))
        let saved = try XCTUnwrap(r.custom.routines.first { $0.name == "Saved" })
        XCTAssertEqual(saved.exercises.map(\.exerciseId), rows.sorted { $0.position < $1.position }.map(\.exerciseId))
        XCTAssertEqual(saved.exercises.map(\.position), Array(0..<rows.count))
    }

    func test_accept_reviewEquipment_writesNothingButRecordsTheDecision() {
        let r = rig()
        r.plan.abandonedWorkouts = [stop(1), stop(4)]
        let before = r.memory.memory.equipment
        let s = try! XCTUnwrap(r.plan.currentSuggestions(now: now).first)
        XCTAssertEqual(s.action, .reviewEquipment)
        XCTAssertTrue(r.plan.acceptSuggestion(s, now: now))
        XCTAssertEqual(r.memory.memory.equipment, before)
        XCTAssertEqual(r.memory.memory.suggestionDecisions.map(\.suggestionId), ["equipmentUnavailable"])
        XCTAssertTrue(r.plan.currentSuggestions(now: now).isEmpty)
    }

    func test_accept_unknownRoutine_failsAndRecordsNothing() {
        let r = rig()
        XCTAssertFalse(r.plan.acceptSuggestion(suggestion(.saveRoutine(routineId: -1, name: "X"), id: "v"), now: now))
        XCTAssertTrue(r.memory.memory.suggestionDecisions.isEmpty)
        XCTAssertTrue(r.custom.routines.isEmpty)
    }

    func test_dismiss_recordsAndSuppresses() {
        let r = rig()
        r.plan.dayOutcomes = (1...3).map { outcome(Double($0), dropped: ["Walking Lunge"]) }
        let s = try! XCTUnwrap(r.plan.currentSuggestions(now: now).first)
        r.plan.dismissSuggestion(s, now: now)
        XCTAssertTrue(r.plan.currentSuggestions(now: now).isEmpty)
    }

    func test_decisionsRoundTripThroughMemoryCoding() throws {
        var m = TrainingMemory()
        m.suggestionDecisions = [SuggestionDecision(suggestionId: "x", accepted: true, at: now)]
        let back = try JSONDecoder().decode(TrainingMemory.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.suggestionDecisions.map(\.suggestionId), ["x"])
    }

    // MARK: - Check-in counter and coach block

    func test_checkInCounter_ignoresBothPreSteps() {
        XCTAssertEqual(WeeklyCheckInStep.total, 4)
        XCTAssertEqual(WeeklyCheckInStep.patterns.humanIndex, 0)
        XCTAssertEqual(WeeklyCheckInStep.intent.humanIndex, 1)
        XCTAssertEqual(WeeklyCheckInStep.feedback.humanIndex, 4)
        XCTAssertEqual(WeeklyCheckInStep.preview.humanIndex, 0)
    }

    func test_coachBlock_leavesBrowseSuggestionsOut() throws {
        let viewed = Suggestion(id: "viewedRoutine:12", rule: .viewedRoutine, title: "You keep coming back to Ski Legs.",
                                evidence: "e", acceptLabel: "Save", action: .saveRoutine(routineId: 12, name: "Ski Legs"),
                                eventDates: [])
        XCTAssertNil(CoachContext.patternsSection(outcomes: [], suggestions: [viewed], now: now))
        let block = try XCTUnwrap(CoachContext.patternsSection(
            outcomes: [outcome(1, dropped: ["Walking Lunge"]), outcome(2, kind: .asPlanned)],
            suggestions: [viewed], now: now))
        XCTAssertTrue(block.contains("modified 1") && block.contains("asPlanned 1"))
        XCTAssertTrue(block.contains("Walking Lunge ×1"))
        XCTAssertFalse(block.contains("Ski Legs"))
    }
}
