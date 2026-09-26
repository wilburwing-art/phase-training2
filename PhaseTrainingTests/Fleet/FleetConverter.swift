// FleetConverter.swift — a contract athlete in the app's own types.
//
// For every simulated day this builds what the app would have stored:
//   - a DayPlan per planned day, grouped into Monday-start WeekPlans (rest
//     days fill the gaps). Lift days carry a GeneratedWorkout whose exercise
//     ids are the contract's planned ids, and each logged exercise that came
//     from the plan gets id `DayOutcome.plannedIdPrefix + planned id`, which
//     is the id `GeneratedWorkout.toWorkoutTemplate` gives it in the app. That
//     is what lets `DayOutcome.derive` find drops and swaps.
//   - a SavedSession per session (sport sessions too, with no exercises, so
//     3b sees the planned sport day as happened);
//   - a DayOutcome per session through `DayOutcome.derive` (twin left nil;
//     the replay freezes it, since it needs the history before the session);
//   - a MissedWorkoutEntry per planned lift or sport day with no session;
//   - an AbandonedWorkoutEntry per abandoned session (reason `.other`: the
//     contract carries no reason, and `.timeOut` would feed PatternEngine's
//     time-out rule with a reason nobody gave);
//   - an `.outOfTown` WeekEvent per travel day.
//
// Pure apart from UUIDs, which are derived from the day index so two
// conversions of the same athlete are equal.

import Foundation
@testable import PhaseTraining

struct FleetHistory {
    var athlete: FleetAthlete
    /// Start of each simulated day, ascending, parallel to `days`.
    var dates: [Date]
    var days: [FleetDay]
    /// Planned days only, keyed by start of day.
    var plannedByDate: [Date: DayPlan]
    /// Monday-start weeks covering every simulated day, ascending.
    var weeks: [WeekPlan]
    /// Ascending by start time.
    var sessions: [SavedSession]
    /// Parallel to `sessions`.
    var outcomes: [DayOutcome]
    var missed: [MissedWorkoutEntry]
    var abandoned: [AbandonedWorkoutEntry]
    var travelEvents: [WeekEvent]
}

enum FleetConverter {

    static func convert(_ athlete: FleetAthlete,
                        calendar: Calendar = FleetContract.calendar) throws -> FleetHistory {
        let parsed = try athlete.days.map { (date: try FleetContract.day($0.date), day: $0) }
            .sorted { $0.date < $1.date }

        var plannedByDate: [Date: DayPlan] = [:]
        var sessions: [SavedSession] = []
        var outcomes: [DayOutcome] = []
        var missed: [MissedWorkoutEntry] = []
        var abandoned: [AbandonedWorkoutEntry] = []
        var travel: [WeekEvent] = []

        for (index, entry) in parsed.enumerated() {
            let date = entry.date
            let day = entry.day
            var plan: DayPlan?
            if let planned = day.planned {
                let built = try dayPlan(planned, date: date, index: index,
                                        declaredMinutes: athlete.declaredSessionMinutes)
                plannedByDate[date] = built
                plan = built
            }

            if day.travel {
                travel.append(WeekEvent(id: uuid(kind: 3, index: index), date: date, title: "Travel",
                                        kind: .outOfTown, sport: nil))
            }

            if let s = day.session {
                let session = try savedSession(s, date: date, plan: plan)
                sessions.append(session)
                outcomes.append(DayOutcome.derive(session: session,
                                                  plannedDay: plan,
                                                  displaced: nil,
                                                  abandoned: s.abandoned,
                                                  targetMinutes: athlete.declaredSessionMinutes,
                                                  now: session.endTime,
                                                  calendar: calendar))
                if s.abandoned {
                    let all = session.exercises.flatMap(\.sets)
                    let done = all.filter(\.done).count
                    abandoned.append(AbandonedWorkoutEntry(
                        date: date, plannedTitle: session.name, reason: .other,
                        completionRatio: all.isEmpty ? 0 : Double(done) / Double(all.count),
                        loggedAt: session.endTime))
                }
            } else if let plan, plan.kind == .lift || plan.kind == .sport {
                var miss = MissedWorkoutEntry(date: date, plannedKind: plan.kind, plannedTitle: plan.title,
                                              resolution: .dropped,
                                              loggedAt: calendar.date(byAdding: .day, value: 1, to: date) ?? date)
                miss.id = uuid(kind: 4, index: index)
                missed.append(miss)
            }
        }

        // Sessions come out in day order already; sort by start time in case
        // a simulator ever writes two on one day out of order.
        let order = sessions.indices.sorted { sessions[$0].startTime < sessions[$1].startTime }

        return FleetHistory(athlete: athlete,
                            dates: parsed.map(\.date),
                            days: parsed.map(\.day),
                            plannedByDate: plannedByDate,
                            weeks: weeks(dates: parsed.map(\.date), planned: plannedByDate, calendar: calendar),
                            sessions: order.map { sessions[$0] },
                            outcomes: order.map { outcomes[$0] },
                            missed: missed,
                            abandoned: abandoned,
                            travelEvents: travel)
    }

