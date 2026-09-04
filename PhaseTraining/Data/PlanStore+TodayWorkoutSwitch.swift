//
//  PlanStore+TodayWorkoutSwitch.swift
//  PhaseTraining
//
//  Switching which workout a single day runs, without regenerating the week.
//
//  Why not updateOverrides: it calls generate(from:), which rebuilds every day
//  in the plan AND calls kickOffLLMRefinementIfConsented. That is the right
//  cost for the Week editor's one deliberate edit; it is the wrong cost for
//  Today's title wheel, where a user scrolling through stops would reroll the
//  week and fire a refinement per landing.
//
//  So this writes the SAME persisted seam (overrides.customRoutineByDate, so
//  the choice still survives a later regeneration) and then applies the change
//  to the one day directly, per the regenerateToday mutation pattern.
//
//  Restoring is why DisplacedPlan exists. Clearing the override and
//  re-deriving the day gives a DIFFERENT workout, which from the outside looks
//  like the app rerolled your session because you scrolled back.
//

import Foundation

extension PlanStore {

    /// Point `date` at a saved routine, or back at the planner's own session
    /// when `routineId` is nil. Returns false when there is no plan or the
    /// date is not in it.
    /// Put a SAMPLE session on a day (Today's wheel, for a user with few or no
    /// saved workouts). Same stash-and-override shape as the saved-workout
    /// switch: the planner's day is displaced once, the id is written through
    /// `customRoutineByDate` so `wheelSelection` and the restore path see it,
    /// and selecting the planned stop clears it via `switchWorkout(on:to: nil)`.
    ///
    /// `applyCustomRoutineOverrides` skips ids it cannot find in the saved
    /// routines, so a regeneration simply drops the sample and the day reverts
    /// to the planner's session, which is the right outcome for a demo.
    @discardableResult
    func switchWorkout(on date: Date, toSampleId sampleId: String,
                       workout: GeneratedWorkout, title: String) -> Bool {
        guard var plan else { return false }
        let cal = Calendar.current
        guard let idx = plan.days.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) })
        else { return false }
        let key = cal.startOfDay(for: date)
        var stash = overrides.displacedPlanByDate ?? [:]
        if stash[key] == nil {
            let day = plan.days[idx]
            stash[key] = DisplacedPlan(kind: day.kind, title: day.title,
                                       workout: day.generatedWorkout,
                                       reason: day.generatedReason,
                                       routineId: day.routineId)
            overrides.displacedPlanByDate = stash
        }
        overrides.customRoutineByDate[key] = sampleId
        plan.days[idx].generatedWorkout = workout
        plan.days[idx].title = title
        plan.days[idx].routineId = nil
        plan.days[idx].generatedReason = "A sample of this season's training"
        if plan.days[idx].kind != .lift { plan.days[idx].kind = .lift }
        self.plan = plan
        savePlan()
        saveOverrides()
        return true
    }

    @discardableResult
    func switchWorkout(on date: Date, to routineId: String?) -> Bool {
        guard var plan else { return false }
        let cal = Calendar.current
        guard let idx = plan.days.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) })
        else { return false }
        let key = cal.startOfDay(for: date)

        if let routineId {
            guard let custom = customStore?.routines.first(where: { $0.id == routineId })
            else { return false }
            // Stash the planner's day the FIRST time it is displaced. Switching
            // between two saved workouts must not overwrite the stash with
            // another saved workout, or the planned stop is lost.
            var stash = overrides.displacedPlanByDate ?? [:]
            if stash[key] == nil {
                let day = plan.days[idx]
                stash[key] = DisplacedPlan(kind: day.kind,
                                           title: day.title,
                                           workout: day.generatedWorkout,
                                           reason: day.generatedReason,
                                           routineId: day.routineId)
                overrides.displacedPlanByDate = stash
            }
            overrides.customRoutineByDate[key] = routineId
            plan.days[idx].generatedWorkout = composeWorkout(fromCustom: custom)
            plan.days[idx].title = custom.name.isEmpty ? "Custom workout" : custom.name
            plan.days[idx].routineId = nil
            plan.days[idx].generatedReason = "Your saved workout"
            if plan.days[idx].kind != .lift { plan.days[idx].kind = .lift }
        } else {
            overrides.customRoutineByDate.removeValue(forKey: key)
            overrides.prescriptionRefreshByDate?.removeValue(forKey: key)
            if let displaced = overrides.displacedPlanByDate?[key] {
                plan.days[idx].kind = displaced.kind
                plan.days[idx].title = displaced.title
                plan.days[idx].generatedWorkout = displaced.workout
                plan.days[idx].generatedReason = displaced.reason
                plan.days[idx].routineId = displaced.routineId
                overrides.displacedPlanByDate?.removeValue(forKey: key)
            }
            // No stash means nothing was displaced through this path, so the
            // day is already the planner's. Leave it alone rather than
            // re-deriving it.
        }

        self.plan = plan
        savePlan()
        saveOverrides()
        return true
    }
}
