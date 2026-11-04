import XCTest
@testable import PhaseTraining

/// The ski discipline reaches the engine: resolution, a real change in the
/// generated mix, the plan hash, and old payloads.
final class SkiDisciplineTests: XCTestCase {

    private func memory(_ slug: String, discipline: SportVariant? = nil, phase: SeasonPhase = .offSeason) -> TrainingMemory {
        var m = TrainingMemory()
        let sport = Sport.resolve(slug: slug)
        m.sports = [sport]
        m.primarySport = sport
        m.seasonsBySport = [sport: phase]
        m.defaultSeason = phase
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.skiDiscipline = discipline
        return m
    }

    func test_resolution() {
        XCTAssertEqual(memory("alpine-skiing").primaryVariant, .inbounds)
        XCTAssertEqual(memory("ski-mountaineering").primaryVariant, .skimo,
                       "a ski-mountaineering primary no longer trains as a resort skier")
        XCTAssertEqual(memory("alpine-skiing", discipline: .backcountry).primaryVariant, .backcountry)
        XCTAssertEqual(memory("climbing", discipline: .park).primaryVariant, .sportRoute,
                       "a stale ski discipline does nothing for a climber")
    }

    /// Backcountry adds uphill aerobic weight; across a week of sessions it
    /// should show up as more aerobicUphill demand than resort.
    func test_backcountryCarriesMoreUphillThanResort() {
        func uphill(_ m: TrainingMemory) -> Int {
            var n = 0
            for phase in [SeasonPhase.offSeason, .preSeason] {
                var mm = m
                mm.defaultSeason = phase
                if let s = mm.primarySport { mm.seasonsBySport = [s: phase] }
                for slot in 0..<3 {
                    let w = WorkoutGenerator.generateLift(liftIndex: slot, totalLifts: 3, memory: mm,
                                                          profile: DemographicProfile.from(mm),
                                                          hashSeed: "disc-\(phase.rawValue)-\(slot)")
                    let tail = w.provenance.components(separatedBy: "demands: ").last ?? ""
                    n += tail.split(separator: "/").filter { $0 == "aerobicUphill" }.count
                }
            }
            return n
        }
        let resort = uphill(memory("alpine-skiing"))
        let backcountry = uphill(memory("alpine-skiing", discipline: .backcountry))
        print("DISCIPLINE uphill demands resort=\(resort) backcountry=\(backcountry)")
        XCTAssertGreaterThan(backcountry, resort)
    }

    func test_hashMovesOnlyWhenChosen() {
        let base = memory("alpine-skiing")
        var chosen = base
        chosen.skiDiscipline = .inbounds
        XCTAssertNotEqual(base.planInputsHash, chosen.planInputsHash, "choosing, even resort, is an input")
        var unset = base
        unset.skiDiscipline = nil
        XCTAssertEqual(base.planInputsHash, unset.planInputsHash)
    }

    func test_oldPayloadDecodesWithoutTheField() throws {
        let data = try JSONEncoder().encode(memory("alpine-skiing", discipline: .park))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj["skiDiscipline"])
        obj.removeValue(forKey: "skiDiscipline")
        let old = try JSONDecoder().decode(TrainingMemory.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.skiDiscipline)
    }
}
