// TrainingMemoryEraOverrideTests — verify that the Phase-1 `eraOverride`
// field round-trips through Codable and that legacy saves without the
// key decode cleanly (the tolerant-decode contract that every new
// TrainingMemory field has to honor — see comment at the top of
// TrainingMemory.swift).

import XCTest
@testable import PhaseTraining

final class TrainingMemoryEraOverrideTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultEraOverrideIsNil() {
        let m = TrainingMemory()
        XCTAssertNil(m.eraOverride)
    }

    // MARK: - Legacy decode

    /// Legacy JSON written before Phase 1 (no eraOverride key). Must
    /// decode without error; eraOverride must come back nil so the
    /// generator falls through to the derived cohort.
    func testLegacyJSONWithoutEraOverrideDecodesCleanly() throws {
        let legacyJSON = """
        {
          "schemaVersion": 6,
          "sports": [],
          "focuses": ["general_strength"],
          "seasonsBySport": {},
          "defaultSeason": "maintenance",
          "sessionMinutes": 45,
          "liftDaysPerWeek": 3,
          "equipment": ["none"],
          "experience": "intermediate",
          "startingState": "fresh_start",
          "age": 30,
          "usesImperial": true,
          "dislikes": [],
          "constraints": [],
          "exerciseAffinities": {},
          "userInjuries": [],
          "feedback": [],
          "soreness": [],
          "weeklyCheckIns": [],
          "coachInsights": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TrainingMemory.self, from: legacyJSON)
        XCTAssertNil(decoded.eraOverride)
        XCTAssertEqual(decoded.age, 30)
        XCTAssertEqual(decoded.experience, .intermediate)
    }

    // MARK: - Round-trip

    func testEraOverrideRoundTripPreservesValue() throws {
        var m = TrainingMemory()
        m.age = 33
        m.eraOverride = "magazine_bodybuilding"   // override the derived redditFitness

        let encoded = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(TrainingMemory.self, from: encoded)

        XCTAssertEqual(decoded.eraOverride, "magazine_bodybuilding")
        XCTAssertEqual(decoded.age, 33)
    }

    func testNilEraOverrideRoundTripStaysNil() throws {
        var m = TrainingMemory()
        m.age = 25
        m.eraOverride = nil

        let encoded = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(TrainingMemory.self, from: encoded)

        XCTAssertNil(decoded.eraOverride)
        XCTAssertEqual(decoded.age, 25)
    }

    /// Setting eraOverride to a string that doesn't match any EraCohort
    /// rawValue is allowed at the storage layer (this file doesn't know
    /// the catalog). DemographicProfile resolves unknown strings to nil
    /// (and falls through to derived). Confirm the round-trip preserves
    /// the raw string so a future cohort addition can be re-recognized.
    func testUnknownCohortStringRoundTripPreservesString() throws {
        var m = TrainingMemory()
        m.eraOverride = "future_cohort_2030"

        let encoded = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(TrainingMemory.self, from: encoded)

        XCTAssertEqual(decoded.eraOverride, "future_cohort_2030")
    }
}
