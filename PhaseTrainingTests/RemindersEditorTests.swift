// RemindersEditorTests.swift — notification pre-prompt decision.

import XCTest
import UserNotifications
@testable import PhaseTraining

final class RemindersEditorTests: XCTestCase {
    private let suite = "RemindersEditorTests.prePrompt"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_zeroSessions_hidesOffer() {
        XCTAssertFalse(NotificationPrePrompt.shouldOffer(completedSessions: 0, status: .notDetermined, defaults: defaults))
    }

    func test_oneSession_undetermined_showsOffer() {
        XCTAssertTrue(NotificationPrePrompt.shouldOffer(completedSessions: 1, status: .notDetermined, defaults: defaults))
    }

    func test_denied_hidesOffer() {
        XCTAssertFalse(NotificationPrePrompt.shouldOffer(completedSessions: 3, status: .denied, defaults: defaults))
    }

    func test_authorized_hidesOffer() {
        XCTAssertFalse(NotificationPrePrompt.shouldOffer(completedSessions: 3, status: .authorized, defaults: defaults))
    }

    func test_answered_hidesOffer_andPersists() {
        NotificationPrePrompt.markAnswered(defaults: defaults)
        XCTAssertFalse(NotificationPrePrompt.shouldOffer(completedSessions: 3, status: .notDetermined, defaults: defaults))
        let reread = UserDefaults(suiteName: suite)!
        XCTAssertTrue(reread.bool(forKey: NotificationPrePrompt.answeredKey))
    }
}
