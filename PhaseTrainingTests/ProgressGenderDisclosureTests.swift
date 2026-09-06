// ProgressGenderDisclosureTests.swift — the strength-ratios card's gender
// contract.
//
// Two halves that must agree and had nothing holding them together:
//
//   1. StrengthStandards routes .nonbinary and .preferNotToSay to the FEMALE
//      threshold curve, because only two curves exist in the published
//      tables.
//   2. The Progress card tells those users exactly that.
//
// A change to either half alone is a change to what the app claims about a
// user's body. These tests pin both against one source of truth,
// StrengthStandards.curve(for:).

import XCTest
@testable import PhaseTraining

final class ProgressGenderDisclosureTests: XCTestCase {

    /// Ratios spanning below-novice through above-elite for every lift, so
    /// the curve comparison exercises each threshold band rather than one
    /// arbitrary point.
    private let ratios: [Double] = [
        0.0, 0.15, 0.25, 0.35, 0.5, 0.6, 0.75, 0.8, 1.0, 1.25,
        1.5, 1.75, 2.0, 2.25, 2.5, 3.0, 3.25, 4.0,
    ]

    // MARK: - Routing

    func test_nonbinary_tierMatchesFemaleCurve() {
        for lift in StrengthStandards.CanonicalLift.allCases {
            for ratio in ratios {
                XCTAssertEqual(
                    StrengthStandards.tier(for: lift, ratio: ratio, gender: .nonbinary),
                    StrengthStandards.tier(for: lift, ratio: ratio, gender: .female),
                    "\(lift) at \(ratio)× BW must score on the female curve"
                )
            }
        }
    }

    func test_preferNotToSay_tierMatchesFemaleCurve() {
        for lift in StrengthStandards.CanonicalLift.allCases {
            for ratio in ratios {
                XCTAssertEqual(
                    StrengthStandards.tier(for: lift, ratio: ratio, gender: .preferNotToSay),
                    StrengthStandards.tier(for: lift, ratio: ratio, gender: .female),
                    "\(lift) at \(ratio)× BW must score on the female curve"
                )
            }
        }
    }

    func test_curveAccessor_agreesWithTierRouting() {
        XCTAssertEqual(StrengthStandards.curve(for: .male), .male)
        XCTAssertEqual(StrengthStandards.curve(for: .female), .female)
        XCTAssertEqual(StrengthStandards.curve(for: .nonbinary), .female)
        XCTAssertEqual(StrengthStandards.curve(for: .preferNotToSay), .female)
    }

    func test_male_tierDivergesFromFemaleCurve() {
        // Guards against the routing tests passing vacuously (e.g. if the
        // thresholds were ever collapsed to one shared table, "nonbinary
        // matches female" would be true and meaningless).
        //
        // Bench at 1.0× BW: female thresholds put that at ADVANCED, male
        // thresholds at BEGINNER.
        XCTAssertNotEqual(
            StrengthStandards.tier(for: .bench, ratio: 1.0, gender: .male),
            StrengthStandards.tier(for: .bench, ratio: 1.0, gender: .female)
        )
    }

    func test_nilGender_hasNoTier() {
        // No curve is picked without consent, at any ratio.
        for lift in StrengthStandards.CanonicalLift.allCases {
            for ratio in ratios {
                XCTAssertNil(StrengthStandards.tier(for: lift, ratio: ratio, gender: nil))
            }
        }
    }

    func test_belowNoviceThreshold_hasNoTier() {
        // The floor is shared by both curves: under novice, no label.
        XCTAssertNil(StrengthStandards.tier(for: .bench, ratio: 0.1, gender: .nonbinary))
        XCTAssertNil(StrengthStandards.tier(for: .bench, ratio: 0.1, gender: .male))
    }

    // MARK: - Disclosure copy

    func test_disclosure_namesTheCurveNonbinaryUsersAreScoredOn() {
        // The copy says "female thresholds"; curve(for:) must agree, or the
        // card is telling the user something untrue.
        for gender: Gender in [.nonbinary, .preferNotToSay] {
            let copy = ProgressStats.strengthTierDisclosure(gender: gender)
            XCTAssertTrue(
                copy.contains("female thresholds"),
                "\(gender) disclosure must name the curve: \(copy)"
            )
            XCTAssertEqual(
                StrengthStandards.curve(for: gender), .female,
                "\(gender) copy claims the female curve; routing must match"
            )
        }
    }

    func test_disclosure_alwaysCarriesTheNotADiagnosisCaveat() {
        let genders: [Gender?] = [nil, .male, .female, .nonbinary, .preferNotToSay]
        for gender in genders {
            XCTAssertTrue(
                ProgressStats.strengthTierDisclosure(gender: gender)
                    .contains("not a diagnosis"),
                "Tier labels render as bare authoritative words; the caveat is not optional"
            )
        }
    }

    func test_disclosure_promptsForGenderOnlyWhenUnset() {
        XCTAssertTrue(
            ProgressStats.strengthTierDisclosure(gender: nil).contains("Add your gender")
        )
        for gender: Gender in [.male, .female, .nonbinary, .preferNotToSay] {
            XCTAssertFalse(
                ProgressStats.strengthTierDisclosure(gender: gender).contains("Add your gender"),
                "\(gender) is set; the card must not ask for it again"
            )
        }
    }

    func test_disclosure_doesNotNameACurveForBinaryGenders() {
        // Male/female users are scored on their own curve, so the two-curve
        // explanation would be noise.
        for gender: Gender in [.male, .female] {
            XCTAssertFalse(
                ProgressStats.strengthTierDisclosure(gender: gender).contains("two curves")
            )
        }
    }

    // MARK: - Row integration

    func test_rows_carryRoutedTierForNonbinary() {
        // End-to-end through rows(from:bodyweightKg:gender:): the row's tier
        // is the routed one, not nil and not the male label.
        let bodyweightLb = 150.0
        let sessions = [benchSession(weightLb: 150, reps: 5)]

        let nonbinaryRows = StrengthStandards.rows(
            from: sessions,
            bodyweightKg: BodyMetrics.lbToKg(bodyweightLb),
            gender: .nonbinary
        )
        let femaleRows = StrengthStandards.rows(
            from: sessions,
            bodyweightKg: BodyMetrics.lbToKg(bodyweightLb),
            gender: .female
        )

        XCTAssertFalse(nonbinaryRows.isEmpty, "Bench session must produce a row")
        XCTAssertEqual(nonbinaryRows.map(\.tier), femaleRows.map(\.tier))
        XCTAssertNotNil(nonbinaryRows.first?.tier)
    }

    private func benchSession(weightLb: Double, reps: Int) -> SavedSession {
        let start = Date().addingTimeInterval(-3600)
        let exercise = LoggedExercise(
            id: "bench", name: "Barbell Bench Press", type: nil, unit: "lbs",
            targetSets: 1, targetReps: reps, rest: 90,
            sets: [LoggedSet(num: 1, weight: "\(Int(weightLb))", reps: "\(reps)",
                             rpe: "", done: true, isWarmup: false)],
            prevSets: []
        )
        return SavedSession(
            templateId: "t", name: "Upper", category: "",
            startTime: start, exercises: [exercise],
            feel: nil, note: nil,
            endTime: start.addingTimeInterval(3600), duration: 3600
        )
    }
}
