// WeekConsolidator.swift — D3 of the adaptive-week PRD (consolidation engine).
//
// Pure DECISION layer: re-plan a set of lift-day focuses down to a smaller day
// count using best-practice merges, preserving coverage of every focus. It
// answers "if the user drops from N lift days to N-1, which focuses survive
// and what gets grafted onto them?"
//
// This is the decision only. The downstream wiring is separate and NOT yet
// built:
//   - generating a merged-focus workout (primary recipe + the secondary's key
//     compound) in WorkoutGenerator
//   - a 1/week consolidation cap on PlanStore (own budget, distinct from the
//     2/week reshuffle cap)
//   - turning ConsolidatedDay[] into PlanEdits and applying them
//   - the consultative miss-flow UI (D2) that offers consolidate-vs-reshuffle
//
// Consolidation is offered ONLY when MissedWorkoutAutopilot.proposeReshuffle
// returns [] for a week-full / no-rest-day reason — NOT for budget exhaustion
// (PRD §6 Q4). A merged day holds at most two focuses, so the feasible floor
// is ceil(N/2) days; consolidate() clamps to it so coverage is never lost.
//
// All pure functions. No state. Easy to test against synthetic focus lists.

import Foundation

enum WeekConsolidator {

    /// One consolidated training day: trains `primary`, optionally grafting the
    /// key compound work of a merged-away `secondary` focus. A nil secondary is
    /// an ordinary single-focus day.
    struct ConsolidatedDay: Equatable {
        let primary: WorkoutFocus
        let secondary: WorkoutFocus?
    }

    /// Re-plan `focuses` (this week's lift-day focuses, in order) down to
    /// `targetDays`, merging the surplus onto survivors.
    ///
    /// Invariants:
    ///   - every input focus's coverage is preserved — it appears as a
    ///     `primary` or a `secondary` in the result
    ///   - the result has `max(ceil(N/2), min(targetDays, N))` days (a merged
    ///     day holds ≤2 focuses, so we can't go below ceil(N/2) without
    ///     dropping coverage)
    ///   - each input focus returned as a solo day when no reduction is needed
    static func consolidate(_ focuses: [WorkoutFocus], to targetDays: Int) -> [ConsolidatedDay] {
        guard !focuses.isEmpty else { return [] }
        let minFeasible = (focuses.count + 1) / 2          // ceil(N/2)
        let target = max(minFeasible, min(targetDays, focuses.count))
        var days = focuses.map { ConsolidatedDay(primary: $0, secondary: nil) }
        guard days.count > target else { return days }

        while days.count > target {
            // Step 1 — drop a redundant duplicate primary first: its coverage
            // is already present on the kept copy, so 4-day U/L/U/L collapses to
            // U/L with no grafting. Prefer a duplicate carrying no secondary so
            // no grafted coverage is lost.
            if let dupIdx = firstRedundantIndex(days) {
                days.remove(at: dupIdx)
                continue
            }
            // Step 2 — graft a surplus focus onto the most complementary
            // survivor. Pull a solo (un-merged) day from the end so earlier
            // (usually heavier / higher-priority) days stay solo longest.
            guard let surplus = days.last(where: { $0.secondary == nil }) else { break }
            let surplusIdx = days.firstIndex(of: surplus)!
            days.remove(at: surplusIdx)
            let hostIdx = bestHostIndex(for: surplus.primary, in: days)
            let host = days[hostIdx]
            days[hostIdx] = ConsolidatedDay(primary: host.primary, secondary: surplus.primary)
        }
        return days
    }

    // MARK: - Internals

    /// Index of a day whose primary focus already appeared earlier — a
    /// redundant day safe to drop. Prefers a duplicate carrying no grafted
    /// secondary so no coverage is lost.
    private static func firstRedundantIndex(_ days: [ConsolidatedDay]) -> Int? {
        var seen: Set<WorkoutFocus> = []
        var fallback: Int? = nil
        for (i, d) in days.enumerated() {
            if seen.contains(d.primary) {
                if d.secondary == nil { return i }
                if fallback == nil { fallback = i }
            }
            seen.insert(d.primary)
        }
        return fallback
    }

    /// Pick the survivor that best complements `focus`: prefer the opposite
    /// body region (graft an upper focus onto a lower day and vice-versa) so the
    /// merged day is balanced, and prefer a host that has no secondary yet.
    private static func bestHostIndex(for focus: WorkoutFocus, in days: [ConsolidatedDay]) -> Int {
        let focusIsUpper = isUpperRegion(focus)
        // Opposite region AND still solo — the ideal balanced host.
        if let i = days.firstIndex(where: { isUpperRegion($0.primary) != focusIsUpper && $0.secondary == nil }) {
            return i
        }
        // Any still-solo host (don't overwrite an existing graft).
        if let i = days.firstIndex(where: { $0.secondary == nil }) {
            return i
        }
        // Opposite region even if already merged (last resort).
        if let i = days.firstIndex(where: { isUpperRegion($0.primary) != focusIsUpper }) {
            return i
        }
        return 0
    }

    /// Upper- vs lower-region classification for merge balancing. Full-body
    /// focuses count as upper for pairing — they already include lower work, so
    /// grafting another upper onto them is the least disruptive.
    private static func isUpperRegion(_ focus: WorkoutFocus) -> Bool {
        switch focus {
        case .push, .pull, .upper, .fullBodyA, .fullBodyB: return true
        case .legs, .lower: return false
        }
    }
}
