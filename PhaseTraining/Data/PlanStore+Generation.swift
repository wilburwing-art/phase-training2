// PlanStore+Generation.swift
//
// Extracted from PlanStore.swift (Tier-3 god-object split). Plan generation: weekly generate, custom-routine composition, generator-context build.
// Lifecycle (init/reload), generation-context plumbing, PlanEdit/regeneration,
// and persistence stay in PlanStore.swift.

import Foundation

extension PlanStore {
    func generate(from memory: TrainingMemory, today: Date = Date()) -> WeekPlan {
        let routines = CoachDatabase.shared.listRoutines()
        let context = buildGeneratorContext(memory: memory, today: today)
        let p = Planner.generate(
            memory: memory,
            overrides: overrides,
            routines: routines,
            // Build 99: auto-regen paths used to drop feedback bias on the
            // floor — only WeeklyCheckInFlow passed it. So "marked 3
            // workouts too hard, planner kept handing me the same volume"
            // was a real complaint. Surfacing it here means every regen
            // (profile drift, overrides change, sport-log change) honors
            // the same ±1 lift-day nudge that the check-in flow already
            // honored.
            previousFeedback: memory.feedback,
            recentSportLogs: sportLogStore?.entries ?? [],
            recentlyPicked: recentPicks?.recentlyPickedIds() ?? [],
            today: today,
            context: context
        )
        // Build 105: apply CustomRoutine overrides AFTER Planner.generate()
        // so the user's "use my saved leg workout for Thursday" pick
        // survives plan regens. Done as post-processing because the
        // Planner is stateless and doesn't know about CustomRoutineStore.
        let pWithCustoms = applyCustomRoutineOverrides(to: p, memory: memory, context: context)
        self.plan = pWithCustoms
        savePlan()
        recordPickedExercises(in: pWithCustoms)
        // PR 4: snapshot every generated plan into history (idempotent by
        // weekStart — a same-week regen replaces the prior entry).
        snapshotCurrentPlan(now: today)
        // Build 98: kick off background LLM refinement for consent-on
        // users. Deterministic plan above renders immediately; the
        // refinement task progressively replaces each lift/mobility day
        // with an LLM-personalized version. No-op without consent.
        kickOffLLMRefinementIfConsented(memory: memory)
        return pWithCustoms
    }

    /// Walk the plan and replace any day's generatedWorkout with one
    /// composed from a CustomRoutine when `overrides.customRoutineByDate`
    /// has an entry for that date. No-op if customStore isn't wired or
    /// the referenced routine has been deleted.
    private func applyCustomRoutineOverrides(to plan: WeekPlan,
                                             memory: TrainingMemory,
                                             context: GeneratorContext) -> WeekPlan {
        guard let customStore else { return plan }
        guard !overrides.customRoutineByDate.isEmpty else { return plan }
        var updated = plan
        for idx in updated.days.indices {
            let day = updated.days[idx]
            guard let customId = overrides.customRoutineId(for: day.date) else { continue }
            guard let custom = customStore.routines.first(where: { $0.id == customId }) else { continue }
            // Build a workout shape from the custom routine. Mark it as
            // lift kind if it isn't already (rest days could also carry an
            // override if the user manually scheduled a custom workout on
            // a planned rest day from the Week tab).
            updated.days[idx].generatedWorkout = composeWorkout(fromCustom: custom)
            updated.days[idx].title = custom.name.isEmpty ? "Custom workout" : custom.name
            updated.days[idx].routineId = nil
            if day.kind == .rest || day.kind == .sport || day.kind == .event {
                updated.days[idx].kind = .lift
            }
            updated.days[idx].generatedReason = "Your saved workout"
        }
        // Prescription refresh (shape B of the saved-workout load options):
        // a SECOND pass, after every kind flip above, so the focus
        // derivation sees the final lift-day layout. Re-derived from the
        // persisted intent on every generate() — that's what makes the
        // refresh survive plan regeneration. refinedByLLMAt stays nil and
        // the customRoutineId exclusion in refinementCandidates is keyed on
        // the override dict, so LLM-refinement protection is untouched.
        if overrides.prescriptionRefreshByDate?.isEmpty == false {
            let profile = DemographicProfile.from(memory)
            let cal = Calendar.current
            let liftDays = updated.days.filter { $0.kind == .lift }
            for idx in updated.days.indices {
                let day = updated.days[idx]
                guard overrides.customRoutineId(for: day.date) != nil,
                      let mode = overrides.prescriptionRefreshMode(for: day.date),
                      let workout = day.generatedWorkout else { continue }
                // Focus: the user's focus chip if they set one, else the
                // day's position in the week's lift rotation (the same
                // derivation LLM refinement anchors on), else full body.
                let focus: WorkoutFocus
                if let chip = overrides.override(on: day.date)?.liftFocus {
                    focus = chip.asWorkoutFocus
                } else if let liftIndex = liftDays.firstIndex(where: { cal.isDate($0.date, inSameDayAs: day.date) }) {
                    focus = WorkoutFocus.lift(liftIndex: liftIndex, totalLifts: liftDays.count)
                } else {
                    focus = .fullBodyA
                }
                updated.days[idx].generatedWorkout = WorkoutGenerator.represcribe(
                    workout: workout, mode: mode, focus: focus,
                    memory: memory, profile: profile, context: context)
            }
        }
        return updated
    }

