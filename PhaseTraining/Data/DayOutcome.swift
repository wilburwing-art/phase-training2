// DayOutcome.swift — A2 of PLAN-predictive-recommendations.md.
//
// One frozen record per saved session: what the plan said for that day versus
// what the user actually did. It is the outcome label every behavior signal
// (swaps, affinities, explore intent) gets checked against.
//
// Why frozen at save time rather than derived on read: the two places that
// could answer "what did the planner originally want?" both decay.
// `snapshotCurrentPlan` REPLACES the week's snapshot on every capture, so after
// a wheel switch history holds the switched day; `overrides.displacedPlanByDate`
// keeps the planner's original, but WeekOverrides resets every Monday. A
// read-time derivation loses exactly the switched days.
//
// Missed days are NOT recorded here: `pt_missed_workouts` already covers them,
// and a reader joins the two logs by date.
//
// Persisted on PlanStore under `pt_day_outcomes`, rolling 90-day window, one
// record per session id.

import Foundation

enum DayOutcomeKind: String, Codable, CaseIterable, Hashable {
    /// Ran the planner's session: every planned exercise, no swaps, no
    /// additions, and at least the planned working sets.
    case asPlanned
    /// Ran the planner's session with changes: swaps, drops, additions, or
    /// fewer working sets than planned.
    case modified
    /// Ran something other than the planner's session (wheel / override
    /// switch to a saved or sample workout, or a routine started directly).
    case switched
    /// Trained on a day with no planned lift session.
    case unplanned
    /// Stopped early below the abandonment threshold (see AbandonedWorkoutEntry).
    case abandoned
}

struct ExerciseSwapPair: Codable, Hashable {
    var planned: String
    var logged: String
}

struct DayOutcome: Codable, Identifiable, Hashable {
    /// `SavedSession.id` — one outcome per session.
    var sessionId: TimeInterval
    var id: TimeInterval { sessionId }

    /// Start of the calendar day the session began on.
    var date: Date
    var kind: DayOutcomeKind

    // What the plan said
    var plannedDayKind: DayKind?
    var plannedTitle: String?
    /// The planner's own exercises. When the day was switched this is the
    /// DISPLACED original, not the workout the switch put there.
    var plannedExercises: [String]
    var plannedWorkingSets: Int
    var plannedMinutes: Int?
    /// The user's declared session length at save time.
    var targetMinutes: Int?

    // What happened
    var loggedTemplateId: String
    var loggedTitle: String
    var loggedExercises: [String]
    var completedWorkingSets: Int
    var durationMinutes: Int

    // The diff (empty for switched / unplanned)
    var swaps: [ExerciseSwapPair]
    var dropped: [String]
    var added: [String]

    var recordedAt: Date

    /// B1a — the shadow twin's prediction, frozen at save from history before
    /// this session. Nil on outcomes recorded before 2026-09-26.
    var twin: TwinPrediction? = nil
}

extension DayOutcome {

    /// Prefix `WorkoutGenerator.toWorkoutTemplate` gives a logged exercise
    /// built from a planned one. The id survives a mid-session swap (LogScreen
    /// renames the row in place), which is what makes swaps recoverable.
    static let plannedIdPrefix = "gex-"

    /// Pure derivation. `plannedDay` is the plan's day for the session's date
    /// (nil when the plan has none); `displaced` is the planner's original when
    /// the day was switched away from it.
    static func derive(session: SavedSession,
                       plannedDay: DayPlan?,
                       displaced: DisplacedPlan?,
                       abandoned: Bool,
                       targetMinutes: Int?,
                       now: Date = Date(),
                       calendar: Calendar = .current) -> DayOutcome {
        let original: GeneratedWorkout? = displaced?.workout ?? plannedDay?.generatedWorkout
        let plannedList = original?.exercises ?? []
        let plannedKind = displaced?.kind ?? plannedDay?.kind
        let plannedTitle = displaced?.title ?? plannedDay?.title

        let completed = session.exercises.reduce(0) { total, ex in
            total + ex.sets.filter { $0.done && !$0.isWarmup }.count
        }

        var outcome = DayOutcome(
            sessionId: session.id,
            date: calendar.startOfDay(for: session.startTime),
            kind: .unplanned,
            plannedDayKind: plannedKind,
            plannedTitle: plannedTitle,
            plannedExercises: plannedList.map(\.name),
            plannedWorkingSets: plannedList.reduce(0) { $0 + $1.sets },
            plannedMinutes: original?.estimatedMinutes,
            targetMinutes: targetMinutes,
            loggedTemplateId: session.templateId,
            loggedTitle: session.name,
            loggedExercises: session.exercises.map(\.name),
            completedWorkingSets: completed,
            durationMinutes: session.duration / 60,
            swaps: [],
            dropped: [],
            added: [],
            recordedAt: now
        )

        // The logged rows that came from THIS plan's exercises, keyed by the
        // planned exercise's id.
        let plannedIds = Set(plannedList.map { plannedIdPrefix + $0.id })
        let fromPlan = session.exercises.filter { plannedIds.contains($0.id) }

        if plannedKind == .lift, !plannedList.isEmpty {
            if displaced != nil || fromPlan.isEmpty {
                outcome.kind = .switched
            } else {
                let byId = Dictionary(session.exercises.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
                for gex in plannedList {
                    guard let logged = byId[plannedIdPrefix + gex.id] else {
                        outcome.dropped.append(gex.name)
                        continue
                    }
                    let didWork = logged.sets.contains { $0.done && !$0.isWarmup }
                    if !didWork {
                        outcome.dropped.append(gex.name)
                    } else if logged.name.caseInsensitiveCompare(gex.name) != .orderedSame {
                        outcome.swaps.append(ExerciseSwapPair(planned: gex.name, logged: logged.name))
                    }
                }
                outcome.added = session.exercises
                    .filter { !plannedIds.contains($0.id) }
                    .filter { $0.sets.contains { $0.done && !$0.isWarmup } }
                    .map(\.name)
                let untouched = outcome.swaps.isEmpty && outcome.dropped.isEmpty
                    && outcome.added.isEmpty
                    && completed >= outcome.plannedWorkingSets
                outcome.kind = untouched ? .asPlanned : .modified
            }
        }

        // Abandonment overrides the classification but keeps the diff, so a
        // reader can still see WHAT was cut before the stop.
        if abandoned { outcome.kind = .abandoned }
        return outcome
    }
}
