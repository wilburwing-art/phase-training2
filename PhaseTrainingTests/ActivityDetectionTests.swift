// ActivityDetectionTests — the pure detection pass behind the on-open
// "looks like you went skiing" banner (ActivityDetection.swift), plus the
// store's seen-id persistence.
//
// Detection is pure (HKWorkoutLike[] in, DetectedActivity[] out), so these
// never touch real HealthKit. Store tests use an isolated UserDefaults
// suite, mirroring the repo convention.

import XCTest
import HealthKit
@testable import PhaseTraining

final class ActivityDetectionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func workout(_ type: HKWorkoutActivityType,
                         daysAgo: Double,
                         minutes: Double,
                         uuid: UUID = UUID()) -> HKWorkoutLike {
        HKWorkoutLike(uuid: uuid,
                      activityType: type,
                      startDate: now.addingTimeInterval(-daysAgo * 86_400),
                      duration: minutes * 60,
                      totalEnergyBurnedKcal: nil)
    }

    // MARK: - Mapping + thresholds

    func testSkiDayIsDetectedAndMapped() {
        let out = ActivityDetector.detect(
            workouts: [workout(.downhillSkiing, daysAgo: 1, minutes: 160)],
            sportLogs: [], seenIds: [], now: now
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].sport.slug, "alpine-skiing")
        XCTAssertEqual(out[0].activityLabel, "Skiing")
        XCTAssertEqual(out[0].durationMinutes, 160)
        XCTAssertEqual(out[0].suggestedIntensity, .moderate)
    }

    func testStrengthAndGymTypesNeverPrompt() {
        let out = ActivityDetector.detect(
            workouts: [
                workout(.traditionalStrengthTraining, daysAgo: 1, minutes: 90),
                workout(.functionalStrengthTraining, daysAgo: 2, minutes: 90),
                workout(.highIntensityIntervalTraining, daysAgo: 3, minutes: 90),
                workout(.yoga, daysAgo: 1, minutes: 90)
            ],
            sportLogs: [], seenIds: [], now: now
        )
        XCTAssertTrue(out.isEmpty)
    }

    func testShortSessionsFallUnderPerActivityFloor() {
        let out = ActivityDetector.detect(
            workouts: [
                workout(.downhillSkiing, daysAgo: 1, minutes: 20),  // lift-lap noise
                workout(.running, daysAgo: 2, minutes: 45)          // jog, floor is 60
            ],
            sportLogs: [], seenIds: [], now: now
        )
        XCTAssertTrue(out.isEmpty)
    }

    func testLongRunClearsTheEnduranceFloor() {
        let out = ActivityDetector.detect(
            workouts: [workout(.running, daysAgo: 2, minutes: 95)],
            sportLogs: [], seenIds: [], now: now
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].sport.slug, "running")
    }

    // MARK: - Exclusions

    func testOutsideWindowIsIgnored() {
        let out = ActivityDetector.detect(
            workouts: [workout(.climbing, daysAgo: 9, minutes: 120)],
            sportLogs: [], seenIds: [], now: now
        )
        XCTAssertTrue(out.isEmpty)
    }

    func testSeenIdsAreExcluded() {
        let uuid = UUID()
        let out = ActivityDetector.detect(
            workouts: [workout(.climbing, daysAgo: 1, minutes: 120, uuid: uuid)],
            sportLogs: [], seenIds: [uuid.uuidString], now: now
        )
        XCTAssertTrue(out.isEmpty)
    }

    func testDayWithExistingSportLogIsExcluded() {
        let ski = workout(.downhillSkiing, daysAgo: 1, minutes: 200)
        let log = SportLogEntry(
            date: Calendar.current.startOfDay(for: ski.startDate),
            sport: Sport.resolve(slug: "alpine-skiing"),
            durationMinutes: 180,
            intensity: .hard,
            note: nil,
            loggedAt: now
        )
        let out = ActivityDetector.detect(
            workouts: [ski], sportLogs: [log], seenIds: [], now: now
        )
        XCTAssertTrue(out.isEmpty)
    }

    func testDismissedOutingTombstoneBlocksLateFragment() {
        // The user said "Not me" to Saturday's ski outing; a fresh-UUID
        // fragment of the same morning syncs in later and clears the
        // duration floor on its own. The (day, sport) tombstone keeps it
        // from re-prompting; a DIFFERENT sport that day still can.
        let lateSki = workout(.downhillSkiing, daysAgo: 1, minutes: 45)
        let hike = workout(.hiking, daysAgo: 1, minutes: 90)
        let tombstone = DetectedActivity.outingKey(
            day: Calendar.current.startOfDay(for: lateSki.startDate),
            sportSlug: "alpine-skiing"
        )
        let out = ActivityDetector.detect(
            workouts: [lateSki, hike], sportLogs: [], seenIds: [],
            dismissedOutingKeys: [tombstone], now: now
        )
        XCTAssertEqual(out.map(\.activityLabel), ["Hiking"])
    }

    // MARK: - Grouping

    func testSameDayFragmentsCollapseIntoOneOuting() {
        // Four short ski recordings on one day: each is under the 30-min
        // floor, the summed outing clears it and prompts once.
        let day: Double = 1
        let a = UUID(); let b = UUID(); let c = UUID(); let d = UUID()
        let out = ActivityDetector.detect(
            workouts: [
                workout(.downhillSkiing, daysAgo: day, minutes: 20, uuid: a),
                workout(.downhillSkiing, daysAgo: day - 0.01, minutes: 25, uuid: b),
                workout(.downhillSkiing, daysAgo: day - 0.02, minutes: 22, uuid: c),
                workout(.downhillSkiing, daysAgo: day - 0.03, minutes: 28, uuid: d)
            ],
            sportLogs: [], seenIds: [], now: now
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].durationMinutes, 95)
        XCTAssertEqual(Set(out[0].workoutIds), Set([a, b, c, d].map(\.uuidString)))
    }

    func testDistinctDaysStayDistinctNewestFirst() {
        let out = ActivityDetector.detect(
            workouts: [
                workout(.downhillSkiing, daysAgo: 3, minutes: 180),
                workout(.climbing, daysAgo: 1, minutes: 90)
            ],
            sportLogs: [], seenIds: [], now: now
        )
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].activityLabel, "Climbing")
        XCTAssertEqual(out[1].activityLabel, "Skiing")
    }

    // MARK: - Intensity heuristic

    func testIntensityBands() {
        XCTAssertEqual(ActivityDetector.suggestedIntensity(durationMinutes: 45), .light)
        XCTAssertEqual(ActivityDetector.suggestedIntensity(durationMinutes: 90), .moderate)
        XCTAssertEqual(ActivityDetector.suggestedIntensity(durationMinutes: 240), .hard)
    }
}

