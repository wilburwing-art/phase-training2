import XCTest
@testable import PhaseTraining

final class RecentPicksStoreTests: XCTestCase {

    private func freshStore(_ suite: String = #function) -> RecentPicksStore {
        let defaults = UserDefaults(suiteName: "RecentPicksStoreTests.\(suite)")!
        defaults.removePersistentDomain(forName: "RecentPicksStoreTests.\(suite)")
        return RecentPicksStore(defaults: defaults)
    }

    func test_record_andQueryRecent() {
        let store = freshStore()
        store.record(exerciseIds: [10, 20, 30])
        XCTAssertEqual(store.recentlyPickedIds(), [10, 20, 30])
    }

    func test_oldEntries_dropOutOfRecentWindow() {
        let store = freshStore()
        let oldDate = Date().addingTimeInterval(-Double(RecentPicksStore.cutoffDays + 1) * 86400)
        store.record(exerciseIds: [99], at: oldDate)
        XCTAssertTrue(store.recentlyPickedIds().isEmpty,
                      "Exercise picked > cutoffDays ago should not be in the recent set")
    }

    func test_record_isIdempotent_bumpsTimestamp() {
        let store = freshStore()
        let yesterday = Date().addingTimeInterval(-86400)
        store.record(exerciseIds: [42], at: yesterday)
        store.record(exerciseIds: [42])   // bump to now
        XCTAssertEqual(store.lastPicked[42].map { Date().timeIntervalSince($0) < 5 }, true)
    }

    func test_clear_emptiesEverything() {
        let store = freshStore()
        store.record(exerciseIds: [1, 2, 3])
        store.clear()
        XCTAssertTrue(store.lastPicked.isEmpty)
        XCTAssertTrue(store.recentlyPickedIds().isEmpty)
    }

    // MARK: - End-to-end with the generator

    func test_generatorSoftFiltersRecentlyPickedExercises() {
        // Seed memory + profile that yields a healthy candidate pool on push.
        var memory = TrainingMemory()
        memory.experience = .intermediate
        memory.equipment = [.fullGym]
        memory.sessionMinutes = 60
        let profile = DemographicProfile.from(memory)

        // First generation — nothing recent yet.
        let first = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: memory, profile: profile,
            hashSeed: memory.planInputsHash,
            recentlyPicked: []
        )
        let firstIds = Set(first.exercises.map(\.exerciseId))
        XCTAssertFalse(firstIds.isEmpty)

        // Second generation with first picks marked recent — pool should
        // largely shift to different exercises. If the pool was very small,
        // we tolerate some overlap (variety is best-effort).
        let second = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: memory, profile: profile,
            hashSeed: memory.planInputsHash,
            recentlyPicked: firstIds
        )
        let secondIds = Set(second.exercises.map(\.exerciseId))
        let overlap = firstIds.intersection(secondIds)
        XCTAssertLessThan(overlap.count, firstIds.count,
                          "Variety should drop at least some recently-picked exercises (overlap=\(overlap.count))")
    }
}
