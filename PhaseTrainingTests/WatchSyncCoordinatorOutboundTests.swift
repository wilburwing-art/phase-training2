// WatchSyncCoordinatorOutboundTests.swift — the phone to watch direction.
// Drives the phone-edit ledger through the `store.$active` sink with
// SessionStore.saveActive, and checks the context the coordinator builds for
// the watch. WCSession itself is not exercised.

import XCTest
@testable import PhaseTraining

@MainActor
final class WatchSyncCoordinatorOutboundTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private var suites: [String] = []
    override func tearDown() {
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "watch-sync-out-\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func session(startTime: Date? = nil) -> ActiveSession {
        func ex(_ id: String, _ name: String) -> LoggedExercise {
            LoggedExercise(id: id, name: name, type: nil, unit: "lb", targetSets: 3, targetReps: 5, rest: 120,
                           sets: (1...3).map { LoggedSet(num: $0, weight: "135", reps: "5", rpe: "", done: false) },
                           prevSets: [], rpe: nil, tempo: nil)
        }
        return ActiveSession(templateId: "t", name: "Lower A", category: "Generated", startTime: startTime ?? start,
                             exercises: [ex("squat", "Barbell Back Squat"), ex("rdl", "Romanian Deadlift")],
                             feel: nil, note: nil)
    }

    private struct Rig {
        let sessions: SessionStore
        let plan: PlanStore
        let coordinator: WatchSyncCoordinator
        let defaults: UserDefaults
    }

    private func rig(active: ActiveSession? = nil) -> Rig {
        let defaults = freshDefaults()
        let sessions = SessionStore(defaults: freshDefaults(), userDB: UserDatabase(path: ":memory:"))
        if let active { sessions.saveActive(active) }
        let plan = PlanStore(defaults: freshDefaults(), today: Date())
        return Rig(sessions: sessions, plan: plan,
                   coordinator: WatchSyncCoordinator(store: sessions, planStore: plan, defaults: defaults),
                   defaults: defaults)
    }

    private func setReps(_ r: Rig, _ exIdx: Int, _ setIdx: Int, _ reps: String) {
        var edited = r.sessions.active!
        edited.exercises[exIdx].sets[setIdx].reps = reps
        r.sessions.saveActive(edited)
    }

    private func generated() -> GeneratedWorkout {
        let gex = GeneratedExercise(id: "g1", exerciseId: 1, name: "Bench", isCompound: true,
                                    sets: 3, reps: "5", restSeconds: 120)
        return GeneratedWorkout(title: "t", summary: "", exercises: [gex],
                                estimatedMinutes: 30, provenance: "")
    }

    private func weekPlan(todayKind: DayKind, generated: GeneratedWorkout?) -> WeekPlan {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<7).map { i in
            DayPlan(date: cal.date(byAdding: .day, value: i, to: today)!,
                    kind: i == 0 ? todayKind : .rest, title: i == 0 ? "Day" : "Rest",
                    routineId: nil, generatedWorkout: i == 0 ? generated : nil)
        }
        return WeekPlan(days: days, generatedAt: Date(), inputsHash: "test")
    }

    // MARK: - Phone edit ledger

    func testAChangedSetIsRecordedAsAPhoneEdit() {
        let r = rig(active: session())
        setReps(r, 0, 1, "6")
        let key = WatchSyncState.setKey(exerciseId: "squat", setNum: 2)
        XCTAssertEqual(Set(r.coordinator.state.phoneEdits.keys), [key])
        XCTAssertNotNil(r.defaults.data(forKey: WatchSyncCoordinator.stateKey))
    }

    func testUnchangedSetsAreNotRecorded() {
        let r = rig(active: session())
        setReps(r, 0, 1, "6")
        setReps(r, 0, 1, "7")
        XCTAssertEqual(Set(r.coordinator.state.phoneEdits.keys),
                       [WatchSyncState.setKey(exerciseId: "squat", setNum: 2)])
    }

    func testFirstSightOfASessionRecordsNothing() {
        let r = rig()
        r.sessions.saveActive(session())
        XCTAssertTrue(r.coordinator.state.phoneEdits.isEmpty)
    }

    func testANewSessionRecordsNothingForItsSets() {
        let r = rig(active: session())
        r.sessions.saveActive(session(startTime: start.addingTimeInterval(3600)))
        XCTAssertTrue(r.coordinator.state.phoneEdits.isEmpty)
    }

    func testWatchAppliedChangesAreNotRecordedAsPhoneEdits() {
        let r = rig(active: session())
        let e = WatchSyncEvent(sessionStart: start, exerciseId: "squat", setNum: 1,
                               kind: .setCompleted(weight: nil, reps: nil), at: start.addingTimeInterval(10))
        r.coordinator.apply([e])
        XCTAssertEqual(r.sessions.active?.exercises[0].sets[0].done, true)
        XCTAssertTrue(r.coordinator.state.phoneEdits.isEmpty)
    }

    // MARK: - Context

    func testPlannedTemplateRidesAlongWhenNothingIsActive() {
        let r = rig()
        let g = generated()
        let day = weekPlan(todayKind: .lift, generated: g).days[0]
        r.plan.plan = weekPlan(todayKind: .lift, generated: g)
        let template = day.workoutTemplate(planWeek: nil)!
        let planned = r.coordinator.context(for: nil).plannedSession
        XCTAssertNotNil(planned)
        XCTAssertEqual(planned?.name, template.name)
        XCTAssertEqual(planned?.exercises.map(\.name), template.exercises.map(\.name))
    }

    func testActiveSessionSuppressesThePlannedSession() {
        let r = rig()
        r.plan.plan = weekPlan(todayKind: .lift, generated: generated())
        let active = session()
        let context = r.coordinator.context(for: active)
        XCTAssertNil(context.plannedSession)
        XCTAssertEqual(context.activeSession, active)
    }

    func testNoPlanOrARestDayHasNoPlannedSession() {
        let r = rig()
        XCTAssertNil(r.coordinator.context(for: nil).plannedSession)
        r.plan.plan = weekPlan(todayKind: .rest, generated: nil)
        XCTAssertNil(r.coordinator.context(for: nil).plannedSession)
    }
}
