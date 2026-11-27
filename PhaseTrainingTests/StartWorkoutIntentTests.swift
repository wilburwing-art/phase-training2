import XCTest
@testable import PhaseTraining

@MainActor
final class StartWorkoutIntentTests: XCTestCase {
    private let cal = Calendar.current
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    // MARK: - Fixtures

    private var today: Date { cal.startOfDay(for: Date()) }

    private func snapshot(_ kind: TodayWidgetDay.Kind, title: String, done: Bool = false,
                          on date: Date? = nil) -> TodayWidgetSnapshot {
        TodayWidgetSnapshot(days: [
            TodayWidgetDay(date: date ?? today, kind: kind, title: title, detail: nil, done: done),
        ])
    }

    private func makeStore(onboarded: Bool = true, imperial: Bool) -> MemoryStore {
        let name = "start-workout-intent-tests-\(UUID().uuidString)"
        suiteNames.append(name)
        let store = MemoryStore(defaults: UserDefaults(suiteName: name)!)
        store.update {
            $0.usesImperial = imperial
            $0.onboardedAt = onboarded ? Date() : nil
        }
        return store
    }

    // MARK: - Start rules

    func test_activeWorkout_resumesAndRaises() {
        let launch = StartWorkoutLaunch()
        let line = launch.request(snapshot: snapshot(.rest, title: "Rest day"), hasActiveWorkout: true, onboarded: true,
                                  now: Date(), calendar: cal)
        XCTAssertEqual(line, StartWorkoutLaunch.resumingLine)
        XCTAssertTrue(launch.pending)
        XCTAssertTrue(launch.showToday)
    }

    func test_noSnapshot_opensTodayAndRaises() {
        let launch = StartWorkoutLaunch()
        let line = launch.request(snapshot: nil, hasActiveWorkout: false, onboarded: true, now: Date(), calendar: cal)
        XCTAssertEqual(line, StartWorkoutLaunch.openingTodayLine)
        XCTAssertTrue(launch.pending)
        XCTAssertTrue(launch.showToday)
    }

    func test_snapshotWithoutToday_opensTodayAndRaises() {
        let launch = StartWorkoutLaunch()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let line = launch.request(snapshot: snapshot(.lift, title: "Upper Day 1", on: yesterday),
                                  hasActiveWorkout: false, onboarded: true, now: Date(), calendar: cal)
        XCTAssertEqual(line, StartWorkoutLaunch.openingTodayLine)
        XCTAssertTrue(launch.pending)
        XCTAssertTrue(launch.showToday)
    }

    func test_openLiftDay_startsAndRaises() {
        let launch = StartWorkoutLaunch()
        let line = launch.request(snapshot: snapshot(.lift, title: "Upper Day 1"),
                                  hasActiveWorkout: false, onboarded: true, now: Date(), calendar: cal)
        XCTAssertEqual(line, StartWorkoutLaunch.startingLine("Upper Day 1"))
        XCTAssertEqual(line, "Starting Upper Day 1.")
        XCTAssertTrue(launch.pending)
        XCTAssertTrue(launch.showToday)
    }

    func test_loggedLiftDay_doesNotRaise() {
        let launch = StartWorkoutLaunch()
        let line = launch.request(snapshot: snapshot(.lift, title: "Upper Day 1", done: true),
                                  hasActiveWorkout: false, onboarded: true, now: Date(), calendar: cal)
        XCTAssertEqual(line, StartWorkoutLaunch.alreadyLoggedLine)
        XCTAssertFalse(launch.pending)
        XCTAssertTrue(launch.showToday)
    }

    func test_restDay_doesNotRaise() {
        let launch = StartWorkoutLaunch()
        let line = launch.request(snapshot: snapshot(.rest, title: "Rest day"),
                                  hasActiveWorkout: false, onboarded: true, now: Date(), calendar: cal)
        XCTAssertEqual(line, StartWorkoutLaunch.restDayLine)
        XCTAssertFalse(launch.pending)
        XCTAssertTrue(launch.showToday)
    }

    func test_sportAndEventDays_sayTitleAndDoNotRaise() {
        for (kind, title) in [(TodayWidgetDay.Kind.sport, "Skiing"), (.event, "Race day")] {
            let launch = StartWorkoutLaunch()
            let line = launch.request(snapshot: snapshot(kind, title: title),
                                      hasActiveWorkout: false, onboarded: true, now: Date(), calendar: cal)
            XCTAssertEqual(line, StartWorkoutLaunch.todayIsLine(title))
            XCTAssertEqual(line, "Today is \(title).")
            XCTAssertFalse(launch.pending, "\(kind)")
            XCTAssertTrue(launch.showToday, "\(kind)")
        }
    }