    /// Convert a CustomRoutine's exercise list into a GeneratedWorkout so
    /// the Today / Week surfaces can render it the same way they render
    /// planner output. Uses sensible fallback prescriptions when the
    /// routine doesn't carry them (older saves predate the per-exercise
    /// sets/reps/rest fields).
    private func composeWorkout(fromCustom custom: CustomRoutine) -> GeneratedWorkout {
        let exercises = custom.exercises.enumerated().map { idx, ex in
            GeneratedExercise(
                id: "custom-\(custom.id)-\(idx)",
                exerciseId: ex.exerciseId,
                name: ex.name,
                pattern: nil,
                isCompound: false,
                sets: ex.sets ?? 3,
                reps: ex.reps ?? "8-12",
                restSeconds: parseRest(ex.rest) ?? 90,
                notes: ex.notes,
                rpe: nil,
                tempo: nil,
                source: .recipe
            )
        }
        let movements = exercises.count == 1 ? "1 movement" : "\(exercises.count) movements"
        let estMin = max(15, exercises.reduce(0) { $0 + $1.sets * 90 } / 60)
        return GeneratedWorkout(
            title: custom.name.isEmpty ? "Custom workout" : custom.name,
            summary: "\(movements) · ~\(estMin) min",
            exercises: exercises,
            estimatedMinutes: estMin,
            provenance: "From your saved workouts",
            refinedByLLMAt: nil
        )
    }

    /// Parse a free-form rest string ("90s", "1 min", "2:00") to seconds.
    private func parseRest(_ s: String?) -> Int? {
        guard let s else { return nil }
        let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.contains(":") {
            let parts = lower.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        let digits = lower.prefix(while: { $0.isNumber || $0 == "." })
        guard let n = Double(digits) else { return nil }
        if lower.contains("min") { return Int(n * 60) }
        return Int(n)
    }

    /// Derive the runtime-history context for the planner. Returns `.empty`
    /// when sessionStore isn't wired (tests / previews) — same shape as
    /// pre-build-66 so the planner output stays unchanged in those paths.
    ///
    /// Phase 2: also unions HealthKit-imported workouts (read via
    /// `UserDatabase.shared.recentImportedWorkouts`) and resolves the
    /// user's era cohort for readiness-norm computation. When no HK auth
    /// has been granted, the imported list is empty and the readiness
    /// signal still works off native sessions + sport logs alone.
    func buildGeneratorContext(memory: TrainingMemory, today: Date,
                               includeParkedSignals: Bool = false) -> GeneratorContext {
        guard let sessionStore else { return .empty }
        let profile = DemographicProfile.from(memory)
        let imported = UserDatabase.shared.recentImportedWorkouts(within: 28)
        // Phase 3: lifetime peaks from CSV imports warm-start priorBest
        // for exercises the user has imported but never logged natively.
        let peaks = UserDatabase.shared.importedSetsLifetimePeaks()
        return GeneratorContext.from(
            sessions: sessionStore.savedSessions,
            soreness: memory.soreness,
            feedback: memory.feedback,
            sportLogs: sportLogStore?.entries ?? [],
            importedWorkouts: imported,
            importedPeaks: peaks,
            cohort: profile.eraCohort,
            exerciseAffinities: memory.exerciseAffinities,
            now: today,
            includeParkedSignals: includeParkedSignals
        )
    }

    /// Public seam: build the same GeneratorContext the auto-regen path uses,
    /// for flows that generate a CANDIDATE plan against local overrides and
    /// call `Planner.generate` directly (WeeklyCheckInFlow). Without it the
    /// check-in regen ran with `context: .empty`, silently skipping the
    /// Phase-2 readiness lift-day floor that every other regen path honors.
    /// - Parameter includeParkedSignals: forwarded to `GeneratorContext.from`.
    ///   Production leaves it off (T2-11 — nothing reads those fields and they
    ///   are the expensive half of the build); tests that assert on them opt in.
    func makeGeneratorContext(memory: TrainingMemory, today: Date = Date(),
                              includeParkedSignals: Bool = false) -> GeneratorContext {
        buildGeneratorContext(memory: memory, today: today,
                              includeParkedSignals: includeParkedSignals)
    }

    /// Stamp every exercise the generator just picked into the variety
    /// memory so the next regen avoids them.
    private func recordPickedExercises(in plan: WeekPlan) {
        guard let recentPicks else { return }
        let ids = plan.days
            .compactMap(\.generatedWorkout)
            .flatMap(\.exercises)
            .map(\.exerciseId)
        recentPicks.record(exerciseIds: ids)
    }

    /// Replace the current plan wholesale (used when the user accepts a
    /// preview during onboarding).
    func setPlan(_ p: WeekPlan) {
        self.plan = p
        savePlan()
        // PR 4: snapshot the plan we just installed. Idempotent — repeated
        // setPlan calls for the same week replace rather than append.
        snapshotCurrentPlan()
    }

    /// Build a `GeneratedWorkout` for a single day from its kind, anchored in
    /// the surrounding `plan` (lift index needs the other lift days to pick
    /// push/pull/legs rotation). Returns nil for non-workout kinds.
    func composeWorkout(for day: DayPlan,
                                in plan: WeekPlan,
                                memory: TrainingMemory) -> GeneratedWorkout? {
        let profile = DemographicProfile.from(memory)
        let salt = String(Int(Date().timeIntervalSince1970))
        let seed = "\(memory.planInputsHash)-regen-\(salt)"
        let recentIds = recentPicks?.recentlyPickedIds() ?? []
        let context = buildGeneratorContext(memory: memory, today: day.date)
        let cal = Calendar.current
        switch day.kind {
        case .lift:
            let liftDays = plan.days.filter { $0.kind == .lift }
            let liftIndex = liftDays.firstIndex(where: { cal.isDate($0.date, inSameDayAs: day.date) }) ?? 0
            return WorkoutGenerator.generateLift(
                liftIndex: liftIndex,
                totalLifts: liftDays.count,
                memory: memory,
                profile: profile,
                hashSeed: seed,
                recentlyPicked: recentIds,
                context: context
            )
        case .rest, .sport, .event:
            return nil
        }
    }
}
