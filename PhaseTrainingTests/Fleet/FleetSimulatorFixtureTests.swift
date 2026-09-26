// FleetSimulatorFixtureTests.swift — the cross-repo contract test.
//
// The two JSON files beside this test are byte copies of eval-rig's
// test/fixtures/fleet/athletes/{a-0001,a-0002}.json (run fixture-s1: seed 1,
// 4 weeks from 2026-03-30, one steady athlete and one dropper). eval-rig fails
// its own test if the simulator stops reproducing those bytes; this test fails
// if the app can no longer decode or replay them. Refresh both copies together.

import XCTest
@testable import PhaseTraining

final class FleetSimulatorFixtureTests: XCTestCase {

    private func athlete(_ id: String) throws -> FleetAthlete {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "fleet-fixture-s1-\(id)", withExtension: "json"),
            "fixture missing from the test bundle")
        return try FleetContract.decodeAthlete(try Data(contentsOf: url), source: url.lastPathComponent)
    }

    func testSimulatorFixturesDecodeAndReplay() throws {
        for id in ["a-0001", "a-0002"] {
            let a = try athlete(id)
            XCTAssertEqual(a.athleteId, id)
            let p = try FleetReplay.predictions(for: a)
            XCTAssertEqual(p.athleteId, id)
            XCTAssertFalse(p.likelihood.isEmpty, "\(id): planned days should get a likelihood")
            XCTAssertTrue(p.likelihood.allSatisfy { (0...1).contains($0.p) }, "\(id): p outside 0...1")
            // The replay's output must be readable by the same contract decoder
            // the scorer's schema mirrors.
            let back = try FleetContract.decodePredictions(try FleetContract.encode(p))
            XCTAssertEqual(back, p)
        }
    }

    func testSimulatorFixtureReplayIsDeterministic() throws {
        let a = try athlete("a-0002")
        XCTAssertEqual(try FleetContract.encode(try FleetReplay.predictions(for: a)),
                       try FleetContract.encode(try FleetReplay.predictions(for: a)))
    }
}
