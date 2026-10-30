import XCTest
@testable import PhaseTraining

/// Goal and past workouts join the stated/assumed bookkeeping: both are rows
/// in Finish setup, only the goal gets a Week chip, and neither moves the plan
/// hash when it is marked stated.
final class SetupChecklistGoalHistoryTests: XCTestCase {

    private func decoded(_ memory: TrainingMemory) throws -> TrainingMemory {
        try JSONDecoder().decode(TrainingMemory.self, from: JSONEncoder().encode(memory))
    }

    func test_freshMemory_assumesGoalAndHistory() {
        let m = TrainingMemory()
        XCTAssertTrue(m.assumedFields.contains(.goal))
        XCTAssertTrue(m.assumedFields.contains(.history))
        XCTAssertEqual(m.assumptionSummary(for: .goal), "Sport performance")
        XCTAssertEqual(m.assumptionSummary(for: .history), "Not imported yet")
    }

    func test_onlyHistorySkipsTheWeekChips() {
        XCTAssertEqual(ProfileField.allCases.filter { !$0.shapesWeek }, [.history])
    }

    func test_aGoalPickedBeforeTheRowExisted_decodesAsStated() throws {
        var picked = TrainingMemory()
        picked.statedFields = []
        picked.trainingGoal = .strength
        XCTAssertTrue(try decoded(picked).isStated(.goal))

        var untouched = TrainingMemory()
        untouched.statedFields = []
        XCTAssertFalse(try decoded(untouched).isStated(.goal))
    }

    func test_markingStated_leavesThePlanHashAlone() {
        var m = TrainingMemory()
        let before = m.planInputsHash
        m.markStated(.goal)
        m.markStated(.history)
        XCTAssertEqual(m.planInputsHash, before)
        XCTAssertEqual(m.assumptionSummary(for: .history), "Done")
    }
}
