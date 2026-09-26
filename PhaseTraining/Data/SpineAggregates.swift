// SpineAggregates.swift — 5a of PLAN-next-gen.md.
//
// Per authored routine ("spine"): how its sessions ended, how often it was
// done as planned, where exercises start getting dropped, and which
// substitutions stuck. Pure, computed on device from DayOutcome.
//
// This is the exact shape a later consented upload would carry (track 5c),
// proven on one user first: counts and names only, no free text, no dates
// finer than the ISO week. Nothing here is sent anywhere in this build.

import Foundation

struct SpineAggregate: Equatable, Identifiable {
    var routineId: Int
    var id: Int { routineId }
    var sessions: Int
    var byKind: [DayOutcomeKind: Int]
    /// Share of sessions done as planned (asPlanned / sessions).
    var completionRate: Double
    /// Median zero-based position, in the planned list, of the first dropped
    /// exercise, over sessions that dropped something. Nil when none did.
    var medianFirstDropPosition: Double?
    /// planned -> logged swap pairs with counts, most frequent first.
    var substitutions: [(pair: ExerciseSwapPair, count: Int)]
    /// Distinct ISO weeks (yyyy-Www) the spine was run in.
    var weeks: [String]

    static func == (a: SpineAggregate, b: SpineAggregate) -> Bool {
        a.routineId == b.routineId && a.sessions == b.sessions && a.byKind == b.byKind
            && a.completionRate == b.completionRate && a.medianFirstDropPosition == b.medianFirstDropPosition
            && a.substitutions.map(\.pair) == b.substitutions.map(\.pair)
            && a.substitutions.map(\.count) == b.substitutions.map(\.count) && a.weeks == b.weeks
    }
}

enum SpineAggregates {

    static func make(outcomes: [DayOutcome], calendar: Calendar = Calendar(identifier: .iso8601)) -> [SpineAggregate] {
        let grouped = Dictionary(grouping: outcomes.filter { $0.plannedRoutineId != nil }) { $0.plannedRoutineId! }
        return grouped.map { id, rows in
            var byKind: [DayOutcomeKind: Int] = [:]
            for r in rows { byKind[r.kind, default: 0] += 1 }

            let firstDrops: [Int] = rows.compactMap { r in
                r.plannedExercises.firstIndex { name in
                    r.dropped.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
                }
            }.sorted()
            let median: Double? = firstDrops.isEmpty ? nil
                : firstDrops.count % 2 == 1 ? Double(firstDrops[firstDrops.count / 2])
                : Double(firstDrops[firstDrops.count / 2 - 1] + firstDrops[firstDrops.count / 2]) / 2

            var swapCounts: [ExerciseSwapPair: Int] = [:]
            for r in rows { for s in r.swaps { swapCounts[s, default: 0] += 1 } }
            let subs = swapCounts.sorted {
                $0.value != $1.value ? $0.value > $1.value : ($0.key.planned, $0.key.logged) < ($1.key.planned, $1.key.logged)
            }.map { (pair: $0.key, count: $0.value) }

            let weeks = Set(rows.map { r -> String in
                let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: r.date)
                return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
            }).sorted()

            return SpineAggregate(routineId: id, sessions: rows.count, byKind: byKind,
                                  completionRate: Double(byKind[.asPlanned] ?? 0) / Double(rows.count),
                                  medianFirstDropPosition: median, substitutions: subs, weeks: weeks)
        }.sorted { $0.sessions != $1.sessions ? $0.sessions > $1.sessions : $0.routineId < $1.routineId }
    }
}
