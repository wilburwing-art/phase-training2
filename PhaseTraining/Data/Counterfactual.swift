// Counterfactual.swift — 2a of PLAN-next-gen.md: the counterfactual engine.
//
// For each planned lift day before the next sport day, what happens to the
// sport day's readiness if that day is skipped, moved, cut short, or swapped
// for a saved routine? Pure: the week plan, the history events and `now` go
// in, a report comes out. No I/O, no UI (2b is a later build).
//
// Readiness source: `FormModel` (fitness-fatigue form), not the generator's
// `ReadinessSignal` (Wilbur, 2026-09-26: two numbers, two jobs). The caller
// passes `GeneratorContext.buildLoadEvents`, one event per day carrying that
// day's minutes. Planned lift days are projected on top as one event each at
// the start of their day with their planned minutes, and form is read at the
// start of the sport day.
//
// Why no `Planner.generate`. The plan is already deterministic output of the
// planner. Re-running it per alternative would reshuffle the rest of the week
// (rotation, consolidation, skip-streak bias) and blur the one change being
// measured, so each alternative edits the existing plan's days directly.
//
// What each alternative shows under form:
// - skip: removes the day's load. In the last days before the sport day this
//   usually RAISES form (less fresh fatigue); further back it lowers it.
// - move(to:): same load on a rest day in the window. Moving it closer to the
//   sport day adds fatigue there, so form usually drops. Only rest days with
//   nothing logged are offered as targets.
// - shorter: half the planned minutes, so less fatigue and usually higher form.
// - savedRoutine: the user's saved workout in the same slot at the same
//   minutes. 0 until load reads content (per-pattern load, a later step).
//
// Planned sport days before the target are NOT projected: the live builder
// drops hard sport logs, and a planned day carries no intensity, so leaving
// them out is the conservative reading. Days already logged are history, not
// plan, and get no alternatives.

import Foundation

enum CounterfactualAlternative: Hashable {
    case skip
    case move(to: Date)
    case shorter(minutes: Int)
    case savedRoutine(id: String, name: String)
}

struct CounterfactualOutcome: Equatable {
    /// Start of the planned lift day the alternative changes.
    let day: Date
    let alternative: CounterfactualAlternative
    /// Readiness on the sport day with the plan as it stands.
    let baseline: Double
    /// Form on the sport day under the alternative. Nil when the alternative
    /// leaves no load at all in the window, which is no data rather than a
    /// comparable score.
    let score: Double?

    var delta: Double? { score.map { $0 - baseline } }
}

struct CounterfactualReport: Equatable {
    /// Start of the next sport day after today, or nil when the plan has none.
    let sportDay: Date?
    /// Sport-day readiness with the plan as it stands. Nil when there is no
    /// sport day or no events at all.
    let baseline: Double?
    /// Ordered by planned day, then skip, moves (earliest target first),
    /// shorter, saved routines (input order).
    let outcomes: [CounterfactualOutcome]

    static let empty = CounterfactualReport(sportDay: nil, baseline: nil, outcomes: [])

    /// The outcome with the largest absolute nonzero delta; the first one wins
    /// a tie. Nil when nothing moves the score.
    var largestImpact: CounterfactualOutcome? {
        var best: CounterfactualOutcome?
        var bestSize = 1e-9
        for o in outcomes {
            guard let d = o.delta, abs(d) > bestSize else { continue }
            best = o
            bestSize = abs(d)
        }
        return best
    }
}

enum Counterfactual {

    static func evaluate(
        plan: WeekPlan,
        history: [ReadinessEvent],
        savedRoutines: [CustomRoutine] = [],
        now: Date,
        calendar: Calendar = .current
    ) -> CounterfactualReport {
        let today = calendar.startOfDay(for: now)
        func start(_ d: DayPlan) -> Date { calendar.startOfDay(for: d.date) }

        let days = plan.days.sorted { $0.date < $1.date }
        guard let sport = days.first(where: { $0.kind == .sport && start($0) > today }) else {
            return .empty
        }
        let sportDay = start(sport)
        let loggedDays = Set(history.map { calendar.startOfDay(for: $0.startTime) })
        let window = days.filter { start($0) >= today && start($0) < sportDay }
        let lifts = window.filter { $0.kind == .lift && !loggedDays.contains(start($0)) }

        var planned: [Date: ReadinessEvent] = [:]
        for d in lifts {
            planned[start(d)] = ReadinessEvent(startTime: start(d), duration: Double(minutes(d)) * 60)
        }
        func score(_ events: [ReadinessEvent]) -> Double? {
            FormModel.form(events: events, at: sportDay, calendar: calendar)
        }
        guard let baseline = score(history + Array(planned.values)) else {
            return CounterfactualReport(sportDay: sportDay, baseline: nil, outcomes: [])
        }

        let moveTargets = window
            .filter { $0.kind == .rest }
            .map(start)
            .filter { !loggedDays.contains($0) && planned[$0] == nil }

        var outcomes: [CounterfactualOutcome] = []
        func add(_ key: Date, _ alt: CounterfactualAlternative, _ events: [Date: ReadinessEvent]) {
            outcomes.append(CounterfactualOutcome(
                day: key, alternative: alt, baseline: baseline,
                score: score(history + Array(events.values))))
        }

        for d in lifts {
            let key = start(d)
            let duration = planned[key]?.duration ?? 0

            var skipped = planned
            skipped[key] = nil
            add(key, .skip, skipped)

            for target in moveTargets {
                var moved = skipped
                moved[target] = ReadinessEvent(startTime: target, duration: duration)
                add(key, .move(to: target), moved)
            }

            let mins = minutes(d)
            if mins > 1 {
                var shorter = planned
                shorter[key] = ReadinessEvent(startTime: key, duration: Double(mins / 2) * 60)
                add(key, .shorter(minutes: mins / 2), shorter)
            }

            for r in savedRoutines {
                var swapped = planned
                swapped[key] = ReadinessEvent(startTime: key, duration: duration)
                add(key, .savedRoutine(id: r.id, name: r.name), swapped)
            }
        }
        return CounterfactualReport(sportDay: sportDay, baseline: baseline, outcomes: outcomes)
    }

    /// One line for the DEBUG Signals row, e.g.
    /// "skip Tue: Sat readiness 0.71 -> 0.63".
    static func summary(_ o: CounterfactualOutcome, sportDay: Date, calendar: Calendar = .current) -> String {
        func wd(_ d: Date) -> String {
            let symbols = calendar.shortWeekdaySymbols
            let i = calendar.component(.weekday, from: d) - 1
            return symbols.indices.contains(i) ? symbols[i] : "?"
        }
        let what: String
        switch o.alternative {
        case .skip: what = "skip \(wd(o.day))"
        case .move(let to): what = "move \(wd(o.day)) to \(wd(to))"
        case .shorter(let m): what = "\(wd(o.day)) at \(m) min"
        case .savedRoutine(_, let name): what = "\(name) on \(wd(o.day))"
        }
        let after = o.score.map { String(format: "%.2f", $0) } ?? "no data"
        return "\(what): \(wd(sportDay)) readiness \(String(format: "%.2f", o.baseline)) -> \(after)"
    }

    // MARK: - Private

    /// Planned minutes: the day's override, else the workout's estimate.
    private static func minutes(_ d: DayPlan) -> Int {
        d.durationMinutes ?? d.generatedWorkout?.estimatedMinutes ?? 0
    }
}
