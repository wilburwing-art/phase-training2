import XCTest
@testable import PhaseTraining

@MainActor
final class WorkoutIntentTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_000_000)

    override func tearDown() {
        ActiveWorkoutRegistry.shared.drop()
        ActiveWorkoutRegistry.shared.store = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func defaults() -> UserDefaults {
        let suite = "WorkoutIntentTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func exercise(_ name: String, sets: Int, rest: Int = 90,
                          unit: String = "lbs", weight: String = "") -> LoggedExercise {
        LoggedExercise(id: "ex-\(name)", name: name, type: nil, unit: unit,
                       targetSets: sets, targetReps: 8, rest: rest,
                       sets: (0..<sets).map {
                           LoggedSet(num: $0 + 1, weight: weight, reps: "", rpe: "", done: false)
                       },
                       prevSets: [], supersetGroup: nil)
    }

    private func make(_ exercises: [LoggedExercise]) -> (ActiveWorkoutController, SessionStore) {
        let store = SessionStore(defaults: defaults())
        let session = ActiveSession(templateId: "t", name: "Test", category: "Custom",
                                    startTime: Date(), exercises: exercises,
                                    feel: nil, note: nil)
        store.saveActive(session)
        let c = ActiveWorkoutController(store: store, session: session,
                                        haptic: { _ in },
                                        now: { [unowned self] in clock })
        return (c, store)
    }

    private func allDone(_ c: ActiveWorkoutController) {
        for e in c.session.exercises.indices {
            for s in c.session.exercises[e].sets.indices {
                c.logSet(exIdx: e, setIdx: s, weight: nil, reps: "8", rpe: nil)
            }
        }
    }

    /// Bench set 1 logged, so a 90 s rest is counting down from `clock`.
    private func withRunningRest() -> ActiveWorkoutController {
        let (c, _) = make([exercise("Bench", sets: 3)])
        c.logSet(exIdx: 0, setIdx: 0, weight: "135", reps: "8", rpe: nil)
        XCTAssertNotNil(c.rest.remaining(at: clock))
        return c
    }

    // MARK: - No workout

    func test_everyActionWithNoControllerSaysNoWorkout() {
        XCTAssertEqual(WorkoutIntentActions.logSet(weight: 135, reps: 5, in: nil), "No workout running")
        XCTAssertEqual(WorkoutIntentActions.skipRest(in: nil, now: clock), "No workout running")
        XCTAssertEqual(WorkoutIntentActions.addRest(seconds: 15, in: nil, now: clock), "No workout running")
        XCTAssertEqual(WorkoutIntentActions.whatsNext(in: nil), "No workout running")
    }

    // MARK: - logSet

    func test_logSetMarksNextUpDoneWithWeightAndRepsAndReadsBack() {
        let (c, store) = make([exercise("Bench", sets: 3), exercise("Row", sets: 2)])
        let line = WorkoutIntentActions.logSet(weight: 135, reps: 5, in: c)
        let set = c.session.exercises[0].sets[0]
        XCTAssertTrue(set.done)
        XCTAssertEqual(set.weight, "135")
        XCTAssertEqual(set.reps, "5")
        XCTAssertEqual(line, SpokenCue.readback(exercise: c.session.exercises[0], setIdx: 0))
        XCTAssertEqual(line, "Bench, set 1, 135 for 5.")
        XCTAssertEqual(store.active, c.session)
        XCTAssertFalse(c.session.exercises[0].sets[1].done, "only the next-up set changes")
    }

    func test_logSetWithoutWeightKeepsTheSetsWeight() {
        let (c, _) = make([exercise("Bench", sets: 3, weight: "100")])
        _ = WorkoutIntentActions.logSet(weight: nil, reps: 8, in: c)
        XCTAssertEqual(c.session.exercises[0].sets[0].weight, "100")
        XCTAssertEqual(c.session.exercises[0].sets[0].reps, "8")
        XCTAssertTrue(c.session.exercises[0].sets[0].done)
    }

    func test_logSetFractionalWeightUsesSpokenFormat() {
        let (c, _) = make([exercise("Bench", sets: 3)])
        _ = WorkoutIntentActions.logSet(weight: 62.5, reps: 5, in: c)
        XCTAssertEqual(c.session.exercises[0].sets[0].weight, "62.5")
    }

    func test_logSetOnBodyweightIgnoresWeight() {
        let (c, _) = make([exercise("Pull-up", sets: 3, unit: LoggedExercise.bodyweightUnit)])
        let line = WorkoutIntentActions.logSet(weight: 135, reps: 10, in: c)
        let set = c.session.exercises[0].sets[0]
        XCTAssertTrue(set.done)
        XCTAssertEqual(set.weight, "")
        XCTAssertEqual(set.reps, "10")
        XCTAssertEqual(line, "Pull-up, set 1, 10 reps.")
    }

    func test_logSetRepsBelowOneChangesNothing() {
        let (c, store) = make([exercise("Bench", sets: 3)])
        let before = c.session
        XCTAssertEqual(WorkoutIntentActions.logSet(weight: 135, reps: 0, in: c), "Reps must be at least 1")
        XCTAssertEqual(WorkoutIntentActions.logSet(weight: 135, reps: -3, in: c), "Reps must be at least 1")
        XCTAssertEqual(c.session, before)
        XCTAssertEqual(store.active, before)
        XCTAssertNil(c.rest.startedAt)
    }

    func test_logSetOnFinishedSessionSaysAllLogged() {
        let (c, _) = make([exercise("Bench", sets: 2)])
        allDone(c)
        let before = c.session
        XCTAssertEqual(WorkoutIntentActions.logSet(weight: 135, reps: 5, in: c), "All sets are logged")
        XCTAssertEqual(c.session, before)
    }

    // MARK: - skipRest

    func test_skipRestClearsRunningRest() {
        let c = withRunningRest()
        XCTAssertEqual(WorkoutIntentActions.skipRest(in: c, now: clock), "Rest skipped")
        XCTAssertNil(c.rest.startedAt)
        XCTAssertNil(c.rest.remaining(at: clock))
    }

    func test_skipRestWithNoRestSaysNoRest() {
        let (c, _) = make([exercise("Bench", sets: 3)])
        XCTAssertEqual(WorkoutIntentActions.skipRest(in: c, now: clock), "No rest running")
    }

    func test_skipRestAfterRestExpiredSaysNoRest() {
        let c = withRunningRest()
        clock.addTimeInterval(91)
        XCTAssertEqual(WorkoutIntentActions.skipRest(in: c, now: clock), "No rest running")
    }

    // MARK: - addRest

    func test_addRestExtendsDuration() {
        let c = withRunningRest()
        XCTAssertEqual(WorkoutIntentActions.addRest(seconds: 15, in: c, now: clock), "Added 15 seconds")
        XCTAssertEqual(c.rest.duration, 105)
    }

    func test_addRestNegativeCuts() {
        let c = withRunningRest()
        XCTAssertEqual(WorkoutIntentActions.addRest(seconds: -30, in: c, now: clock), "Cut 30 seconds")
        XCTAssertEqual(c.rest.duration, 60)
    }

    func test_addRestCutPastElapsedEndsRest() {
        let c = withRunningRest()
        clock.addTimeInterval(60)
        XCTAssertEqual(WorkoutIntentActions.addRest(seconds: -45, in: c, now: clock), "Rest ended")
        XCTAssertNil(c.rest.startedAt)
    }

    func test_addRestWithNoRestSaysNoRest() {
        let (c, _) = make([exercise("Bench", sets: 3)])
        XCTAssertEqual(WorkoutIntentActions.addRest(seconds: 15, in: c, now: clock), "No rest running")
        XCTAssertNil(c.rest.duration)
    }

    // MARK: - whatsNext

    func test_whatsNextReturnsUpNextLine() {
        let (c, _) = make([exercise("Bench", sets: 3, weight: "135")])
        let line = WorkoutIntentActions.whatsNext(in: c)
        XCTAssertEqual(line, SpokenCue.upNext(next: c.nextUp()!, in: c.session) + ".")
        XCTAssertEqual(line, "Bench, set 1 of 3, 135 for 8.")
    }

    func test_whatsNextOnFinishedSessionSaysAllLogged() {
        let (c, _) = make([exercise("Bench", sets: 2)])
        allDone(c)
        XCTAssertEqual(WorkoutIntentActions.whatsNext(in: c), "All sets are logged")
    }

    // MARK: - Intent wiring (registry -> action)

    func test_logSetIntentActsOnRegisteredController() async throws {
        let (c, _) = make([exercise("Bench", sets: 3)])
        ActiveWorkoutRegistry.shared.current = c
        _ = try await LogSetIntent(reps: 5, weight: 135).perform()
        XCTAssertTrue(c.session.exercises[0].sets[0].done)
        XCTAssertEqual(c.session.exercises[0].sets[0].weight, "135")
        XCTAssertEqual(c.session.exercises[0].sets[0].reps, "5")
    }

    func test_skipRestIntentClearsRegisteredRest() async throws {
        clock = Date()
        let c = withRunningRest()
        ActiveWorkoutRegistry.shared.current = c
        _ = try await SkipRestIntent().perform()
        XCTAssertNil(c.rest.startedAt)
    }

    func test_addRestIntentExtendsRegisteredRest() async throws {
        clock = Date()
        let c = withRunningRest()
        ActiveWorkoutRegistry.shared.current = c
        _ = try await AddRestIntent(seconds: 15).perform()
        XCTAssertEqual(c.rest.duration, 105)
    }

    func test_whatsNextIntentReadsRegisteredControllerWithoutChangingIt() async throws {
        let (c, _) = make([exercise("Bench", sets: 3)])
        ActiveWorkoutRegistry.shared.current = c
        let before = c.session
        _ = try await WhatsNextIntent().perform()
        XCTAssertEqual(c.session, before)
    }

    func test_registryDoesNotKeepADroppedControllerAlive() {
        var (c, _): (ActiveWorkoutController?, SessionStore) = make([exercise("Bench", sets: 3)])
        ActiveWorkoutRegistry.shared.current = c
        XCTAssertNotNil(ActiveWorkoutRegistry.shared.current)
        c = nil
        XCTAssertNil(ActiveWorkoutRegistry.shared.current)
    }

    // MARK: - Registry builds from the store (log screen not open)

    private func storeWithActive(_ exercises: [LoggedExercise],
                                 start: Date = Date(timeIntervalSince1970: 500)) -> SessionStore {
        let store = SessionStore(defaults: defaults())
        store.saveActive(ActiveSession(templateId: "t", name: "Test", category: "Custom",
                                       startTime: start, exercises: exercises,
                                       feel: nil, note: nil))
        return store
    }

    func test_logSetIntentWithEmptyRegistryLogsIntoStoreActive() async throws {
        let store = storeWithActive([exercise("Bench", sets: 3)])
        ActiveWorkoutRegistry.shared.store = store
        XCTAssertNil(ActiveWorkoutRegistry.shared.current)
        _ = try await LogSetIntent(reps: 5, weight: 135).perform()
        let set = try XCTUnwrap(store.active?.exercises[0].sets[0])
        XCTAssertTrue(set.done)
        XCTAssertEqual(set.weight, "135")
        XCTAssertEqual(set.reps, "5")
    }

    func test_intentWithNoActiveWorkoutStillSaysNoWorkout() {
        ActiveWorkoutRegistry.shared.store = SessionStore(defaults: defaults())
        XCTAssertNil(ActiveWorkoutRegistry.shared.resolve())
        XCTAssertEqual(WorkoutIntentActions.whatsNext(in: ActiveWorkoutRegistry.shared.resolve()),
                       WorkoutIntentActions.noWorkout)
    }

    func test_resolveReusesTheBuiltControllerAcrossIntents() async throws {
        let store = storeWithActive([exercise("Bench", sets: 3)])
        ActiveWorkoutRegistry.shared.store = store
        _ = try await LogSetIntent(reps: 5, weight: 135).perform()
        let first = ActiveWorkoutRegistry.shared.resolve()
        _ = try await LogSetIntent(reps: 6, weight: 135).perform()
        XCTAssertTrue(first === ActiveWorkoutRegistry.shared.resolve())
        XCTAssertEqual(store.active?.exercises[0].sets[1].reps, "6")
    }

    func test_resolveRebuildsWhenAnotherWorkoutStarts() {
        let store = storeWithActive([exercise("Bench", sets: 3)])
        ActiveWorkoutRegistry.shared.store = store
        let first = ActiveWorkoutRegistry.shared.resolve()
        store.saveActive(ActiveSession(templateId: "t2", name: "Next", category: "Custom",
                                       startTime: Date(timeIntervalSince1970: 900),
                                       exercises: [exercise("Squat", sets: 2)],
                                       feel: nil, note: nil))
        let second = ActiveWorkoutRegistry.shared.resolve()
        XCTAssertFalse(first === second)
        XCTAssertEqual(second?.session.name, "Next")
    }

    func test_resolveDropsTheBuiltControllerWhenTheWorkoutEnds() {
        let store = storeWithActive([exercise("Bench", sets: 3)])
        ActiveWorkoutRegistry.shared.store = store
        XCTAssertNotNil(ActiveWorkoutRegistry.shared.resolve())
        store.clearActive()
        XCTAssertNil(ActiveWorkoutRegistry.shared.resolve())
    }

    func test_registeredControllerWinsOverTheStore() {
        let (c, store) = make([exercise("Bench", sets: 3)])
        ActiveWorkoutRegistry.shared.store = store
        ActiveWorkoutRegistry.shared.current = c
        XCTAssertTrue(ActiveWorkoutRegistry.shared.resolve() === c)
    }
}
