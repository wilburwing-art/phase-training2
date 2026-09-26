// Counterfactual.swift — 2a of PLAN-next-gen.md: the counterfactual engine.
//
// For each planned lift day before the next sport day, what happens to the
// sport day's readiness if that day is skipped, moved, cut short, or swapped
// for a saved routine? Pure: the week plan, the history events and `now` go
// in, a report comes out. No I/O, no UI (2b is a later build).
//
// Readiness source. This reads whichever readiness source is live, which
// today is `ReadinessSignal` (the twin has not earned 1b). The caller passes
// the same events the live score is built from
// (`GeneratorContext.buildReadinessEvents`), so with nothing projected the
// engine's score at `now` IS the live `readinessScore`. Planned lift days are
// projected on top as one event each at the start of their day, and the score
// is read at the start of the sport day.
//
// Why no `Planner.generate`. The plan is already deterministic output of the
// planner, and `ReadinessSignal` depends only on WHEN sessions happen, never
// on what they contain. Re-running the planner per alternative would reshuffle
// the rest of the week (rotation, consolidation, skip-streak bias) and blur
// the one change being measured. So each alternative edits the existing
// plan's days directly. Revisit when the readiness source reads content
// (the twin's per-pattern load), since then the substituted workout matters.
//
// What each alternative can and cannot show under `ReadinessSignal`:
// - skip: removes the day's event. Lowers or keeps the score (density and
//   recency can only fall).
// - move(to:): same event on a rest day in the window. Changes recency, so
//   moving closer to the sport day raises the score and moving earlier lowers
//   it. Only rest days with nothing logged are offered as targets.
// - shorter: half the planned minutes. `ReadinessSignal` ignores duration
//   (`ReadinessEvent.duration` is carried but unread), so the delta is 0
//   today. Kept so the twin can fill it in without a shape change.
// - savedRoutine: the user's saved workout in the same slot, same timing.
//   Also 0 today for the same reason.
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
    /// Readiness on the sport day under the alternative. Nil when the
    /// alternative leaves no events at all: the signal then returns its
    /// neutral 0.5, which the generator treats as "no data" and ignores, so
    /// it is not a comparable score.
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

    /// Readiness right now from the same events, i.e. the live score.
    /// Nil when there are no events (the live path's `hasReadinessData`
    /// is false then).
    static func liveScore(history: [ReadinessEvent], now: Date) -> Double? {
        score(history, at: now)
    }

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
        guard let baseline = score(history + Array(planned.values), at: sportDay) else {
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
                score: score(history + Array(events.values), at: sportDay)))
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

    private static func score(_ events: [ReadinessEvent], at date: Date) -> Double? {
        events.isEmpty ? nil : ReadinessSignal.compute(events: events, now: date).score
    }

    /// Planned minutes: the day's override, else the workout's estimate.
    private static func minutes(_ d: DayPlan) -> Int {
        d.durationMinutes ?? d.generatedWorkout?.estimatedMinutes ?? 0
    }
}
