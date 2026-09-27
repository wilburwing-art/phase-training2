// HealthWorkoutWriterTests.swift — one session, one workout in Apple Health
// (PLAN-watch.md, step 2): what the phone writes, when it stays silent, and
// that the importer never reads the app's own workouts back.

import XCTest
import HealthKit
@testable import PhaseTraining

final class HealthWorkoutWriterTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_790_000_000.25)

    private func saved(done: Bool = true, writer: HealthWriter? = nil, minutes: Int = 50) -> SavedSession {
        let set = LoggedSet(num: 1, weight: "135", reps: "5", rpe: "", done: done)
        let ex = LoggedExercise(id: "squat", name: "Barbell Back Squat", type: nil, unit: "lb", targetSets: 1,
                                targetReps: 5, rest: 120, sets: [set], prevSets: [], rpe: nil, tempo: nil)
        return SavedSession(templateId: "t", name: "Lower A", category: "Generated", startTime: start,
                            exercises: [ex], feel: nil, note: nil,
                            endTime: start.addingTimeInterval(Double(minutes) * 60), duration: minutes * 60,
                            healthWriter: writer)
    }

    func test_payload_carriesTheSyncIdentityAndTheTag() throws {
        let p = try XCTUnwrap(HealthWorkoutWriter.payload(for: saved()))
        XCTAssertEqual(p.sessionId, "pt-session-1790000000250")
        XCTAssertEqual(p.start, start)
        XCTAssertEqual(p.end, start.addingTimeInterval(3000))
        XCTAssertEqual(p.activityType, .traditionalStrengthTraining)
        XCTAssertEqual(p.metadata[HKMetadataKeySyncIdentifier] as? String, p.sessionId)
        XCTAssertEqual(p.metadata[HKMetadataKeySyncVersion] as? Int, HealthWorkoutTag.syncVersion)
        XCTAssertEqual(p.metadata[HealthWorkoutTag.sessionKey] as? String, p.sessionId)
    }

    func test_sessionIdIsStableForTheSameStart() {
        XCTAssertEqual(HealthWorkoutTag.sessionId(for: start), HealthWorkoutTag.sessionId(for: start))
        XCTAssertNotEqual(HealthWorkoutTag.sessionId(for: start),
                          HealthWorkoutTag.sessionId(for: start.addingTimeInterval(1)))
    }

    func test_watchOwnedSession_isNotWrittenByThePhone() {
        XCTAssertNil(HealthWorkoutWriter.payload(for: saved(writer: .watch)))
        XCTAssertNotNil(HealthWorkoutWriter.payload(for: saved(writer: .phone)))
        XCTAssertNotNil(HealthWorkoutWriter.payload(for: saved(writer: nil)), "sessions from before 146")
    }

    func test_sessionWithNoCompletedSet_isNotAWorkout() {
        XCTAssertNil(HealthWorkoutWriter.payload(for: saved(done: false)))
    }

    func test_endNeverPrecedesStartByLessThanAMinute() throws {
        let p = try XCTUnwrap(HealthWorkoutWriter.payload(for: saved(minutes: 0)))
        XCTAssertEqual(p.end, start.addingTimeInterval(60))
    }

    func test_record_asksOnceThenSaves_andStaysSilentWhenDenied() async {
        final class Store: HealthWorkoutStore, @unchecked Sendable {
            var granted = true
            var asks = 0
            var saved: [HealthWorkoutPayload] = []
            func requestWorkoutShareAuthorization() async throws -> Bool { asks += 1; return granted }
            func save(_ payload: HealthWorkoutPayload) async throws { saved.append(payload) }
        }
        let store = Store()
        await HealthWorkoutWriter.record(saved(), store: store)
        XCTAssertEqual(store.asks, 1)
        XCTAssertEqual(store.saved.count, 1)

        let denied = Store()
        denied.granted = false
        await HealthWorkoutWriter.record(saved(), store: denied)
        XCTAssertTrue(denied.saved.isEmpty)

        let watch = Store()
        await HealthWorkoutWriter.record(saved(writer: .watch), store: watch)
        XCTAssertEqual(watch.asks, 0, "nothing to write, so no prompt")
    }

    // MARK: - The importer never reads these back

    func test_importerDropsOwnWorkouts_byTagAndByBundle() async throws {
        final class Fake: HKHealthStoreInterface, @unchecked Sendable {
            var workouts: [HKWorkoutLike] = []
            func requestWorkoutReadAuthorization() async throws -> Bool { true }
            func recentWorkouts(days: Int) async throws -> [HKWorkoutLike] { workouts }
        }
        func hk(_ bundle: String?, tag: String?) -> HKWorkoutLike {
            HKWorkoutLike(uuid: UUID(), activityType: .traditionalStrengthTraining, startDate: start,
                          duration: 3000, totalEnergyBurnedKcal: nil, sourceBundleId: bundle, sessionTag: tag)
        }
        let fake = Fake()
        let foreign = hk("com.apple.Fitness", tag: nil)
        fake.workouts = [hk("com.phasetraining.app.watchkitapp", tag: "pt-session-1"),
                         hk("com.phasetraining.app", tag: nil),
                         hk("com.apple.Fitness", tag: "pt-session-2"),
                         foreign]
        let importer = HealthKitImporter(store: fake)
        let mapped = try await importer.recentWorkouts().map(\.id)
        let raw = try await importer.recentRawWorkouts().map(\.uuid)
        XCTAssertEqual(mapped, [foreign.uuid.uuidString])
        XCTAssertEqual(raw, [foreign.uuid])
    }
}
