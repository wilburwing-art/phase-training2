// FleetSimulatorFixtureTests.swift — the cross-repo contract test.
//
// The two JSON files beside this test are byte copies of eval-rig's
// test/fixtures/fleet/athletes/{a-0001,a-0002}.json (run fixture-s1: seed 1,
// 4 weeks from 2026-03-30, one steady athlete and one dropper). eval-rig fails
// its own test if the simulator stops reproducing those bytes; this test fails
// if the app can no longer decode or replay them. Refresh both copies together.
//
// fleet-v2-fixture-s1-a-000{1..5}.json are byte copies of eval-rig's
// test/fixtures/fleet-v2/athletes/*.json (schema 2, the population generator:
// seed 1, 4 weeks, one athlete per archetype, ff-sleep-stress readiness).

import XCTest
@testable import PhaseTraining

final class FleetSimulatorFixtureTests: XCTestCase {

    private func athlete(_ id: String, prefix: String = "fleet-fixture-s1") throws -> FleetAthlete {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "\(prefix)-\(id)", withExtension: "json"),
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

    func testV2FixturesDecodeAndReplay() throws {
        var archetypes: [String] = []
        for id in ["a-0001", "a-0002", "a-0003", "a-0004", "a-0005"] {
            let a = try athlete(id, prefix: "fleet-v2-fixture-s1")
            XCTAssertEqual(a.schemaVersion, 2)
            XCTAssertEqual(a.days.count, 28)
            archetypes.append(a.persona)
            let p = try FleetReplay.predictions(for: a)
            XCTAssertEqual(p.schemaVersion, 2, "\(id): predictions carry the athlete's schema version")
            XCTAssertTrue(p.likelihood.allSatisfy { (0...1).contains($0.p) }, "\(id): p outside 0...1")
            let back = try FleetContract.decodePredictions(try FleetContract.encode(p))
            XCTAssertEqual(back, p)
        }
        XCTAssertEqual(archetypes, ["population", "near-overrun", "near-drop", "control-overrun", "control-drop"])
    }
}
