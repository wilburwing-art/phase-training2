// SignalsReadout.swift — "is it collecting?" at a glance, for the DEBUG
// Signals sheet in Profile. Pure summary over the logs A2 to B1a write, so
// the owner can see accrual on the phone without a debugger.

import Foundation

struct SignalsReadout: Equatable {
    var outcomesByKind: [DayOutcomeKind: Int]
    var outcomesTotal: Int
    var twinPairs: Int
    var exploreVisits28d: Int
    var exploreConverted28d: Int
    /// Distinct normalised queries in the last 28 days that found nothing:
    /// the catalog-gap list.
    var zeroResultQueries28d: [String]
    var suggestionsToday: [Suggestion]
    var decisionsApplied: Int
    var decisionsDismissed: Int

    static func make(outcomes: [DayOutcome], explore: [ExploreSession],
                     suggestions: [Suggestion], decisions: [SuggestionDecision],
                     now: Date = Date()) -> SignalsReadout {
        let cutoff = now.addingTimeInterval(-28 * 86_400)
        var byKind: [DayOutcomeKind: Int] = [:]
        for o in outcomes { byKind[o.kind, default: 0] += 1 }
        let recent = explore.filter { $0.startedAt >= cutoff }
        let gaps = Set(recent.compactMap { $0.resultCount == 0 ? $0.query : nil }).sorted()
        return SignalsReadout(
            outcomesByKind: byKind,
            outcomesTotal: outcomes.count,
            twinPairs: TwinScorecard.from(outcomes).pairs.n,
            exploreVisits28d: recent.count,
            exploreConverted28d: recent.filter(\.converted).count,
            zeroResultQueries28d: gaps,
            suggestionsToday: suggestions,
            decisionsApplied: decisions.filter(\.accepted).count,
            decisionsDismissed: decisions.filter { !$0.accepted }.count)
    }
}
