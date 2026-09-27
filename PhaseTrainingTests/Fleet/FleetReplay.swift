// FleetReplay.swift — walk one converted athlete through the app's pure
// engines and produce its predictions file.
//
// The one rule: every prediction at a point in time uses only history
// strictly before it.
//   - likelihood (3b): each planned lift or sport day D, `now` = start of D,
//     outcomes / missed / session starts dated before D. At the start of the
//     day the time-of-day decay cannot fire (it only applies once `now` is
//     past the usual start hour). Travel comes from the `.outOfTown` events,
//     which the calendar shows ahead of time.
//   - suggestions (PatternEngine): each week start W, outcomes and abandons
//     before W, no explore sessions, affinities or decisions.
//   - twin (B1a): each saved session S, frozen as `recordOutcome` freezes it
//     (planned exercises from S's DayOutcome, history = sessions before S).
//     Only rows with an actual are written: the logged working exercises.
//   - counterfactual (2a): each week start W, `Counterfactual.evaluate` on that
//     week's plan with the load events `GeneratorContext.buildLoadEvents`
//     builds from sessions before W. Every alternative it returns.
//
// All dates go through the UTC calendar.

import Foundation
@testable import PhaseTraining

enum FleetReplay {

    static func predictions(for athlete: FleetAthlete,
                            calendar: Calendar = FleetContract.calendar) throws -> FleetPredictions {
        let history = try FleetConverter.convert(athlete, calendar: calendar)
        return run(history, calendar: calendar)
    }

    static func run(_ h: FleetHistory, calendar: Calendar = FleetContract.calendar) -> FleetPredictions {
        let patterns = PatternCache()
        return FleetPredictions(schemaVersion: h.athlete.schemaVersion,
                                athleteId: h.athlete.athleteId,
                                engineBuild: FleetContract.engineBuild,
                                likelihood: likelihood(h, calendar: calendar),
                                suggestions: suggestions(h),
                                twin: twin(h, calendar: calendar, patternFor: patterns.pattern(for:)),
                                counterfactual: counterfactual(h, calendar: calendar))
    }

    // MARK: - 3b

    static func likelihood(_ h: FleetHistory, calendar: Calendar,
                           params: SessionLikelihoodEngine.Params = .defaults) -> [FleetLikelihoodRow] {
        h.dates.compactMap { day -> FleetLikelihoodRow? in
            guard let plan = h.plannedByDate[day], plan.kind == .lift || plan.kind == .sport else { return nil }
            let history = SessionLikelihoodEngine.History(
                outcomes: h.outcomes.filter { $0.date < day },
                missed: h.missed.filter { $0.date < day },
                sessionStarts: h.sessions.map(\.startTime).filter { $0 < day })
            let travel = h.travelEvents.contains {
                $0.kind == .outOfTown && calendar.isDate($0.date, inSameDayAs: day)
            }
            guard let l = SessionLikelihoodEngine.estimate(date: day, dayKind: plan.kind, isTravel: travel,
                                                           history: history, now: day, calendar: calendar,
                                                           params: params)
            else { return nil }
            return FleetLikelihoodRow(date: FleetContract.dayString(day), p: l.probability, samples: l.samples)
        }
    }

    // MARK: - PatternEngine

    static func suggestions(_ h: FleetHistory) -> [FleetSuggestionRow] {
        h.weeks.flatMap { week -> [FleetSuggestionRow] in
            guard let start = week.days.first?.date else { return [] }
            let input = PatternEngine.Inputs(
                outcomes: h.outcomes.filter { $0.date < start },
                abandoned: h.abandoned.filter { $0.date < start },
                explore: [],
                sessionMinutes: h.athlete.declaredSessionMinutes,
                affinities: [:],
                savedRoutineNames: [],
                decisions: [])
            return PatternEngine.suggestions(input, now: start).map {
                FleetSuggestionRow(weekStart: FleetContract.dayString(start), id: $0.id, rule: $0.rule.rawValue)
            }
        }
    }

    // MARK: - Twin