    // MARK: - Pieces

    static func dayKind(_ raw: String) throws -> DayKind {
        switch raw {
        case "lift": return .lift
        case "sport": return .sport
        case "rest": return .rest
        default: throw FleetContract.ContractError.unknownPlannedKind(raw)
        }
    }

    static func dayPlan(_ planned: FleetPlanned, date: Date, index: Int,
                        declaredMinutes: Int) throws -> DayPlan {
        let kind = try dayKind(planned.kind)
        let title = planned.title ?? kind.label.capitalized
        var workout: GeneratedWorkout?
        if kind == .lift {
            let exercises = planned.exercises.map { e in
                GeneratedExercise(id: e.id, exerciseId: 0, name: e.name, pattern: nil,
                                  isCompound: false, sets: e.sets, reps: String(e.reps),
                                  restSeconds: 90)
            }
            workout = GeneratedWorkout(title: title,
                                       summary: "\(exercises.count) movements",
                                       exercises: exercises,
                                       estimatedMinutes: planned.minutes ?? declaredMinutes,
                                       provenance: "fleet")
        }
        return DayPlan(id: uuid(kind: 1, index: index), date: date, kind: kind, title: title,
                       routineId: nil, generatedWorkout: workout, sport: nil,
                       durationMinutes: planned.minutes, generatedReason: "fleet")
    }

    static func savedSession(_ s: FleetSession, date: Date, plan: DayPlan?) throws -> SavedSession {
        let start = try FleetContract.timestamp(s.start)
        let seconds = Int((s.durationMinutes * 60).rounded())
        let dayKey = FleetContract.dayString(date)
        let exercises = s.exercises.enumerated().map { i, ex -> LoggedExercise in
            let sets = ex.sets.enumerated().map { n, set in
                LoggedSet(num: n + 1, weight: weightString(set.weight), reps: String(set.reps),
                          rpe: "", done: set.done, isWarmup: set.warmup)
            }
            let id = ex.plannedId.map { DayOutcome.plannedIdPrefix + $0 } ?? "fleet-added-\(dayKey)-\(i)"
            return LoggedExercise(id: id, name: ex.name, type: nil, unit: "lbs",
                                  targetSets: ex.sets.count, targetReps: ex.sets.first?.reps ?? 0,
                                  rest: 90, sets: sets, prevSets: [],
                                  rpe: nil, tempo: nil, supersetGroup: nil)
        }
        return SavedSession(templateId: "fleet-\(dayKey)",
                            name: plan?.title ?? "Unplanned session",
                            category: plan?.kind == .sport ? "Sport" : "Generated",
                            startTime: start,
                            exercises: exercises,
                            feel: nil,
                            note: nil,
                            endTime: start.addingTimeInterval(TimeInterval(seconds)),
                            duration: seconds)
    }

    /// Pounds as the logger would hold them: "225", "227.5".
    static func weightString(_ w: Double) -> String {
        if w == w.rounded(), abs(w) < 1e9 { return String(Int(w)) }
        return String(w)
    }

    /// Monday-start weeks spanning `dates`; a day with no plan is rest.
    static func weeks(dates: [Date], planned: [Date: DayPlan], calendar: Calendar) -> [WeekPlan] {
        guard let first = dates.first, let last = dates.last,
              var weekStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start else { return [] }
        var out: [WeekPlan] = []
        var restIndex = 0
        while weekStart <= last {
            let days = (0..<7).map { offset -> DayPlan in
                let d = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                if let p = planned[d] { return p }
                restIndex += 1
                return DayPlan(id: uuid(kind: 2, index: restIndex), date: d, kind: .rest, title: "Rest",
                               routineId: nil, generatedWorkout: nil, sport: nil,
                               durationMinutes: nil, generatedReason: "fleet: unplanned")
            }
            out.append(WeekPlan(days: days, generatedAt: weekStart, inputsHash: "fleet"))
            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        return out
    }

    /// Deterministic UUID from a small kind tag and an index.
    static func uuid(kind: Int, index: Int) -> UUID {
        let s = String(format: "%08ld-0000-4000-8000-%012ld", kind, index)
        return UUID(uuidString: s) ?? UUID()
    }
}