// MARK: - Confirm mode (keep the lift vs swap for the sport)

final class ActivityDetectionConfirmModeTests: XCTestCase {

    // Week-anchored fixture dates so results don't depend on the machine's
    // timezone: "today" is Thursday noon of the training week containing a
    // fixed epoch instant.
    private let weekStart = Date(timeIntervalSince1970: 1_760_000_000).startOfTrainingWeek()
    private var now: Date { weekStart.addingTimeInterval(3 * 86_400 + 12 * 3_600) }

    private func date(dayOffset: Int, hour: Double = 9) -> Date {
        weekStart.addingTimeInterval(Double(dayOffset) * 86_400 + hour * 3_600)
    }

    private func activity(startTime: Date) -> DetectedActivity {
        DetectedActivity(
            id: "hk-1", workoutIds: ["hk-1"],
            sport: Sport.resolve(slug: "alpine-skiing"),
            activityLabel: "Skiing",
            startTime: startTime,
            day: Calendar.current.startOfDay(for: startTime),
            durationMinutes: 200,
            suggestedIntensity: .hard
        )
    }

    private func plan(_ days: [DayPlan]) -> WeekPlan {
        WeekPlan(days: days, generatedAt: now, inputsHash: "test")
    }

    private func day(_ offset: Int, _ kind: DayKind, title: String = "Day") -> DayPlan {
        DayPlan(date: Calendar.current.startOfDay(for: date(dayOffset: offset)),
                kind: kind, title: title)
    }

