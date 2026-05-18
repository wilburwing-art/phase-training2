import XCTest
@testable import PhaseTraining

final class BodyMetricsTests: XCTestCase {

    func test_kgToLb_roundsToKnownConversion() {
        // 1 kg = 2.20462262 lb (NIST). Loose tolerance — display rounds anyway.
        XCTAssertEqual(BodyMetrics.kgToLb(1.0), 2.20462262, accuracy: 0.0001)
        XCTAssertEqual(BodyMetrics.kgToLb(100.0), 220.46226, accuracy: 0.001)
    }

    func test_lbToKg_roundsTrip() {
        let kg = 80.0
        let lb = BodyMetrics.kgToLb(kg)
        XCTAssertEqual(BodyMetrics.lbToKg(lb), kg, accuracy: 0.0001)
    }

    func test_cmToFeetInches_typicalHeights() {
        // 175 cm ≈ 5'9" (68.9 inches → rounds to 69 = 5'9")
        let h1 = BodyMetrics.cmToFeetInches(175)
        XCTAssertEqual(h1.feet, 5)
        XCTAssertEqual(h1.inches, 9)
        // 183 cm ≈ 6'0" (72 inches exact)
        let h2 = BodyMetrics.cmToFeetInches(183)
        XCTAssertEqual(h2.feet, 6)
        XCTAssertEqual(h2.inches, 0)
    }

    func test_feetInchesToCm_inversesCmConversion() {
        // 5'10" → 70 in × 2.54 = 177.8 → rounds to 178 cm
        XCTAssertEqual(BodyMetrics.feetInchesToCm(feet: 5, inches: 10), 178)
        // Out-of-bounds inches roll over into feet correctly.
        XCTAssertEqual(BodyMetrics.feetInchesToCm(feet: 0, inches: 72), 183)
    }

    func test_formatWeight_handlesNilAndUnits() {
        XCTAssertEqual(BodyMetrics.formatWeight(kg: nil, imperial: true), "—")
        XCTAssertEqual(BodyMetrics.formatWeight(kg: 80.0, imperial: false), "80.0 kg")
        XCTAssertEqual(BodyMetrics.formatWeight(kg: 80.0, imperial: true), "176.4 lb")
    }

    func test_formatHeight_handlesNilAndUnits() {
        XCTAssertEqual(BodyMetrics.formatHeight(cm: nil, imperial: true), "—")
        XCTAssertEqual(BodyMetrics.formatHeight(cm: 178, imperial: false), "178 cm")
        XCTAssertEqual(BodyMetrics.formatHeight(cm: 178, imperial: true), "5′ 10″")
    }
}
