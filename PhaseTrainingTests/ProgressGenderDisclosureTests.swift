// ProgressGenderDisclosureTests.swift — SCAFFOLD (item 2 of 7).
//
// The strength-ratios card tells .nonbinary / .preferNotToSay users that
// their tiers "use the female thresholds" (ProgressScreen+BodyCards.swift
// tierDisclosure). StrengthStandards.tier routes those cases to
// femaleThresholds. Nothing asserted that the copy and the routing agree.

import XCTest
@testable import PhaseTraining

final class ProgressGenderDisclosureTests: XCTestCase {

    func test_nonbinary_tierMatchesFemaleCurve() { XCTFail("scaffold") }
    func test_preferNotToSay_tierMatchesFemaleCurve() { XCTFail("scaffold") }
    func test_male_tierDivergesFromFemaleCurve() { XCTFail("scaffold") }
    func test_nilGender_hasNoTier() { XCTFail("scaffold") }
    func test_rows_carryRoutedTierForNonbinary() { XCTFail("scaffold") }
}
