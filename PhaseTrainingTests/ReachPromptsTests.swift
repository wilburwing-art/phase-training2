import XCTest
@testable import PhaseTraining

final class ReachPromptsTests: XCTestCase {

    private func defaults(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "ReachPromptsTests.\(name)")!
        d.removePersistentDomain(forName: "ReachPromptsTests.\(name)")
        return d
    }

    // MARK: Injuries

    func test_injuriesUnansweredOnFreshMemory() {
        XCTAssertFalse(ReachPrompts.injuriesAnswered(memory: TrainingMemory(), defaults: defaults()))
    }

    func test_openingTheEditorCountsAsAnswering() {
        let d = defaults()
        ReachPrompts.markInjuriesAnswered(defaults: d)
        XCTAssertTrue(ReachPrompts.injuriesAnswered(memory: TrainingMemory(), defaults: d))
    }

    func test_listedInjuryOrNoteCountsAsAnswered() {
        var withInjury = TrainingMemory()
        withInjury.userInjuries = [UserInjury(slug: "rotator-cuff")]
        XCTAssertTrue(ReachPrompts.injuriesAnswered(memory: withInjury, defaults: defaults()))
        var withNote = TrainingMemory()
        withNote.constraints = ["bad ankle"]
        XCTAssertTrue(ReachPrompts.injuriesAnswered(memory: withNote, defaults: defaults()))
    }

    // MARK: Weekly reminder offer

    func test_offerOnlyOnFirstCheckIn() {
        let d = defaults()
        XCTAssertTrue(ReachPrompts.shouldOfferReminder(priorCheckInCount: 0, reminderEnabled: false, defaults: d))
        XCTAssertFalse(ReachPrompts.shouldOfferReminder(priorCheckInCount: 1, reminderEnabled: false, defaults: d))
    }

    func test_noOfferWhenReminderAlreadyOn() {
        XCTAssertFalse(ReachPrompts.shouldOfferReminder(priorCheckInCount: 0, reminderEnabled: true, defaults: defaults()))
    }

    func test_offerHappensOnce() {
        let d = defaults()
        ReachPrompts.markReminderOffered(defaults: d)
        XCTAssertFalse(ReachPrompts.shouldOfferReminder(priorCheckInCount: 0, reminderEnabled: false, defaults: d))
    }

    // MARK: Erase all data

    func test_flagsUsePtPrefixAndEraseAllClearsThem() {
        XCTAssertTrue(ReachPrompts.injuriesAnsweredKey.hasPrefix("pt_"))
        XCTAssertTrue(ReachPrompts.reminderOfferedKey.hasPrefix("pt_"))
        let d = defaults()
        ReachPrompts.markInjuriesAnswered(defaults: d)
        ReachPrompts.markReminderOffered(defaults: d)
        MemoryStore.wipeAllUserData(defaults: d, userDB: UserDatabase(path: ":memory:"))
        XCTAssertFalse(d.bool(forKey: ReachPrompts.injuriesAnsweredKey))
        XCTAssertFalse(d.bool(forKey: ReachPrompts.reminderOfferedKey))
        XCTAssertTrue(ReachPrompts.shouldOfferReminder(priorCheckInCount: 0, reminderEnabled: false, defaults: d))
    }
}
