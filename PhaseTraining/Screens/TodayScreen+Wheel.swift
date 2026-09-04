//
//  TodayScreen+Wheel.swift
//  PhaseTraining
//
//  The option list behind Today's title wheel, and the commit that switches
//  today's workout.
//
//  The commit does NOT mutate the plan directly. `overrides.customRoutineByDate`
//  is the existing seam for "use this saved workout on this day", and
//  PlanStore's generate() post-processes it into the day's generatedWorkout on
//  every regeneration — which is what makes the choice survive a replan.
//  Direct mutation (the regenerateToday pattern) would be overwritten by the
//  next generate. Same seam OverrideTodaySheet and the Week day editor use.
//

import SwiftUI

extension TodayScreen {

    /// Cap. The wheel is a shortcut to the few workouts you would plausibly
    /// swap to, not a library — Today was just stripped of things that ask you
    /// to browse. "See all" opens OverrideTodaySheet for the rest.
    static var wheelCap: Int { 5 }

    /// Planned session first, then saved workouts, most recent first.
    var wheelOptions: [WorkoutWheelOption] {
        var out: [WorkoutWheelOption] = [
            WorkoutWheelOption(
                id: WorkoutWheelOption.plannedId,
                title: plannedTitle,
                subtitle: nil,
                routineId: nil
            )
        ]
        let saved = customStore.routines
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.wheelCap - 1)
        for routine in saved {
            out.append(
                WorkoutWheelOption(
                    id: routine.id,
                    title: routine.name.isEmpty ? "Saved workout" : routine.name,
                    subtitle: nil,
                    routineId: routine.id
                )
            )
        }
        // Samples fill whatever the saved workouts leave. A new user has no
        // saved workouts, so their wheel is the plan plus one sample per
        // season for their sport: off-season, pre-season, in-season, event
        // prep, maintenance. Swiping through them is the fastest tour of what
        // the app's training actually looks like. The current season is
        // skipped because the planned stop already shows it.
        if out.count < Self.wheelCap, let sport = memoryStore.memory.primarySport {
            let current = memoryStore.memory.seasonsBySport[sport] ?? memoryStore.memory.defaultSeason
            for season in SeasonPhase.allCases where season != current && out.count < Self.wheelCap {
                out.append(
                    WorkoutWheelOption(
                        id: WorkoutWheelOption.sampleId(season),
                        title: "\(season.label) sample",
                        subtitle: sport.name,
                        routineId: nil,
                        sampleSeason: season
                    )
                )
            }
        }
        return out
    }

    /// A sample session: today's generator run against a copy of the user's
    /// profile with only the season changed. Deterministic per (sport, season),
    /// so swiping away and back shows the same workout. Injury and equipment
    /// filters apply exactly as they would to a real plan.
    func sampleWorkout(for season: SeasonPhase) -> GeneratedWorkout? {
        var mem = memoryStore.memory
        guard let sport = mem.primarySport else { return nil }
        mem.seasonsBySport[sport] = season
        mem.defaultSeason = season
        let profile = DemographicProfile.from(mem)
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: max(1, mem.liftDaysPerWeek),
            memory: mem, profile: profile,
            hashSeed: "sample-\(sport.slug)-\(season.rawValue)")
        return workout.exercises.isEmpty ? nil : workout
    }

    /// The generator's own title for today, independent of any override, so
    /// the first stop always reads as "what the plan says" even while an
    /// override is active.
    var plannedTitle: String {
        guard let day = todayPlan else { return heroTitle }
        if planStore.overrides.customRoutineId(for: day.date) != nil {
            // An override is in force, so `day.title` is the saved workout's.
            // The displaced stash holds the planner's own title, so the first
            // stop keeps reading as the real session rather than a placeholder.
            let key = Calendar.current.startOfDay(for: day.date)
            if let displaced = planStore.overrides.displacedPlanByDate?[key] {
                return displaced.title
            }
            return day.kind == .rest ? "Rest" : "Today's plan"
        }
        return heroTitle
    }

    /// Which stop is showing.
    var wheelSelection: String {
        guard let day = todayPlan,
              let id = planStore.overrides.customRoutineId(for: day.date) else {
            return WorkoutWheelOption.plannedId
        }
        return id
    }

    /// Write the choice through the override seam. Selecting the planned stop
    /// clears the override rather than writing a competing one.
    func commitWheel(_ option: WorkoutWheelOption) {
        guard let day = todayPlan else { return }
        if let season = option.sampleSeason {
            guard let workout = sampleWorkout(for: season) else { return }
            planStore.switchWorkout(on: day.date, toSampleId: option.id, workout: workout,
                                    title: option.title)
            return
        }
        // NOT updateOverrides: that regenerates the whole week and kicks off
        // LLM refinement, which is the wrong cost for a control you scroll.
        // switchWorkout writes the same persisted override and applies it to
        // this one day, restoring the displaced planned session on the way
        // back rather than re-deriving a different one.
        planStore.switchWorkout(on: day.date, to: option.routineId)
    }
}
