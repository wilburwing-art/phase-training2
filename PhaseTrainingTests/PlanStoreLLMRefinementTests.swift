// PlanStoreLLMRefinementTests.swift — refineCurrentPlanWithLLM against a stub
// stream (PlanStore.RefinementStream). Covers what the user sees change: edited
// days survive, a bad model reply changes nothing, focus is pinned, and a plan
// replaced mid-flight is not stamped over. The pass is switched off in the app
// (llmRefinementConsumesStrategy), so these protect the day it is switched on.

import XCTest
@testable import PhaseTraining

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@MainActor
final class PlanStoreLLMRefinementTests: XCTestCase {

    private var suites: [String] = []

    override func tearDown() {
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "plan-llm-\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func memory() -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 3
        m.onboardedAt = Date()
        return m
    }

    private func seededStore() -> (PlanStore, TrainingMemory) {
        let m = memory()
        let store = PlanStore(defaults: freshDefaults(), today: Date())
        store.sessionStore = SessionStore(defaults: freshDefaults(), userDB: UserDatabase(path: ":memory:"))
        _ = store.generate(from: m, today: Date())
        return (store, m)
    }

    nonisolated private func buildWorkoutPayload(focus: String? = nil) -> Data {
        var obj: [String: Any] = ["reasoning": "stub", "intensityBias": "normal"]
        if let focus { obj["focus"] = focus }
        return try! JSONSerialization.data(withJSONObject: obj)
    }

    private func replying(with data: Data, counter: CallCounter? = nil) -> PlanStore.RefinementStream {
        { _, _, _ in
            counter?.bump()
            return AsyncThrowingStream { c in
                c.yield(.toolCall(id: "t1", name: "build_workout", input: data))
                c.finish()
            }
        }
    }

    private func liftIdx(_ plan: WeekPlan) -> [Int] {
        plan.days.indices.filter { plan.days[$0].kind == .lift }
    }

    // MARK: - Happy path

    func testRefinementStampsEveryLiftDayAndLeavesOthersAlone() async throws {
        let (store, m) = seededStore()
        let before = try XCTUnwrap(store.plan)
        XCTAssertEqual(liftIdx(before).count, 3)

        await store.refineCurrentPlanWithLLM(memory: m, stream: replying(with: buildWorkoutPayload()))

        let after = try XCTUnwrap(store.plan)
        for i in before.days.indices {
            if before.days[i].kind == .lift {
                XCTAssertNotNil(after.days[i].generatedWorkout?.refinedByLLMAt, "lift day \(i) should be stamped")
            } else {
                XCTAssertEqual(after.days[i], before.days[i], "non-lift day \(i) must be untouched")
            }
        }
    }

    func testFocusIsPinnedToTheDaysOwnFocusWhateverTheModelSays() async throws {
        let (store, m) = seededStore()
        let before = try XCTUnwrap(store.plan)
        // Every day gets told "legs"; only the leg day should stay legs.
        await store.refineCurrentPlanWithLLM(memory: m, stream: replying(with: buildWorkoutPayload(focus: "legs")))
        let after = try XCTUnwrap(store.plan)
        for i in liftIdx(before) {
            XCTAssertNotNil(before.days[i].generatedWorkout?.focus)
            XCTAssertEqual(after.days[i].generatedWorkout?.focus, before.days[i].generatedWorkout?.focus,
                           "day \(i) changed focus under the model's instruction")
        }
    }

    // MARK: - Days the pass must not touch

    func testOverrideDayAndAlreadyRefinedDayAreNotSentToTheModel() async throws {
        let (store, m) = seededStore()
        var plan = try XCTUnwrap(store.plan)
        let lifts = liftIdx(plan)
        let overrideDay = lifts[0], editedDay = lifts[1], plainDay = lifts[2]
        store.overrides.customRoutineByDate[plan.days[overrideDay].date] = "custom-1"
        plan.days[editedDay].generatedWorkout?.refinedByLLMAt = Date(timeIntervalSince1970: 1_000)
        store.setPlan(plan)
        let snapshot = try XCTUnwrap(store.plan)

        let counter = CallCounter()
        await store.refineCurrentPlanWithLLM(memory: m, stream: replying(with: buildWorkoutPayload(), counter: counter))

        let after = try XCTUnwrap(store.plan)
        XCTAssertEqual(counter.value, 1, "only the plain day is a candidate")
        XCTAssertEqual(after.days[overrideDay], snapshot.days[overrideDay])
        XCTAssertEqual(after.days[editedDay], snapshot.days[editedDay])
        XCTAssertNotEqual(after.days[plainDay].generatedWorkout?.refinedByLLMAt,
                          snapshot.days[plainDay].generatedWorkout?.refinedByLLMAt)
    }

