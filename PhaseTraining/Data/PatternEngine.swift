// PatternEngine.swift — A4 of PLAN-predictive-recommendations.md.
//
// The first reader of the behavior the app records: DayOutcome (A2),
// ExploreSession (A3), and the abandonment log. It turns repeated behavior
// into at most three suggestions for the weekly check-in, each with its
// evidence and one concrete action. The app asks and the user decides;
// nothing here changes anything on its own.
//
// Rules are elimination-style counts over a 28-day window, learnable from a
// handful of events. Per-user volume is a few sessions a week, which is far
// too little for weights (see the scorer-outcome-feedback-loop skill).
//
// Pure: every input is passed in, `now` included. PlanStore+Suggestions
// gathers the inputs and performs accepted actions.

import Foundation

enum SuggestionRule: String, Codable, CaseIterable {
    /// Sessions keep overrunning the declared length, or get stopped for time.
    case sessionLength
    /// The same planned exercise keeps getting dropped.
    case droppedExercise
    /// The same bundled routine keeps getting opened and is not saved.
    case viewedRoutine
}

enum SuggestionAction: Codable, Hashable {
    /// Set `TrainingMemory.sessionMinutes`.
    case setSessionMinutes(Int)
    /// Set the exercise's affinity to the sink threshold (A1): the engine stops
    /// picking it but still covers a demand only it serves. Reversible.
    case sinkExercise(name: String)
    /// Copy a bundled coach.db routine into the user's saved workouts.
    case saveRoutine(routineId: Int, name: String)
}

struct Suggestion: Identifiable, Hashable {
    /// `rule:subject`, stable across runs so a decision sticks to it.
    var id: String
    var rule: SuggestionRule
    var title: String
    /// One line of evidence: counts and the window.
    var evidence: String
    var acceptLabel: String
    var action: SuggestionAction
    /// Dates of the events that qualified it, newest first.
    var eventDates: [Date]
}

struct SuggestionDecision: Codable, Hashable {
    var suggestionId: String
    var accepted: Bool
    var at: Date

    /// 26 weeks, the same window as weeklyCheckIns.
    static func prune(_ decisions: [SuggestionDecision], now: Date = Date()) -> [SuggestionDecision] {
        let cutoff = now.addingTimeInterval(-26 * 7 * 86_400)
        return decisions.filter { $0.at >= cutoff }
    }
}

enum PatternEngine {

    static let windowDays = 28
    static let maxSuggestions = 3
    /// A dismissed suggestion stays quiet this long.
    static let dismissCooldownDays = 56

    // Thresholds, named so tests and copy agree.
    static let overrunMinutes = 15
    static let overrunSessionsNeeded = 3
    static let overrunLookback = 5
    static let timeOutAbandonsNeeded = 2
    static let dropsNeeded = 3
    static let routineVisitsNeeded = 3

    struct Inputs {
        var outcomes: [DayOutcome]
        var abandoned: [AbandonedWorkoutEntry]
        var explore: [ExploreSession]
        var sessionMinutes: Int
        var affinities: [String: Int]
        var savedRoutineNames: Set<String>
        var decisions: [SuggestionDecision]
    }

    static func suggestions(_ input: Inputs, now: Date = Date()) -> [Suggestion] {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var out: [Suggestion] = []

        // Each candidate carries a qualifier over its own events so an
        // accepted suggestion can be re-tested on events after the accept.
        for (candidate, qualifies) in sessionLengthCandidates(input, cutoff: cutoff)
            + droppedCandidates(input, cutoff: cutoff)
            + routineCandidates(input, cutoff: cutoff) {
            guard allowed(candidate, qualifies: qualifies, decisions: input.decisions, now: now) else { continue }
            out.append(candidate)
            if out.count == maxSuggestions { break }
        }
        return out
    }

    // MARK: - Decisions

    private static func allowed(_ s: Suggestion, qualifies: ([Date]) -> Bool,
                                decisions: [SuggestionDecision], now: Date) -> Bool {
        guard let last = decisions.filter({ $0.suggestionId == s.id }).max(by: { $0.at < $1.at })
        else { return true }
        if last.accepted {
            // Only back if the evidence rebuilt from events after the accept.
            return qualifies(s.eventDates.filter { $0 > last.at })
        }
        return now.timeIntervalSince(last.at) > Double(dismissCooldownDays) * 86_400
    }

    typealias Candidate = (Suggestion, ([Date]) -> Bool)

    // MARK: - Rule: sessions run long

