// PlanStore+LLMRefinement.swift — build 98 background LLM refinement.
//
// Architecture:
//   1. PlanStore.generate(from:) stamps the deterministic plan as before
//      (instant render — UI never blocks waiting for the LLM).
//   2. If CoachConsent is granted, generate() also kicks off
//      `refineCurrentPlanWithLLM` as a background Task.
//   3. The Task fires LLM calls in parallel (TaskGroup) — one per
//      lift/mobility day in the week. Each call asks the coach to refine
//      that day's planned workout, returning a build_workout strategy
//      that overrides the deterministic defaults for sets/reps/focus
//      emphasis/target weights.
//   4. As each call completes, the refined workout replaces that day's
//      `generatedWorkout` in the plan and stamps `refinedByLLMAt`.
//   5. Per-day failures stay deterministic — no spurious empty days.
//   6. Subsequent regens cancel the in-flight refinement task so the
//      newer plan's refinement wins.
//
// This makes the LLM the visible default for coach-enabled users without
// blocking the UI on LLM latency. Coach off → behavior identical to
// pre-build-98.

import Foundation

extension PlanStore {

    // MARK: - Trigger

    /// Called from generate(from:) after the deterministic plan is stamped.
    /// Reads CoachConsent at call time so toggling consent in settings
    /// takes effect on the next regen with no app restart needed.
    func kickOffLLMRefinementIfConsented(memory: TrainingMemory) {
        // Cancel any in-flight refinement so we don't race two against
        // the same plan (last write wins on the @Published mutation,
        // but the older task wastes LLM calls).
        currentRefinementTask?.cancel()
        guard isCoachConsentGranted else { return }
        guard plan != nil else { return }
        currentRefinementTask = Task { @MainActor in
            await self.refineCurrentPlanWithLLM(memory: memory)
        }
    }

    private var isCoachConsentGranted: Bool {
        // CoachConsent stores the flag under its own UserDefaults key.
        // We read from .standard (where AppStorage writes) — the PlanStore's
        // own UserDefaults instance may be a different suite (tests/previews).
        UserDefaults.standard.bool(forKey: CoachConsent.storageKey)
    }

    // MARK: - Candidate selection

    /// Days eligible for background LLM refinement. A day qualifies only if
    /// it's a lift day with a deterministic workout that:
    ///   - hasn't already been refined for this plan version
    ///     (refinement is per-plan-version; we don't re-polish), AND
    ///   - doesn't carry a user custom-routine override.
    ///
    /// The override exclusion is load-bearing: composeWorkout(fromCustom:)
    /// stamps a nil refinedByLLMAt, so a Week-tab "Override workout" day would
    /// otherwise look like a fresh candidate and get rerolled by the LLM —
    /// silently reverting the user's pick 5-10s after they made it. An
    /// override is the user's intent; refinement must not touch it. Extracted
    /// from the refinement loop so these rules are unit-testable without a
    /// live CoachClient.
    func refinementCandidates(in plan: WeekPlan) -> [(index: Int, day: DayPlan)] {
        plan.days.enumerated().compactMap { idx, day in
            guard day.kind == .lift else { return nil }
            guard day.generatedWorkout != nil else { return nil }
            if day.generatedWorkout?.refinedByLLMAt != nil { return nil }
            if overrides.customRoutineId(for: day.date) != nil { return nil }
            return (idx, day)
        }
    }

    // MARK: - Core refinement loop