    /// A day the user already logged is history; rewriting its planned weights
    /// afterwards changes what the week card claims they did. The candidate
    /// filter looks only at kind, refined flag and overrides, so it does not
    /// skip it.
    func testLoggedDayIsNotSentToTheModel() async throws {
        let (store, m) = seededStore()
        let plan = try XCTUnwrap(store.plan)
        let loggedIdx = liftIdx(plan)[0]
        let day = plan.days[loggedIdx]
        let start = day.date.addingTimeInterval(9 * 3600)
        store.sessionStore?.saveAll([SavedSession(
            templateId: "t", name: day.title, category: "c", startTime: start,
            exercises: [LoggedExercise(id: "e", name: "Bench Press", type: "Barbell", unit: "lbs",
                                       targetSets: 1, targetReps: 5, rest: 60,
                                       sets: [LoggedSet(num: 1, weight: "135", reps: "5", rpe: "", done: true)],
                                       prevSets: [])],
            feel: nil, note: nil, endTime: start.addingTimeInterval(3600), duration: 3600)])

        await store.refineCurrentPlanWithLLM(memory: m, stream: replying(with: buildWorkoutPayload()))

        XCTAssertNil(store.plan?.days[loggedIdx].generatedWorkout?.refinedByLLMAt)
    
    }

    // MARK: - Bad model output

    private func assertPlanUnchanged(_ stream: @escaping PlanStore.RefinementStream,
                                     file: StaticString = #filePath, line: UInt = #line) async throws {
        let (store, m) = seededStore()
        let before = try XCTUnwrap(store.plan, file: file, line: line)
        await store.refineCurrentPlanWithLLM(memory: m, stream: stream)
        XCTAssertEqual(store.plan, before, file: file, line: line)
    }

    func testUndecodablePayloadLeavesThePlanUnchanged() async throws {
        try await assertPlanUnchanged(replying(with: Data("not json".utf8)))
    }

    func testWrongShapeJSONLeavesThePlanUnchanged() async throws {
        try await assertPlanUnchanged(replying(with: Data(#"{"durationMinutes":"soon"}"#.utf8)))
    }

    func testReplyWithNoToolCallLeavesThePlanUnchanged() async throws {
        try await assertPlanUnchanged({ _, _, _ in
            AsyncThrowingStream { c in c.yield(.textDelta("Sure, here is a plan")); c.finish() }
        })
    }

    func testWrongToolNameLeavesThePlanUnchanged() async throws {
        try await assertPlanUnchanged({ [self] _, _, _ in
            let payload = buildWorkoutPayload()
            return AsyncThrowingStream { c in
                c.yield(.toolCall(id: "t", name: "propose_plan", input: payload)); c.finish()
            }
        })
    }

    func testStreamErrorLeavesThePlanUnchanged() async throws {
        try await assertPlanUnchanged({ _, _, _ in
            AsyncThrowingStream { c in c.finish(throwing: CoachClient.CoachError.dailyCeilingReached) }
        })
    }

    // MARK: - Plan replaced while the model was thinking

    func testResultIsDroppedWhenAFresherPlanReplacedTheOneRefined() async throws {
        let (store, m) = seededStore()
        let box = StoreBox(store)
        let stream: PlanStore.RefinementStream = { [self] _, _, _ in
            let payload = buildWorkoutPayload()
            return AsyncThrowingStream { c in
                Task {
                    // A newer regen lands before the reply does. The stream is
                    // not called on the main actor, so hop there to mutate.
                    await MainActor.run {
                        var p = box.store.plan!
                        p.inputsHash = "newer-plan"
                        box.store.setPlan(p)
                    }
                    c.yield(.toolCall(id: "t", name: "build_workout", input: payload))
                    c.finish()
                }
            }
        }
        await store.refineCurrentPlanWithLLM(memory: m, stream: stream)
        XCTAssertTrue(store.plan?.days.allSatisfy { $0.generatedWorkout?.refinedByLLMAt == nil } ?? false,
                      "a stale refinement must not stamp over the newer plan")
        XCTAssertEqual(store.plan?.inputsHash, "newer-plan")
    }
}

private final class StoreBox: @unchecked Sendable {
    let store: PlanStore
    init(_ s: PlanStore) { store = s }
}
