//
//  CoachBubbleUnreadTests.swift
//  PhaseTrainingTests
//
//  The coach button's unread dot is driven by whether any turn carries a
//  proposal the user has neither applied nor rejected.
//

import XCTest
@testable import PhaseTraining

final class CoachBubbleUnreadTests: XCTestCase {

    private func store() -> CoachConversationStore {
        let d = UserDefaults(suiteName: "CoachBubbleUnreadTests")!
        d.removePersistentDomain(forName: "CoachBubbleUnreadTests")
        return CoachConversationStore(defaults: d)
    }

    private func proposal(_ status: CoachProposal.Status) -> CoachProposal {
        var p = CoachProposal(ops: [], reasoning: "test")
        p.status = status
        return p
    }

    func testNoMessagesIsNotPending() {
        XCTAssertFalse(store().hasPendingProposal)
    }

    func testPlainAssistantTurnIsNotPending() {
        let s = store()
        s.messages = [CoachMessage(role: "assistant", text: "Tuesday is a rest day.")]
        XCTAssertFalse(s.hasPendingProposal)
    }

    func testPendingPlanProposalIsPending() {
        let s = store()
        s.messages = [CoachMessage(role: "assistant", text: "Moved it.",
                                   proposal: proposal(.pending))]
        XCTAssertTrue(s.hasPendingProposal)
    }

    func testAppliedAndRejectedAreNotPending() {
        for status in [CoachProposal.Status.applied, .rejected] {
            let s = store()
            s.messages = [CoachMessage(role: "assistant", text: "Moved it.",
                                       proposal: proposal(status))]
            XCTAssertFalse(s.hasPendingProposal, "\(status) should clear the dot")
        }
    }

    /// One decided proposal must not mask an undecided one on another turn.
    func testOneDecidedTurnDoesNotMaskAnUndecidedOne() {
        let s = store()
        s.messages = [
            CoachMessage(role: "assistant", text: "Applied.", proposal: proposal(.applied)),
            CoachMessage(role: "assistant", text: "And this?", proposal: proposal(.pending)),
        ]
        XCTAssertTrue(s.hasPendingProposal)
    }
}
