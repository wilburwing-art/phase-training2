import XCTest
@testable import PhaseTraining

final class CoachConversationStoreTests: XCTestCase {

    private func freshDefaults(_ suite: String = #function) -> UserDefaults {
        let name = "CoachConversationStoreTests.\(suite)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_recordTurn_incrementsCount() {
        let store = CoachConversationStore(defaults: freshDefaults())
        XCTAssertEqual(store.turnsToday, 0)
        store.recordTurn()
        store.recordTurn()
        XCTAssertEqual(store.turnsToday, 2)
    }

    func test_softAndHardCapThresholds() {
        let store = CoachConversationStore(defaults: freshDefaults())
        for _ in 0..<CoachConfig.softTurnCap { store.recordTurn() }
        XCTAssertTrue(store.atSoftCap, "Should hit the soft cap at \(CoachConfig.softTurnCap) turns")
        XCTAssertFalse(store.atHardCap)
        for _ in CoachConfig.softTurnCap..<CoachConfig.hardTurnCap { store.recordTurn() }
        XCTAssertTrue(store.atHardCap, "Should hit the hard cap at \(CoachConfig.hardTurnCap) turns")
    }

    func test_clearToday_doesNotResetTurnCount() {
        let store = CoachConversationStore(defaults: freshDefaults())
        store.append(CoachMessage(role: "user", text: "hi"))
        store.recordTurn()
        store.clearToday()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.turnsToday, 1, "Clearing the transcript must not reset the daily cost guard")
    }

    func test_turnCount_persistsAcrossReload_sameDay() {
        let defaults = freshDefaults()
        let day = Date()
        let s1 = CoachConversationStore(defaults: defaults, now: day)
        s1.recordTurn(); s1.recordTurn(); s1.recordTurn()
        let s2 = CoachConversationStore(defaults: defaults, now: day)
        XCTAssertEqual(s2.turnsToday, 3, "Turn count should survive a same-day reload")
    }

    func test_recordTurn_rollsOverAcrossMidnight_inLongLivedStore() {
        // A store held open past midnight (no re-init, no .onAppear) must still
        // reset the counter on the new day's first recorded turn.
        let defaults = freshDefaults()
        let day1 = Date()
        let store = CoachConversationStore(defaults: defaults, now: day1)
        store.recordTurn(now: day1)
        store.recordTurn(now: day1)
        XCTAssertEqual(store.turnsToday, 2)
        let day2 = day1.addingTimeInterval(2 * 86400)
        store.recordTurn(now: day2)
        XCTAssertEqual(store.turnsToday, 1, "First turn of a new day should count against a reset counter")
    }

    func test_dayRollover_resetsTurnCount() {
        let defaults = freshDefaults()
        let day1 = Date()
        let s1 = CoachConversationStore(defaults: defaults, now: day1)
        s1.recordTurn(); s1.recordTurn()
        XCTAssertEqual(s1.turnsToday, 2)
        let day2 = day1.addingTimeInterval(2 * 86400)
        let s2 = CoachConversationStore(defaults: defaults, now: day2)
        XCTAssertEqual(s2.turnsToday, 0, "A new calendar day resets the daily turn counter")
    }

    // MARK: - Gate test 3: the wireHistory() contract

    private func msg(_ role: String, _ text: String) -> CoachMessage {
        CoachMessage(role: role, text: text)
    }

    func test_wireHistory_dropsEmptyTurns() {
        let store = CoachConversationStore(defaults: freshDefaults())
        store.messages = [msg("user", "hi"), msg("assistant", "   \n"), msg("user", "still there?")]
        let wire = store.wireHistory()
        XCTAssertFalse(wire.contains { $0.text.isEmpty })
        // The two user turns left adjacent by the drop are MERGED, not sent
        // back-to-back — the API 400s on consecutive same-role messages.
        XCTAssertEqual(wire.map(\.role), ["user"])
        XCTAssertEqual(wire.first?.text, "hi\n\nstill there?")
    }

    func test_wireHistory_rolesStrictlyAlternate() {
        let store = CoachConversationStore(defaults: freshDefaults())
        store.messages = [
            msg("user", "a"), msg("user", "b"),
            msg("assistant", "c"), msg("assistant", "d"),
            msg("user", "e"),
        ]
        let roles = store.wireHistory().map(\.role)
        XCTAssertEqual(roles, ["user", "assistant", "user"])
        for (l, r) in zip(roles, roles.dropFirst()) {
            XCTAssertNotEqual(l, r, "consecutive same-role turns must be merged")
        }
    }

    func test_wireHistory_preservesOrderAndContent() {
        let store = CoachConversationStore(defaults: freshDefaults())
        store.messages = [msg("user", "one"), msg("assistant", "two"), msg("user", "three")]
        XCTAssertEqual(store.wireHistory().map(\.text), ["one", "two", "three"])
    }

    func test_wireHistory_startsWithUser() {
        let store = CoachConversationStore(defaults: freshDefaults())
        store.messages = [msg("assistant", "welcome"), msg("user", "hello")]
        XCTAssertEqual(store.wireHistory().first?.role, "user")
    }

    func test_wireHistory_emptyConversationIsEmpty() {
        let store = CoachConversationStore(defaults: freshDefaults())
        store.messages = []
        XCTAssertTrue(store.wireHistory().isEmpty)
    }
}