    func testOutsideCurrentWeekLogsOnly() {
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: -3)),   // previous week
            plan: plan([day(3, .lift)]),
            completedSessionDays: [], now: now
        )
        XCTAssertEqual(mode, .logOnly)
    }

    func testPlannedSportDayLogsOnly() {
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: 1)),
            plan: plan([day(1, .sport)]),
            completedSessionDays: [], now: now
        )
        XCTAssertEqual(mode, .logOnly)
    }

    func testPlannedEventDayLogsOnly() {
        // The detected activity IS the booked race — converting would
        // fight the user's own WeekEvent (and the resolve guard would
        // silently drop ours).
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: 1)),
            plan: plan([day(1, .event, title: "Race")]),
            completedSessionDays: [], now: now
        )
        XCTAssertEqual(mode, .logOnly)
    }

    func testPastLiftDayNotTrainedAdjustsWeek() {
        // Skied Tuesday instead of the planned lift — honest record is a
        // sport day; also resolves the would-be missed-workout state.
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: 1)),
            plan: plan([day(1, .lift)]),
            completedSessionDays: [], now: now
        )
        XCTAssertEqual(mode, .adjustWeek)
    }

    func testPastLiftDayAlsoTrainedLogsOnly() {
        // Did BOTH that day: keep the lift day + its session record.
        let trained = Calendar.current.startOfDay(for: date(dayOffset: 1))
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: 1)),
            plan: plan([day(1, .lift)]),
            completedSessionDays: [trained], now: now
        )
        XCTAssertEqual(mode, .logOnly)
    }

    func testTodayWithPendingLiftAsksTheUser() {
        // Skied this morning, lift still planned and not yet logged —
        // whether to still lift on a ski day is the user's decision.
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: 3, hour: 7)),
            plan: plan([day(3, .lift)]),
            completedSessionDays: [], now: now
        )
        XCTAssertEqual(mode, .userChoice)
    }

    func testTodayLiftAlreadyTrainedLogsOnly() {
        let trained = Calendar.current.startOfDay(for: date(dayOffset: 3))
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: 3, hour: 7)),
            plan: plan([day(3, .lift)]),
            completedSessionDays: [trained], now: now
        )
        XCTAssertEqual(mode, .logOnly)
    }

    func testPastRestDayAdjustsWeek() {
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: 2)),
            plan: plan([day(2, .rest, title: "Rest")]),
            completedSessionDays: [], now: now
        )
        XCTAssertEqual(mode, .adjustWeek)
    }

    func testNoPlanAdjustsWeek() {
        // In-week with no plan yet: record the event; the planner honors
        // it whenever the week generates.
        let mode = ActivityDetector.confirmMode(
            for: activity(startTime: date(dayOffset: 2)),
            plan: nil,
            completedSessionDays: [], now: now
        )
        XCTAssertEqual(mode, .adjustWeek)
    }
}

// MARK: - Store persistence

@MainActor
final class ActivityDetectionStoreTests: XCTestCase {

    /// Minimal HK fake so store tests can drive scan() without the real
    /// HealthKit store (mirrors HealthKitImporterTests.FakeStore).
    final class FakeStore: HKHealthStoreInterface, @unchecked Sendable {
        var workoutsResult: Result<[HKWorkoutLike], Error> = .success([])
        func requestWorkoutReadAuthorization() async throws -> Bool { true }
        func recentWorkouts(days: Int) async throws -> [HKWorkoutLike] {
            try workoutsResult.get()
        }
    }

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func makeActivity(id: String = "u2",
                              workoutIds: [String] = ["u1", "u2"],
                              slug: String = "climbing",
                              label: String = "Climbing",
                              startTime: Date = Date()) -> DetectedActivity {
        DetectedActivity(
            id: id, workoutIds: workoutIds,
            sport: Sport.resolve(slug: slug),
            activityLabel: label,
            startTime: startTime,
            day: Calendar.current.startOfDay(for: startTime),
            durationMinutes: 90,
            suggestedIntensity: .moderate
        )
    }

    func testConfirmPersistsSeenIdsAcrossInstances() {
        let suite = "ActivityDetectionStoreTests.seen"
        let defaults = freshDefaults(suite)

        let store = ActivityDetectionStore(defaults: defaults)
        store.markConfirmed(makeActivity())

        // A second instance (fresh launch) still knows both ids: detection
        // fed those seen ids never re-prompts the same outing.
        let relaunched = ActivityDetectionStore(defaults: defaults)
        XCTAssertEqual(relaunched.seenIdsForTesting, Set(["u1", "u2"]))
        XCTAssertTrue(relaunched.dismissedOutingKeysForTesting.isEmpty)
    }