    static func twin(_ h: FleetHistory, calendar: Calendar,
                     patternFor: @escaping (String) -> String) -> [FleetTwinRow] {
        var rows: [FleetTwinRow] = []
        for (i, session) in h.sessions.enumerated() {
            let before = h.sessions.filter { $0.startTime < session.startTime }
            let frozen = freezeTwin(session: session,
                                    plannedExercises: h.outcomes[i].plannedExercises,
                                    history: TwinInputs.sets(from: before),
                                    patternFor: patternFor)
            let date = FleetContract.dayString(calendar.startOfDay(for: session.startTime))
            for e in frozen.exercises {
                guard let actual = e.actual else { continue }
                rows.append(FleetTwinRow(date: date, exercise: e.exercise, predicted: e.predicted,
                                         baseline: e.baseline, actual: actual))
            }
        }
        return rows
    }

    /// `TwinInputs.predict`, line for line, with the pattern lookup passed in
    /// so the replay can memoize it (the app's version queries coach.db once
    /// per set per session). The contract test checks the two agree.
    static func freezeTwin(session: SavedSession, plannedExercises: [String], history: [LoadSet],
                           params: TwinParams = .defaults,
                           patternFor: @escaping (String) -> String) -> TwinPrediction {
        let before = history.filter { $0.date < session.startTime }
        let model = TrainingLoadModel(sets: before + TwinInputs.sets(from: [session]), params: params,
                                      patternFor: patternFor)
        let day = TrainingLoadModel.day(session.startTime)
        let names = plannedExercises.isEmpty ? session.exercises.map(\.name) : plannedExercises
        var seen = Set<String>()
        let rows = names.compactMap { name -> TwinExercisePrediction? in
            guard seen.insert(name.lowercased()).inserted,
                  let p = model.predict(exercise: name, day: day) else { return nil }
            return TwinExercisePrediction(exercise: name, predicted: p.predicted, baseline: p.baseline,
                                          actual: model.actualTop(exercise: name, day: day))
        }
        return TwinPrediction(params: params, readiness: model.readiness(exercises: names, day: day),
                              exercises: rows)
    }

    // MARK: - 2a

    static func counterfactual(_ h: FleetHistory, calendar: Calendar) -> [FleetCounterfactualRow] {
        h.weeks.flatMap { week -> [FleetCounterfactualRow] in
            guard let start = week.days.first?.date else { return [] }
            let events = GeneratorContext.buildLoadEvents(
                sessions: h.sessions.filter { $0.startTime < start },
                importedWorkouts: [],
                sportLogs: [],
                now: start,
                calendar: calendar)
            let report = Counterfactual.evaluate(plan: week, history: events, savedRoutines: [],
                                                 now: start, calendar: calendar)
            guard let sportDay = report.sportDay else { return [] }
            return report.outcomes.map { o -> FleetCounterfactualRow in
                var row = FleetCounterfactualRow(weekStart: FleetContract.dayString(start),
                                                 liftDate: FleetContract.dayString(o.day),
                                                 alternative: "",
                                                 sportDate: FleetContract.dayString(sportDay),
                                                 baseline: o.baseline,
                                                 score: o.score,
                                                 moveTo: nil, minutes: nil, routineId: nil)
                switch o.alternative {
                case .skip:
                    row.alternative = "skip"
                case .move(let to):
                    row.alternative = "move"
                    row.moveTo = FleetContract.dayString(to)
                case .shorter(let minutes):
                    row.alternative = "shorter"
                    row.minutes = minutes
                case .savedRoutine(let id, _):
                    row.alternative = "saved_routine"
                    row.routineId = id
                }
                return row
            }
        }
    }

    // MARK: - Helpers

    /// Memoized `TwinInputs.pattern(for:)`.
    final class PatternCache {
        private var cache: [String: String] = [:]
        func pattern(for name: String) -> String {
            if let hit = cache[name] { return hit }
            let p = TwinInputs.pattern(for: name)
            cache[name] = p
            return p
        }
    }
}
