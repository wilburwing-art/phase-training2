// SetPropagationTests — the forward-fill rule behind the log's auto-filled
// weight and reps columns.
//
// The rule lives on [LoggedSet] rather than in LogScreen precisely so it can be
// tested here: the view layer only owns the debounce and which key path to
// pass. Both columns run the same code, so each case is asserted for weight and
// reps together — they must not drift apart.

import XCTest
@testable import PhaseTraining

final class SetPropagationTests: XCTestCase {

    private func sets(_ values: [(weight: String, reps: String, done: Bool)]) -> [LoggedSet] {
        values.enumerated().map { i, v in
            LoggedSet(num: i + 1, weight: v.weight, reps: v.reps, rpe: "", done: v.done)
        }
    }

    // MARK: - The straight-sets case

    func test_fillsEmptyLaterSets() {
        var s = sets([("", "", false), ("", "", false), ("", "", false)])
        s.propagateForward(\.weight, from: 0, replacing: "", with: "135")
        s.propagateForward(\.reps, from: 0, replacing: "", with: "8")
        XCTAssertEqual(s.map(\.weight), ["", "135", "135"])
        XCTAssertEqual(s.map(\.reps), ["", "8", "8"])
    }

    func test_overwritesLaterSetsStillCarryingTheOldValue() {
        var s = sets([("135", "8", false), ("135", "8", false), ("135", "8", false)])
        s.propagateForward(\.weight, from: 0, replacing: "135", with: "145")
        s.propagateForward(\.reps, from: 0, replacing: "8", with: "10")
        XCTAssertEqual(s.map(\.weight), ["135", "145", "145"])
        XCTAssertEqual(s.map(\.reps), ["8", "10", "10"])
    }

    // MARK: - Where it stops

    func test_leavesCustomizedLaterSetsAlone() {
        // The pyramid case: set 3 was deliberately set to something else, so
        // the fill must not reach back over the user's own edit.
        var s = sets([("135", "12", false), ("135", "12", false), ("185", "5", false)])
        s.propagateForward(\.weight, from: 0, replacing: "135", with: "145")
        s.propagateForward(\.reps, from: 0, replacing: "12", with: "10")
        XCTAssertEqual(s.map(\.weight), ["135", "145", "185"])
        XCTAssertEqual(s.map(\.reps), ["12", "10", "5"])
    }

    func test_neverRewritesLoggedSets() {
        // Set 2 is done — that's history, not a prediction.
        var s = sets([("135", "8", false), ("135", "8", true), ("135", "8", false)])
        s.propagateForward(\.weight, from: 0, replacing: "135", with: "145")
        s.propagateForward(\.reps, from: 0, replacing: "8", with: "10")
        XCTAssertEqual(s.map(\.weight), ["135", "135", "145"])
        XCTAssertEqual(s.map(\.reps), ["8", "8", "10"])
    }

    func test_editingALaterSetOnlyMovesForward() {
        var s = sets([("135", "8", false), ("135", "8", false), ("135", "8", false)])
        s.propagateForward(\.weight, from: 1, replacing: "135", with: "155")
        XCTAssertEqual(s.map(\.weight), ["135", "135", "155"],
                       "set 1 is above the edit and must not change")
    }

    // MARK: - Edges

    func test_lastSetIsANoOp() {
        var s = sets([("135", "8", false), ("135", "8", false)])
        s.propagateForward(\.weight, from: 1, replacing: "135", with: "155")
        XCTAssertEqual(s.map(\.weight), ["135", "135"])
    }

    func test_outOfRangeIndexIsANoOp() {
        // The debounced caller can fire after a set was deleted.
        var s = sets([("135", "8", false)])
        s.propagateForward(\.weight, from: 5, replacing: "135", with: "155")
        XCTAssertEqual(s.map(\.weight), ["135"])
    }

    func test_emptySetListIsANoOp() {
        var s: [LoggedSet] = []
        s.propagateForward(\.weight, from: 0, replacing: "", with: "135")
        XCTAssertTrue(s.isEmpty)
    }

    func test_clearingAColumnClearsTheRowsThatFollowedIt() {
        // Consistent with the fill: rows that only hold the value because it
        // was copied down follow the source when it is emptied.
        var s = sets([("", "", false), ("135", "8", false), ("135", "8", false)])
        s.propagateForward(\.weight, from: 0, replacing: "135", with: "")
        XCTAssertEqual(s.map(\.weight), ["", "", ""])
    }

    // MARK: - The columns are independent

    func test_fillingOneColumnLeavesTheOtherUntouched() {
        var s = sets([("135", "8", false), ("", "", false)])
        s.propagateForward(\.weight, from: 0, replacing: "", with: "135")
        XCTAssertEqual(s[1].weight, "135")
        XCTAssertEqual(s[1].reps, "", "a weight fill must not write reps")
    }
}
