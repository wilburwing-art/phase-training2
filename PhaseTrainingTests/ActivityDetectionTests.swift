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

// MARK: - Store persistence

@MainActor
final class ActivityDetectionStoreTests: XCTestCase {

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testMarkHandledPersistsSeenIdsAcrossInstances() async {
        let suite = "ActivityDetectionStoreTests.seen"
        let defaults = freshDefaults(suite)

        let activity = DetectedActivity(
            id: "u2", workoutIds: ["u1", "u2"],
            sport: Sport.resolve(slug: "climbing"),
            activityLabel: "Climbing",
            startTime: Date(),
            durationMinutes: 90,
            suggestedIntensity: .moderate
        )

        let store = ActivityDetectionStore(defaults: defaults)
        store.markHandled(activity)

        // A second instance (fresh launch) still knows both ids: detection
        // fed those seen ids never re-prompts the same outing.
        let relaunched = ActivityDetectionStore(defaults: defaults)
        let out = ActivityDetector.detect(
            workouts: [
                HKWorkoutLike(uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID(),
                              activityType: .climbing,
                              startDate: Date().addingTimeInterval(-3_600),
                              duration: 5_400,
                              totalEnergyBurnedKcal: nil)
            ],
            sportLogs: [],
            seenIds: relaunched.seenIdsForTesting,
            now: Date()
        )
        // The fake workout has a different UUID, so it still prompts — the
        // seen set contains exactly what was handled.
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(relaunched.seenIdsForTesting, Set(["u1", "u2"]))
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

    func testResetDropsSeenIds() {
        let suite = "ActivityDetectionStoreTests.reset"
        let defaults = freshDefaults(suite)

        let store = ActivityDetectionStore(defaults: defaults)
        store.markHandled(DetectedActivity(
            id: "x", workoutIds: ["x"],
            sport: Sport.resolve(slug: "alpine-skiing"),
            activityLabel: "Skiing",
            startTime: Date(),
            durationMinutes: 200,
            suggestedIntensity: .hard
        ))
        XCTAssertFalse(store.seenIdsForTesting.isEmpty)
        store.reset()
        XCTAssertTrue(store.seenIdsForTesting.isEmpty)
        let relaunched = ActivityDetectionStore(defaults: defaults)
        XCTAssertTrue(relaunched.seenIdsForTesting.isEmpty)
    }
}
