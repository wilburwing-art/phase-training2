// FormModel.swift — fitness-fatigue "form" for 2a (PLAN-next-gen.md, 1b split).
//
// PURE. A Banister / performance-management model over daily training load:
//
//   load[d]    = hours trained on day d (0 on a day with nothing)
//   fitness'   = fitness + (load - fitness) * (1 - exp(-1 / 42))
//   fatigue'   = fatigue + (load - fatigue) * (1 - exp(-1 / 7))
//   form(day)  = 1 / (1 + exp(-3 * (fitness - fatigue) / (fitness + 0.1)))
//
// read at the START of the day, before anything logged that day. Fatigue
// decays six times faster than fitness, so dropping a session in the last few
// days before a target day RAISES form there, and dropping an old one lowers
// it. That is the property `ReadinessSignal` cannot express.
//
// Two numbers, two jobs (Wilbur, 2026-09-26). `ReadinessSignal` stays the
// "how trained are you" axis that sizes sets and caps RPE in the generator;
// nothing here feeds the generator. Form is what 2a's "skip Tue and Saturday
// goes from X to Y" reads. Same constants as eval-rig's fleet truth
// (src/fleet/readiness.ts), which are the textbook 42/7 defaults; the fleet
// therefore checks this implementation, not whether 42/7 fits real lifters.
// That is the in-app review's job.

import Foundation

enum FormModel {

    static let fitnessDays = 42.0
    static let fatigueDays = 7.0
    static let gain = 3.0
    /// Starting fitness and fatigue, in hours a day: about four hours a week,
    /// so a window opens near neutral form rather than at zero fitness.
    static let initialLoad = 0.5
    /// History read before the target day. Long enough that the 42-day
    /// fitness term has mostly forgotten `initialLoad`.
    static let windowDays = 120

    private static let fitnessK = 1 - exp(-1 / fitnessDays)
    private static let fatigueK = 1 - exp(-1 / fatigueDays)

    static func form(fitness: Double, fatigue: Double) -> Double {
        1 / (1 + exp(-gain * (fitness - fatigue) / (fitness + 0.1)))
    }

    /// Form at the start of `date`'s day from events before that day. Events
    /// on or after the day are ignored; several events on one day add up.
    /// Nil when no event falls inside the window.
    static func form(events: [ReadinessEvent], at date: Date,
                     calendar: Calendar = .current) -> Double? {
        let target = calendar.startOfDay(for: date)
        guard let first = calendar.date(byAdding: .day, value: -windowDays, to: target) else { return nil }

        var hoursByDay: [Date: Double] = [:]
        for e in events {
            let day = calendar.startOfDay(for: e.startTime)
            guard day >= first, day < target else { continue }
            hoursByDay[day, default: 0] += e.duration / 3600
        }
        guard !hoursByDay.isEmpty else { return nil }

        var fitness = initialLoad
        var fatigue = initialLoad
        var day = first
        while day < target {
            let load = hoursByDay[day] ?? 0
            fitness += (load - fitness) * fitnessK
            fatigue += (load - fatigue) * fatigueK
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return form(fitness: fitness, fatigue: fatigue)
    }
}
