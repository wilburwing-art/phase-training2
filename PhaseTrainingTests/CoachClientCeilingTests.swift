import XCTest
@testable import PhaseTraining

/// `CoachClient.consumeDailyRequestBudget` is the only in-repo control on LLM
/// spend (T0-1, 2026-08-23) and until now nothing asserted it fires. The
/// gateway is BYOK and the token ships in the IPA, so this ceiling is what
/// stands between a distributed build and an unmetered proxy billed to the
/// developer, pending the external rotation.
final class CoachClientCeilingTests: XCTestCase {

    private func fresh(_ fn: String = #function) -> UserDefaults {
        let name = "CoachClientCeilingTests.\(fn)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private var cal: Calendar { Calendar(identifier: .gregorian) }
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400 + 43_200) }

    func test_allowsExactlyTheCeilingThenRefuses() {
        let d = fresh()
        for i in 0..<CoachConfig.dailyRequestCeiling {
            XCTAssertTrue(CoachClient.consumeDailyRequestBudget(defaults: d, now: day(1), calendar: cal),
                          "request \(i + 1) of \(CoachConfig.dailyRequestCeiling) should be allowed")
        }
        XCTAssertFalse(CoachClient.consumeDailyRequestBudget(defaults: d, now: day(1), calendar: cal),
                       "request \(CoachConfig.dailyRequestCeiling + 1) must be refused")
        XCTAssertFalse(CoachClient.consumeDailyRequestBudget(defaults: d, now: day(1), calendar: cal),
                       "and it must STAY refused for the rest of the day")
    }

    func test_rollsOverOnCalendarDay() {
        let d = fresh()
        for _ in 0..<CoachConfig.dailyRequestCeiling {
            _ = CoachClient.consumeDailyRequestBudget(defaults: d, now: day(1), calendar: cal)
        }
        XCTAssertFalse(CoachClient.consumeDailyRequestBudget(defaults: d, now: day(1), calendar: cal))
        XCTAssertTrue(CoachClient.consumeDailyRequestBudget(defaults: d, now: day(2), calendar: cal),
                      "a new calendar day resets the count")
    }

    func test_ceilingIsAboveTheChatHardCap() {
        // The ceiling covers every gateway caller (drawer, build-workout,
        // insights, refinement), so it has to sit above the drawer's own hard
        // cap or normal chat would hit the blunt gateway refusal instead of
        // the friendlier turn-cap banner.
        XCTAssertGreaterThan(CoachConfig.dailyRequestCeiling, CoachConfig.hardTurnCap)
    }

    func test_refusedRequestDoesNotConsumeBudget() {
        let d = fresh()
        for _ in 0..<CoachConfig.dailyRequestCeiling {
            _ = CoachClient.consumeDailyRequestBudget(defaults: d, now: day(1), calendar: cal)
        }
        _ = CoachClient.consumeDailyRequestBudget(defaults: d, now: day(1), calendar: cal)
        let stored = d.integer(forKey: "pt_coach_gateway_requests_today")
        XCTAssertEqual(stored, CoachConfig.dailyRequestCeiling,
                       "a refused request must not push the counter past the ceiling")
    }
}
