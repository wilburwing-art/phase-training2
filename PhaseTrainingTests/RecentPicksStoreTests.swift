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
}