    /// Run LLM refinement for every lift/mobility day in the current plan.
    /// Parallel via TaskGroup; per-day failures stay silent and keep the
    /// deterministic baseline visible.
    @MainActor
    func refineCurrentPlanWithLLM(memory: TrainingMemory) async {
        guard let snapshotPlan = plan else { return }
        let sessions = sessionStore?.savedSessions ?? []
        // Build 99: sport logs feed the refinement snapshot too, so each
        // day's LLM polish knows when the user's been climbing hard 3×
        // this week and can demote intensity / shift accessory selection
        // accordingly. Defaulted in CoachContext.snapshot, so omitting
        // this would silently regress.
        let sportLogs = sportLogStore?.entries ?? []
        // Resolve the Phase-1 era cohort here once so we can pass it both
        // into the per-turn coach context AND through the rest of the
        // refinement pass. DemographicProfile owns the resolution logic.
        let profile = DemographicProfile.from(memory)
        let snapshot = CoachContext.snapshot(
            activeTab: .today,
            memory: memory,
            plan: snapshotPlan,
            recentSessions: sessions,
            recentFeedback: memory.feedback,
            recentSoreness: memory.soreness,
            recentSportLogs: sportLogs,
            eraCohort: profile.eraCohort
        )

        let candidates = refinementCandidates(in: snapshotPlan)
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: (Int, GeneratedWorkout?).self) { group in
            for (idx, day) in candidates {
                group.addTask { @MainActor in
                    let refined = await self.refineSingleDay(
                        day: day,
                        plan: snapshotPlan,
                        memory: memory,
                        profile: profile,
                        sessions: sessions,
                        snapshot: snapshot
                    )
                    return (idx, refined)
                }
            }
            for await (idx, refined) in group {
                guard !Task.isCancelled else { return }
                guard let refined else { continue }
                applyRefinedWorkout(toDayAt: idx, in: snapshotPlan, workout: refined)
            }
        }
    }

    // MARK: - Per-day refinement

    /// LLM-refine a single day. Returns nil on any failure (no consent
    /// downstream, no tool call, parse failure, cancellation) — caller
    /// leaves that day's deterministic version untouched.
    private func refineSingleDay(
        day: DayPlan,
        plan: WeekPlan,
        memory: TrainingMemory,
        profile: DemographicProfile,
        sessions: [SavedSession],
        snapshot: String
    ) async -> GeneratedWorkout? {
        guard let existing = day.generatedWorkout else { return nil }

        // Prompt — anchor the LLM to the planned focus so the week's
        // overall structure (push/pull/legs split, etc.) stays coherent.
        // The LLM still has freedom over exercise picks, intensity,
        // RPE/tempo, and target weights within that focus.
        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMM d"
            return f.string(from: day.date)
        }()
        let userPrompt = """
        Refine the planned workout for \(dateStr) (focus: \(existing.title)). Keep the focus consistent with the week's plan but personalize the exercise picks, intensity, and prescriptions to the user's recent sessions, soreness, and goals. Call build_workout exactly once.
        """

        let client = CoachClient()
        let stream = client.stream(
            cachedSystem: CoachSystemPrompt.cachedHeader,
            perTurnContext: CoachSystemPrompt.contextBlock(snapshot: snapshot),
            history: [],
            userMessage: userPrompt,
            tools: [CoachTools.buildWorkout]
        )

        var toolCallData: Data?
        do {
            for try await part in stream {
                if Task.isCancelled { return nil }
                if case let .toolCall(_, name, input) = part,
                   name == "build_workout",
                   toolCallData == nil {
                    toolCallData = input
                }
            }
        } catch {
            return nil
        }
        guard let data = toolCallData,
              let proposal = CoachToolDecoder.decodeBuildWorkout(from: data) else {
            return nil
        }

        // Build the strategy. We force the focus to match the existing
        // day so the LLM can't accidentally turn a push day into a pull
        // day (which would break the week's overall plan shape).
        var strategy = proposal.strategy
        strategy.focus = existingFocus(for: existing, plan: plan, day: day) ?? strategy.focus

        // Re-run the generator with the LLM strategy.
        let seed = "llm-refine-\(memory.planInputsHash)-\(Int(day.date.timeIntervalSince1970))"
        let context = GeneratorContext.from(
            sessions: sessions,
            soreness: memory.soreness,
            feedback: memory.feedback,
            now: day.date
        )

        let workout: GeneratedWorkout
        switch day.kind {
        case .lift:
            let liftDays = plan.days.filter { $0.kind == .lift }
            let cal = Calendar.current
            let liftIndex = liftDays.firstIndex(where: { cal.isDate($0.date, inSameDayAs: day.date) }) ?? 0
            workout = WorkoutGenerator.generateLift(
                liftIndex: liftIndex,
                totalLifts: liftDays.count,
                memory: memory, profile: profile, hashSeed: seed,
                context: context, strategy: strategy
            )
        default:
            return nil
        }

        // Mark refined.
        var refined = workout
        refined.refinedByLLMAt = Date()
        return refined
    }

    /// Look up the WorkoutFocus that drove the original deterministic
    /// generation for this day. Used to anchor the LLM's strategy so it
    /// can't shift the week's structure.
    private func existingFocus(for workout: GeneratedWorkout, plan: WeekPlan, day: DayPlan) -> WorkoutFocus? {
        switch day.kind {
        case .lift:
            let liftDays = plan.days.filter { $0.kind == .lift }
            let cal = Calendar.current
            guard let liftIndex = liftDays.firstIndex(where: { cal.isDate($0.date, inSameDayAs: day.date) }) else {
                return nil
            }
            return WorkoutFocus.lift(liftIndex: liftIndex, totalLifts: liftDays.count)
        default: return nil
        }
    }

    // MARK: - Apply

    /// Replace the day's workout in the live plan. Verifies the plan
    /// hasn't been swapped out underneath us (a newer regen ran while
    /// the LLM was thinking) — if so, drop the result instead of
    /// stamping over the new plan.
    private func applyRefinedWorkout(toDayAt idx: Int, in originalPlan: WeekPlan, workout: GeneratedWorkout) {
        guard var current = self.plan,
              current.inputsHash == originalPlan.inputsHash,
              current.days.indices.contains(idx)
        else { return }
        current.days[idx].generatedWorkout = workout
        current.days[idx].title = workout.title
        current.days[idx].generatedReason = workout.provenance
        self.plan = current
        savePlan()
    }
}
