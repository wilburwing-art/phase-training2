import XCTest
@testable import PhaseTraining

/// T0-2 (2026-08-23): "Erase all data" wiped the pt_ keys, but three
/// app-lifetime @StateObjects kept their in-memory arrays and wrote themselves
/// back on the next mutation, resurrecting the wiped data. The fix gave each
/// store a reset and called them from BackupCoordinator.eraseAllData. Nothing
/// pinned the resets. These do, per store, over a fresh defaults suite, so no
/// test ever touches .standard.
@MainActor
final class StoreResetTests: XCTestCase {

    private func fresh(_ fn: String = #function) -> UserDefaults {
        let name = "StoreResetTests.\(fn).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_recentPicks_clearEmptiesMemoryAndDisk() {
        let d = fresh()
        let store = RecentPicksStore(defaults: d)
        store.record(exerciseIds: [1, 2, 3])
        XCTAssertFalse(store.recentlyPickedIds().isEmpty)
        store.clear()
        XCTAssertTrue(store.recentlyPickedIds().isEmpty)
        // A fresh store over the same defaults must not resurrect them.
        XCTAssertTrue(RecentPicksStore(defaults: d).recentlyPickedIds().isEmpty,
                      "clear() must remove the persisted copy, not only the in-memory one")
    }

    func test_conversation_resetAllEmptiesTranscriptTurnsAndArchives() {
        let d = fresh()
        let store = CoachConversationStore(defaults: d)
        store.messages = [CoachMessage(role: "user", text: "hi")]
        store.recordTurn(); store.recordTurn()
        d.set("x", forKey: "pt_coach_archive_2026-01-01")
        store.resetAll()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.turnsToday, 0)
        XCTAssertNil(d.object(forKey: "pt_coach_archive_2026-01-01"), "archives are part of the wipe")
        let reloaded = CoachConversationStore(defaults: d)
        XCTAssertTrue(reloaded.messages.isEmpty)
        XCTAssertEqual(reloaded.turnsToday, 0)
    }

    func test_activityDetection_resetClearsStateAndRestoresTheDefaultToggle() {
        let d = fresh()
        d.set(["u1": 1.0], forKey: "pt_detected_activity_seen")
        d.set(["k1": 1.0], forKey: "pt_detected_activity_dismissed")
        let store = ActivityDetectionStore(defaults: d)
        store.enabled = false
        store.reset()
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertNil(d.object(forKey: "pt_detected_activity_seen"))
        XCTAssertNil(d.object(forKey: "pt_detected_activity_dismissed"))
        XCTAssertTrue(store.enabled,
                      "reset must restore the fresh-install default, or detection stays silently off until the next cold launch")
    }

    func test_sportLog_resetEmptiesMemoryAndDisk() {
        let d = fresh()
        let store = SportLogStore(defaults: d)
        let sport = Sport(slug: "climbing", name: "Climbing")
        store.log(sport: sport, on: Date(), durationMinutes: 90,
                  intensity: EventIntensity.allCases.first!, note: "gym session")
        XCTAssertEqual(store.entries.count, 1)
        store.reset()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(SportLogStore(defaults: d).entries.isEmpty,
                      "reset() must remove the persisted copy so the next mutation cannot write the old array back")
    }
}
