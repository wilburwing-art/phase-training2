// SignalsReadoutTests.swift — the DEBUG Signals readout's aggregation.

import XCTest
@testable import PhaseTraining

final class SignalsReadoutTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func outcome(_ kind: DayOutcomeKind, twinActual: Double?) -> DayOutcome {
        var o = DayOutcome(sessionId: Double.random(in: 0...1e9), date: now, kind: kind, plannedDayKind: .lift,
                           plannedTitle: nil, plannedExercises: [], plannedWorkingSets: 0, plannedMinutes: nil,
                           targetMinutes: nil, loggedTemplateId: "", loggedTitle: "", loggedExercises: [],
                           completedWorkingSets: 0, durationMinutes: 0, swaps: [], dropped: [], added: [],
                           recordedAt: now)
        o.twin = TwinPrediction(params: .defaults, readiness: 0.5,
                                exercises: [TwinExercisePrediction(exercise: "S", predicted: 1, baseline: 1, actual: twinActual)])
        return o
    }

    private func visit(daysAgo: Double, query: String?, results: Int?, converted: Bool = false) -> ExploreSession {
        let at = now.addingTimeInterval(-daysAgo * 86_400)
        var s = ExploreSession(surface: .library, startedAt: at, endedAt: at, query: query, resultCount: results)
        if converted {
            s.conversions = [ExploreConversion(kind: .swapIn, itemKind: .exercise, id: "1", name: "X", query: query, at: at)]
        }
        return s
    }

    func test_countsOutcomesTwinPairsVisitsAndGaps() {
        let r = SignalsReadout.make(
            outcomes: [outcome(.asPlanned, twinActual: 100), outcome(.asPlanned, twinActual: nil),
                       outcome(.switched, twinActual: 90)],
            explore: [visit(daysAgo: 1, query: "sled push", results: 0),
                      visit(daysAgo: 2, query: "sled push", results: 0),
                      visit(daysAgo: 3, query: "pull up", results: 6, converted: true),
                      visit(daysAgo: 40, query: "old gap", results: 0)],
            suggestions: [],
            decisions: [SuggestionDecision(suggestionId: "a", accepted: true, at: now),
                        SuggestionDecision(suggestionId: "b", accepted: false, at: now)],
            now: now)
        XCTAssertEqual(r.outcomesTotal, 3)
        XCTAssertEqual(r.outcomesByKind[.asPlanned], 2)
        XCTAssertEqual(r.twinPairs, 2, "only predictions with an actual count")
        XCTAssertEqual(r.exploreVisits28d, 3)
        XCTAssertEqual(r.exploreConverted28d, 1)
        XCTAssertEqual(r.zeroResultQueries28d, ["sled push"], "deduplicated, and 40 days ago is out of window")
        XCTAssertEqual(r.decisionsApplied, 1)
        XCTAssertEqual(r.decisionsDismissed, 1)
    }

    func test_emptyLogs_readAsZero() {
        let r = SignalsReadout.make(outcomes: [], explore: [], suggestions: [], decisions: [], now: now)
        XCTAssertEqual(r.outcomesTotal, 0)
        XCTAssertEqual(r.twinPairs, 0)
        XCTAssertTrue(r.zeroResultQueries28d.isEmpty)
    }
}