    func testDismissTombstonesOutingAcrossInstances() {
        let suite = "ActivityDetectionStoreTests.dismissed"
        let defaults = freshDefaults(suite)

        let activity = makeActivity(slug: "alpine-skiing", label: "Skiing")
        let store = ActivityDetectionStore(defaults: defaults)
        store.markDismissed(activity)

        let relaunched = ActivityDetectionStore(defaults: defaults)
        XCTAssertEqual(relaunched.seenIdsForTesting, Set(["u1", "u2"]))
        XCTAssertEqual(relaunched.dismissedOutingKeysForTesting, Set([activity.outingKey]))
    }

    func testConfirmDropsOtherSameDayCandidates() async {
        // Ski + hike detected on the same Saturday. Confirming the ski
        // writes that day's sport log, so the hike candidate must not
        // survive to double-log the day.
        let suite = "ActivityDetectionStoreTests.sameDay"
        let defaults = freshDefaults(suite)
        let day = Date().addingTimeInterval(-86_400)

        let fake = FakeStore()
        fake.workoutsResult = .success([
            HKWorkoutLike(uuid: UUID(), activityType: .downhillSkiing,
                          startDate: day, duration: 200 * 60, totalEnergyBurnedKcal: nil),
            HKWorkoutLike(uuid: UUID(), activityType: .hiking,
                          startDate: day.addingTimeInterval(3_600), duration: 90 * 60,
                          totalEnergyBurnedKcal: nil)
        ])
        let store = ActivityDetectionStore(
            importer: HealthKitImporter(store: fake), defaults: defaults
        )
        await store.scan(sportLogs: [])
        XCTAssertEqual(store.pending.count, 2)

        store.markConfirmed(store.pending[0])
        XCTAssertTrue(store.pending.isEmpty)
    }

    func testDismissKeepsOtherSameDayCandidate() async {
        // "Not me" on the ski leaves the same-day hike up for review —
        // the other candidate might be the one that's real.
        let suite = "ActivityDetectionStoreTests.dismissKeeps"
        let defaults = freshDefaults(suite)
        let day = Date().addingTimeInterval(-86_400)

        let fake = FakeStore()
        fake.workoutsResult = .success([
            HKWorkoutLike(uuid: UUID(), activityType: .downhillSkiing,
                          startDate: day, duration: 200 * 60, totalEnergyBurnedKcal: nil),
            HKWorkoutLike(uuid: UUID(), activityType: .hiking,
                          startDate: day.addingTimeInterval(3_600), duration: 90 * 60,
                          totalEnergyBurnedKcal: nil)
        ])
        let store = ActivityDetectionStore(
            importer: HealthKitImporter(store: fake), defaults: defaults
        )
        await store.scan(sportLogs: [])
        XCTAssertEqual(store.pending.count, 2)

        let dismissed = store.pending[0]
        store.markDismissed(dismissed)
        XCTAssertEqual(store.pending.count, 1)
        XCTAssertNotEqual(store.pending[0].id, dismissed.id)
    }

    func testDisablingClearsPendingAndPersists() {
        let suite = "ActivityDetectionStoreTests.enabled"
        let defaults = freshDefaults(suite)

        let store = ActivityDetectionStore(defaults: defaults)
        XCTAssertTrue(store.enabled)   // default ON
        store.enabled = false

        let relaunched = ActivityDetectionStore(defaults: defaults)
        XCTAssertFalse(relaunched.enabled)
    }

    func testResetDropsStateAndRestoresEnabledDefault() {
        let suite = "ActivityDetectionStoreTests.reset"
        let defaults = freshDefaults(suite)

        let store = ActivityDetectionStore(defaults: defaults)
        store.markConfirmed(makeActivity(id: "x", workoutIds: ["x"],
                                         slug: "alpine-skiing", label: "Skiing"))
        store.markDismissed(makeActivity(id: "y", workoutIds: ["y"],
                                         slug: "hiking-trekking", label: "Hiking"))
        store.enabled = false
        XCTAssertFalse(store.seenIdsForTesting.isEmpty)

        store.reset()
        XCTAssertTrue(store.seenIdsForTesting.isEmpty)
        XCTAssertTrue(store.dismissedOutingKeysForTesting.isEmpty)
        // Fresh-install default: detection on. A live `false` would leave
        // the feature silently off until the next cold launch.
        XCTAssertTrue(store.enabled)

        let relaunched = ActivityDetectionStore(defaults: defaults)
        XCTAssertTrue(relaunched.seenIdsForTesting.isEmpty)
        XCTAssertTrue(relaunched.dismissedOutingKeysForTesting.isEmpty)
        XCTAssertTrue(relaunched.enabled)
    }
}
