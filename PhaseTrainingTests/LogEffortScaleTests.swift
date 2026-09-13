// LogEffortScaleTests — the per-set effort menu has to be able to record the
// effort the plan asks for.
//
// The two ends of that contract live far apart: DemandScheme writes the RPE
// band into the workout, LogSetRow.effortOptions is what the user can tap. They
// drifted once already — the menu bottomed out at 6 while prehab was
// prescribed at RPE 5-6, so the one thing the plan asked for on those sets was
// the one thing the logger couldn't store. This pins them together.

import XCTest
@testable import PhaseTraining

final class LogEffortScaleTests: XCTestCase {

    private var options: [Double] {
        LogScreen.effortOptions.compactMap { Double($0) }
    }

    func test_everyOptionIsANumber() {
        XCTAssertEqual(options.count, LogScreen.effortOptions.count,
                       "the menu is stored as strings but read back with Double(): \(LogScreen.effortOptions)")
    }

    func test_scaleRunsFromFiveToTen() {
        XCTAssertEqual(options.min(), 5)
        XCTAssertEqual(options.max(), 10)
    }

    func test_optionsAreAscendingAndUnique() {
        XCTAssertEqual(options, options.sorted(), "the menu should read low to high")
        XCTAssertEqual(Set(options).count, options.count)
    }

    /// The floor has to reach whatever the generator can prescribe. Prehab sits
    /// at RPE 5; if a future scheme goes lower, this fails rather than quietly
    /// shipping a session whose target effort can't be logged.
    func test_menuCoversEveryPrescribableRPE() {
        let lows = DemandScheme.base.values.compactMap(\.intensityRPELow).map { Double($0) }
        let highs = DemandScheme.base.values.compactMap(\.intensityRPEHigh).map { Double($0) }
        XCTAssertFalse(lows.isEmpty, "precondition: the schemes prescribe RPE at all")

        guard let floor = options.min(), let ceiling = options.max() else {
            return XCTFail("effort menu is empty")
        }
        if let lowest = lows.min() {
            XCTAssertLessThanOrEqual(floor, lowest,
                                     "a scheme prescribes RPE \(lowest); the effort menu starts at \(floor)")
        }
        if let highest = highs.max() {
            XCTAssertGreaterThanOrEqual(ceiling, highest,
                                        "a scheme prescribes RPE \(highest); the effort menu stops at \(ceiling)")
        }
    }

    /// RPE and RIR are two ways of writing the same thing down, and roughly
    /// RPE = 10 - RIR. The RIR menu's easiest option ("5+") should not describe
    /// a set the RPE menu can't.
    func test_effortFloorReachesTheEasiestRIROption() {
        guard let floor = options.min() else { return XCTFail("effort menu is empty") }
        let easiestRIR = LogScreen.rirOptions
            .compactMap { Double($0.replacingOccurrences(of: "+", with: "")) }
            .max()
        guard let easiestRIR else { return XCTFail("RIR menu is empty") }
        XCTAssertLessThanOrEqual(floor, 10 - easiestRIR,
                                 "RIR \(easiestRIR)+ is about RPE \(10 - easiestRIR), below the menu's \(floor)")
    }
}