    private static func sessionLengthCandidates(_ input: Inputs, cutoff: Date) -> [Candidate] {
        let target = input.sessionMinutes
        guard target > 0 else { return [] }

        let finished = input.outcomes
            // Only sessions the planner sized. A switched or unplanned day ran
            // the user's own workout, so its length says nothing about ours.
            .filter { $0.date >= cutoff && ($0.kind == .asPlanned || $0.kind == .modified) }
            .sorted { $0.date > $1.date }
            .prefix(overrunLookback)
        let overruns = finished.filter { $0.durationMinutes >= ($0.targetMinutes ?? target) + overrunMinutes }

        let timeOuts = input.abandoned
            .filter { $0.date >= cutoff && $0.reason == .timeOut }
            .sorted { $0.date > $1.date }

        let byOverrun = overruns.count >= overrunSessionsNeeded
        let byTimeOut = timeOuts.count >= timeOutAbandonsNeeded
        guard byOverrun || byTimeOut else { return [] }

        let suggested: Int
        let evidence: String
        let dates: [Date]
        if byOverrun {
            // Keep the user's real time: plan sessions whose real duration
            // lands near the stated length, scaling by the observed overrun.
            let median = medianMinutes(overruns.map(\.durationMinutes))
            suggested = roundTo5(Double(target) * Double(target) / Double(max(median, 1)))
            evidence = "\(overruns.count) of your last \(finished.count) sessions ran long, typically \(median - target) minutes past \(target)."
            dates = overruns.map(\.date)
        } else {
            suggested = roundTo5(Double(target - 10))
            evidence = "\(timeOuts.count) workouts in the last 4 weeks stopped because time ran out."
            dates = timeOuts.map(\.date)
        }
        let minutes = min(max(suggested, 20), target - 5)
        guard minutes < target else { return [] }

        let s = Suggestion(
            // No subject: one session-length question at a time. The id must
            // not include the target, or accepting would mint a new id and the
            // same old sessions would re-fire it against the new length.
            id: SuggestionRule.sessionLength.rawValue,
            rule: .sessionLength,
            title: "Your workouts don't fit in \(target) minutes.",
            evidence: evidence,
            acceptLabel: "Plan \(minutes)-minute sessions",
            action: .setSessionMinutes(minutes),
            eventDates: dates)
        let needed = byOverrun ? overrunSessionsNeeded : timeOutAbandonsNeeded
        return [(s, { $0.count >= needed })]
    }

    // MARK: - Rule: a planned exercise keeps getting dropped

    private static func droppedCandidates(_ input: Inputs, cutoff: Date) -> [Candidate] {
        // Abandoned sessions drop everything after the stop, which says
        // nothing about any one exercise.
        var byName: [String: (display: String, dates: [Date])] = [:]
        for o in input.outcomes where o.date >= cutoff && o.kind != .abandoned {
            for name in Set(o.dropped.map { $0.lowercased() }) {
                let display = o.dropped.first { $0.lowercased() == name } ?? name
                byName[name, default: (display, [])].dates.append(o.date)
            }
        }
        let sink = AthleteState.affinitySinkThreshold
        let folded = AthleteState.lowercasedAffinities(input.affinities)
        return byName
            .filter { $0.value.dates.count >= dropsNeeded && (folded[$0.key] ?? 0) > sink }
            .sorted { $0.value.dates.count != $1.value.dates.count
                ? $0.value.dates.count > $1.value.dates.count : $0.key < $1.key }
            .map { key, value in
                let s = Suggestion(
                    id: "\(SuggestionRule.droppedExercise.rawValue):\(key)",
                    rule: .droppedExercise,
                    title: "You keep skipping \(value.display).",
                    evidence: "Dropped from \(value.dates.count) planned sessions in the last 4 weeks.",
                    acceptLabel: "Stop planning it",
                    action: .sinkExercise(name: value.display),
                    eventDates: value.dates.sorted(by: >))
                return (s, { $0.count >= dropsNeeded })
            }
    }

    // MARK: - Rule: a routine keeps getting opened

    private static func routineCandidates(_ input: Inputs, cutoff: Date) -> [Candidate] {
        var visits: [Int: (name: String, dates: [Date])] = [:]
        for session in input.explore where session.startedAt >= cutoff {
            // Count visits, not taps: opening one routine twice in a visit is one look.
            var seen = Set<Int>()
            for open in session.opens where open.kind == .routine {
                guard let id = Int(open.id), seen.insert(id).inserted else { continue }
                visits[id, default: (open.name, [])].dates.append(session.startedAt)
            }
        }
        let saved = Set(input.savedRoutineNames.map { $0.lowercased() })
        return visits
            .filter { $0.value.dates.count >= routineVisitsNeeded && !saved.contains($0.value.name.lowercased()) }
            .sorted { $0.value.dates.count != $1.value.dates.count
                ? $0.value.dates.count > $1.value.dates.count : $0.key < $1.key }
            .map { id, value in
                let s = Suggestion(
                    id: "\(SuggestionRule.viewedRoutine.rawValue):\(id)",
                    rule: .viewedRoutine,
                    title: "You keep coming back to \(value.name).",
                    evidence: "Opened on \(value.dates.count) separate visits in the last 4 weeks.",
                    acceptLabel: "Save to my workouts",
                    action: .saveRoutine(routineId: id, name: value.name),
                    eventDates: value.dates.sorted(by: >))
                return (s, { $0.count >= routineVisitsNeeded })
            }
    }

    // MARK: - Helpers

    static func medianMinutes(_ values: [Int]) -> Int {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func roundTo5(_ v: Double) -> Int { Int((v / 5).rounded()) * 5 }
}