    func test_consume_trueOnceThenFalse() {
        let launch = StartWorkoutLaunch()
        XCTAssertFalse(launch.consume())
        _ = launch.request(snapshot: nil, hasActiveWorkout: false, onboarded: true, now: Date(), calendar: cal)
        XCTAssertTrue(launch.consume())
        XCTAssertFalse(launch.consume())
        XCTAssertFalse(launch.pending)
    }

    func test_consumeShowToday_trueOnceThenFalse() {
        let launch = StartWorkoutLaunch()
        XCTAssertFalse(launch.consumeShowToday())
        _ = launch.request(snapshot: snapshot(.rest, title: "Rest day"),
                           hasActiveWorkout: false, onboarded: true, now: Date(), calendar: cal)
        XCTAssertTrue(launch.consumeShowToday())
        XCTAssertFalse(launch.consumeShowToday())
    }

    func test_notOnboarded_doesNotRaise() {
        let launch = StartWorkoutLaunch()
        let line = launch.request(snapshot: snapshot(.lift, title: "Upper Day 1"),
                                  hasActiveWorkout: false, onboarded: false, now: Date(), calendar: cal)
        XCTAssertEqual(line, StartWorkoutLaunch.notOnboardedLine)
        XCTAssertFalse(launch.pending)
        XCTAssertTrue(launch.showToday)
    }

    func test_consume_staleRequestLapsesAndDrops() {
        let launch = StartWorkoutLaunch()
        let asked = Date()
        _ = launch.request(snapshot: nil, hasActiveWorkout: false, onboarded: true, now: asked, calendar: cal)
        let late = asked.addingTimeInterval(StartWorkoutLaunch.pendingLifetime + 1)
        XCTAssertFalse(launch.consume(now: late))
        XCTAssertFalse(launch.pending)
    }

    func test_consume_freshRequestInsideLifetime() {
        let launch = StartWorkoutLaunch()
        let asked = Date()
        _ = launch.request(snapshot: nil, hasActiveWorkout: false, onboarded: true, now: asked, calendar: cal)
        XCTAssertTrue(launch.consume(now: asked.addingTimeInterval(StartWorkoutLaunch.pendingLifetime - 1)))
    }

    // MARK: - Live plan (11c 7.3)

    private func liftWeek(title: String) -> WeekPlan {
        let monday = cal.startOfDay(for: Date().startOfTrainingWeek())
        let days = (0..<7).map { i -> DayPlan in
            let date = cal.date(byAdding: .day, value: i, to: monday)!
            let ex = [GeneratedExercise(id: "a", exerciseId: 1, name: "Bench", isCompound: true,
                                        sets: 4, reps: "5", restSeconds: 120)]
            let workout = GeneratedWorkout(title: title, summary: "", exercises: ex,
                                           estimatedMinutes: 45, provenance: "test")
            return DayPlan(date: date, kind: .lift, title: "Lift", generatedWorkout: workout)
        }
        return WeekPlan(days: days, generatedAt: Date(), inputsHash: "test")
    }

    private func makePlanStore() -> PlanStore {
        let name = "start-workout-intent-plan-\(UUID().uuidString)"
        suiteNames.append(name)
        return PlanStore(defaults: UserDefaults(suiteName: name)!)
    }

    /// The template `TodayScreen.template` starts with no active session.
    private func startedName(_ planStore: PlanStore) -> String? {
        planStore.plan?.today(calendar: cal)?.workoutTemplate(planWeek: nil)?.name
    }

    func test_planChangeAfterSnapshot_lineNamesTheStartedTemplate() throws {
        let planStore = makePlanStore()
        planStore.plan = liftWeek(title: "Upper Day 1")
        let stale = try XCTUnwrap(TodayWidgetPublisher.snapshot(planStore: planStore, sessions: [], calendar: cal))
        planStore.plan = liftWeek(title: "Lower Day 2")

        let snap = StartWorkoutLaunch.todaySnapshot(planStore: planStore, sessions: [],
                                                    stored: { stale }, calendar: cal)
        let line = StartWorkoutLaunch().request(snapshot: snap, hasActiveWorkout: false, onboarded: true,
                                                now: Date(), calendar: cal)
        XCTAssertEqual(startedName(planStore), "Lower Day 2")
        XCTAssertEqual(line, StartWorkoutLaunch.startingLine("Lower Day 2"))
    }

