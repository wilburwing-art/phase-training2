// HealthKitImporterTests — exercise the auth flow and the
// HKWorkoutActivityType → WorkoutKind mapping without touching real HK.
//
// We feed the importer a fake HKHealthStoreInterface so the test never
// triggers a system auth dialog or queries the real HK store.

import XCTest
import HealthKit
@testable import PhaseTraining

final class HealthKitImporterTests: XCTestCase {

    // MARK: - Fakes

    final class FakeStore: HKHealthStoreInterface, @unchecked Sendable {
        var authResult: Result<Bool, Error> = .success(true)
        var workoutsResult: Result<[HKWorkoutLike], Error> = .success([])

        var authRequestCount = 0
        var lastFetchDays: Int? = nil

        func requestWorkoutReadAuthorization() async throws -> Bool {
            authRequestCount += 1
            return try authResult.get()
        }

        func recentWorkouts(days: Int) async throws -> [HKWorkoutLike] {
            lastFetchDays = days
            return try workoutsResult.get()
        }
    }

    // MARK: - Auth flow

    func testRequestAuthorizationForwardsThrough() async throws {
        let fake = FakeStore()
        let importer = HealthKitImporter(store: fake)
        let ok = try await importer.requestAuthorization()
        XCTAssertTrue(ok)
        XCTAssertEqual(fake.authRequestCount, 1)
    }

    func testRequestAuthorizationPropagatesError() async {
        let fake = FakeStore()
        struct AuthError: Error {}
        fake.authResult = .failure(AuthError())
        let importer = HealthKitImporter(store: fake)
        do {
            _ = try await importer.requestAuthorization()
            XCTFail("expected throw")
        } catch is AuthError {
            // pass
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Fetch + mapping

    func testRecentWorkoutsMapsStrength() async throws {
        let fake = FakeStore()
        let uuid = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        fake.workoutsResult = .success([
            HKWorkoutLike(uuid: uuid,
                          activityType: .traditionalStrengthTraining,
                          startDate: start,
                          duration: 60 * 45,
                          totalEnergyBurnedKcal: 350)
        ])
        let importer = HealthKitImporter(store: fake)
        let out = try await importer.recentWorkouts(days: 28)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].id, uuid.uuidString)
        XCTAssertEqual(out[0].source, .healthKit)
        XCTAssertEqual(out[0].kind, .strength)
        XCTAssertEqual(out[0].startTime, start)
        XCTAssertEqual(out[0].duration, 60 * 45)
        XCTAssertEqual(out[0].energyKcal, 350)
        XCTAssertEqual(fake.lastFetchDays, 28)
    }

    func testRecentWorkoutsRoutesCardioAndSportCorrectly() async throws {
        let fake = FakeStore()
        let now = Date()
        fake.workoutsResult = .success([
            HKWorkoutLike(uuid: UUID(), activityType: .running,
                          startDate: now, duration: 1800, totalEnergyBurnedKcal: nil),
            HKWorkoutLike(uuid: UUID(), activityType: .climbing,
                          startDate: now, duration: 3600, totalEnergyBurnedKcal: nil),
            HKWorkoutLike(uuid: UUID(), activityType: .functionalStrengthTraining,
                          startDate: now, duration: 2700, totalEnergyBurnedKcal: nil),
        ])
        let importer = HealthKitImporter(store: fake)
        let out = try await importer.recentWorkouts(days: 14)
        XCTAssertEqual(out.map(\.kind), [.cardio, .sport, .strength])
        XCTAssertEqual(fake.lastFetchDays, 14)
    }

    // MARK: - Pure mapKind table

    func testMapKindStrengthBuckets() {
        XCTAssertEqual(HealthKitImporter.mapKind(.traditionalStrengthTraining), .strength)
        XCTAssertEqual(HealthKitImporter.mapKind(.functionalStrengthTraining), .strength)
        XCTAssertEqual(HealthKitImporter.mapKind(.crossTraining), .strength)
        XCTAssertEqual(HealthKitImporter.mapKind(.highIntensityIntervalTraining), .strength)
    }

    func testMapKindCardioBuckets() {
        XCTAssertEqual(HealthKitImporter.mapKind(.running), .cardio)
        XCTAssertEqual(HealthKitImporter.mapKind(.cycling), .cardio)
        XCTAssertEqual(HealthKitImporter.mapKind(.walking), .cardio)
        XCTAssertEqual(HealthKitImporter.mapKind(.swimming), .cardio)
        XCTAssertEqual(HealthKitImporter.mapKind(.rowing), .cardio)
        XCTAssertEqual(HealthKitImporter.mapKind(.elliptical), .cardio)
        XCTAssertEqual(HealthKitImporter.mapKind(.hiking), .cardio)
    }

    func testMapKindSportFallback() {
        // Sports + everything else routes to .sport.
        XCTAssertEqual(HealthKitImporter.mapKind(.tennis), .sport)
        XCTAssertEqual(HealthKitImporter.mapKind(.soccer), .sport)
        XCTAssertEqual(HealthKitImporter.mapKind(.climbing), .sport)
        XCTAssertEqual(HealthKitImporter.mapKind(.yoga), .sport)
        XCTAssertEqual(HealthKitImporter.mapKind(.surfingSports), .sport)
        // Unknown / new HK activities fall through to .sport.
        XCTAssertEqual(HealthKitImporter.mapKind(.other), .sport)
    }
}