    func test_noLiveStore_readsStoredSnapshot() {
        let stored = snapshot(.lift, title: "Upper Day 1")
        let snap = StartWorkoutLaunch.todaySnapshot(planStore: nil, sessions: [],
                                                    stored: { stored }, calendar: cal)
        XCTAssertEqual(snap, stored)
    }

    func test_liveStoreWithoutPlan_ignoresStoredSnapshot() {
        let snap = StartWorkoutLaunch.todaySnapshot(planStore: makePlanStore(), sessions: [],
                                                    stored: { self.snapshot(.lift, title: "Upper Day 1") },
                                                    calendar: cal)
        XCTAssertNil(snap)
    }

    // MARK: - Body weight

    func test_weight_kgUser_logsKg() throws {
        let store = makeStore(imperial: false)
        let line = BodyWeightIntentActions.log(weight: 82.5, in: store, now: Date())
        let newest = try XCTUnwrap(store.memory.latestBodyWeightEntry)
        XCTAssertEqual(newest.weightKg, 82.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(store.memory.weightKg), 82.5, accuracy: 0.0001)
        XCTAssertEqual(line, "Logged " + BodyMetrics.formatWeight(kg: 82.5, imperial: false))
    }

    func test_weight_imperialUser_convertsLbToKg() throws {
        let store = makeStore(imperial: true)
        let line = BodyWeightIntentActions.log(weight: 180, in: store, now: Date())
        let newest = try XCTUnwrap(store.memory.latestBodyWeightEntry)
        XCTAssertEqual(newest.weightKg, BodyMetrics.lbToKg(180), accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(store.memory.weightKg), BodyMetrics.lbToKg(180), accuracy: 0.01)
        XCTAssertEqual(line, "Logged " + BodyMetrics.formatWeight(kg: BodyMetrics.lbToKg(180), imperial: true))
    }

    func test_weight_sameDaySecondLog_replacesFirst() throws {
        let store = makeStore(imperial: false)
        let morning = cal.date(bySettingHour: 7, minute: 0, second: 0, of: today)!
        let evening = cal.date(bySettingHour: 19, minute: 0, second: 0, of: today)!
        _ = BodyWeightIntentActions.log(weight: 82.5, in: store, now: morning)
        _ = BodyWeightIntentActions.log(weight: 83.0, in: store, now: evening)
        XCTAssertEqual(store.memory.bodyWeightLog.count, 1)
        XCTAssertEqual(try XCTUnwrap(store.memory.weightKg), 83.0, accuracy: 0.0001)
    }

    func test_weight_writePersistsToDefaults() throws {
        let store = makeStore(imperial: false)
        _ = BodyWeightIntentActions.log(weight: 82.5, in: store, now: Date())
        store.reload()
        XCTAssertEqual(store.memory.bodyWeightLog.count, 1)
        XCTAssertEqual(try XCTUnwrap(store.memory.weightKg), 82.5, accuracy: 0.0001)
    }

    func test_weight_zeroNegativeAndNonFinite_writeNothing() {
        let store = makeStore(imperial: false)
        for bad in [0, -5, Double.nan, Double.infinity] {
            XCTAssertEqual(BodyWeightIntentActions.log(weight: bad, in: store, now: Date()),
                           BodyWeightIntentActions.invalidWeightLine, "\(bad)")
        }
        XCTAssertTrue(store.memory.bodyWeightLog.isEmpty)
        XCTAssertNil(store.memory.weightKg)
    }

    func test_weight_nilStore_returnsOpenLine() {
        XCTAssertEqual(BodyWeightIntentActions.log(weight: 82.5, in: nil, now: Date()),
                       BodyWeightIntentActions.noStoreLine)
    }

    func test_weight_notOnboarded_writesNothing() {
        let store = makeStore(onboarded: false, imperial: false)
        XCTAssertEqual(BodyWeightIntentActions.log(weight: 82.5, in: store, now: Date()),
                       BodyWeightIntentActions.notOnboardedLine)
        XCTAssertTrue(store.memory.bodyWeightLog.isEmpty)
        XCTAssertNil(store.memory.weightKg)
    }
}
