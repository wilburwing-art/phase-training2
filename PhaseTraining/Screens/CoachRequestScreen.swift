// CoachRequestScreen.swift — "Tell the coach what you want to do."
//
// Replaces the free-form CustomRoutineEditor with a structured request: the
// user picks a focus + a duration, the coach (WorkoutGenerator) builds a
// workout shaped by their existing profile + memory, and they can save it as
// a CustomRoutine for reuse. The generator is the same engine the planner
// uses — this just lets the user override its focus/duration inputs for a
// one-off ask.
//
// Two visual states driven by `phase`:
//   .input   — focus chips + duration chips + Generate button
//   .preview — generated workout listing + name field + Save / Regenerate
//
// `onSaved(custom, startNow)` lets the caller (typically OverrideTodaySheet)
// decide whether to dismiss + immediately start a session with the new
// custom workout. Persistence is the caller's responsibility too — this
// screen just builds the CustomRoutine and hands it off.

import SwiftUI

struct CoachRequestScreen: View {
    @EnvironmentObject private var memoryStore: MemoryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var tabSelection: TabSelectionStore
    /// Drives whether we route the Generate request through the LLM coach.
    /// When false, the existing deterministic chip-driven path runs and the
    /// LLM never sees the user's data. Consent flow lives in Profile.
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false
    @Environment(\.dismiss) private var dismiss

    /// Called when the user taps a save action. `startNow` reflects which
    /// button they tapped — "Save & start" vs "Save". Caller is responsible
    /// for persisting + dismissing the surface.
    let onSaved: (CustomRoutine, _ startNow: Bool) -> Void

    @State private var phase: Phase = .input
    @State private var focus: RequestFocus = .fullBody
    @State private var durationMinutes: Int = 45
    @State private var preview: GeneratedWorkout?
    @State private var name: String = ""
    @State private var lastSeed: String = ""
    /// LLM-supplied "why this workout" — surfaced above the preview list.
    @State private var coachReasoning: String? = nil
    /// True while the LLM is thinking. Disables Generate + shows a label.
    @State private var generating: Bool = false
    /// In-flight task so cancel / regenerate can interrupt the LLM mid-stream.
    @State private var llmTask: Task<Void, Never>? = nil

    /// Pre-workout substitution: the index into preview.exercises whose
    /// alternatives the user is browsing. nil = sheet closed.
    @State private var swappingPreviewIdx: Int? = nil
    /// Read-only detail view for an exercise tapped from the preview row.
    @State private var detailExercise: Exercise? = nil
    /// Build 102 — composite-tile migration. Tap on a preview row opens the
    /// shared action sheet. CoachRequest is a draft surface — most actions
    /// apply, except onDelete (mutating a draft mid-build feels wrong) and
    /// onEdit (sets/reps/rest aren't directly editable here).
    @State private var actionSheetExIdx: Int? = nil
    /// Filtered HistoryScreen, driven by the action sheet's history row.
    @State private var historyFilterExerciseName: String? = nil

    enum Phase: Equatable {
        case input
        case preview
    }

    /// Shared CoachClient instance — created once per screen lifetime.
    /// CoachClient is cheap to construct; this avoids env-object wiring for
    /// a one-shot LLM call.
    private let client = CoachClient()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch phase {
                        case .input:   inputContent
                        case .preview: previewContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 140)
                }
                VStack { Spacer(); bottomBar }
            }
            .navigationTitle(phase == .input ? "Build a workout" : "Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if phase == .preview {
                        Button("Back") { phase = .input }
                            .foregroundStyle(Color.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .sheet(item: swappingBinding) { wrapped in
            let original = preview?.exercises[wrapped.index]
            SubstituteExerciseSheet(
                originalName: original?.name ?? "",
                substitutes: original.map { CoachDatabase.shared.substitutes(forExerciseId: $0.exerciseId) } ?? [],
                onPick: { picked in
                    swapPreviewExercise(at: wrapped.index, with: picked)
                }
            )
        }
        .sheet(item: $detailExercise) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
        .sheet(item: actionSheetBinding) { wrapped in
            let exerciseName = preview?.exercises[wrapped.index].name ?? "Exercise"
            ExerciseActionSheet(
                exerciseName: exerciseName,
                onShowDetails: {
                    if let ex = preview?.exercises[wrapped.index] {
                        detailExercise = CoachDatabase.shared.exercise(id: ex.exerciseId)
                    }
                },
                onShowHistory: { historyFilterExerciseName = exerciseName },
                onShowReplace: { swappingPreviewIdx = wrapped.index }
            )
        }
        .sheet(item: filteredHistoryBinding) { wrapped in
            HistoryScreen(initialExerciseFilter: wrapped.name)
                .environmentObject(sessionStore)
        }
        .onAppear {
            // Seed duration default from the user's current session length so
            // the chip selection feels personal on first open.
            if durationMinutes == 45 {
                durationMinutes = memoryStore.memory.sessionMinutes
            }
        }
    }

    // MARK: - Input phase

    private var inputContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("FOCUS")
            WrappingFlow(spacing: 8) {
                ForEach(RequestFocus.allCases, id: \.self) { f in
                    OnboardingChip(
                        label: f.label,
                        selected: focus == f,
                        action: { focus = f }
                    )
                }
            }

            section("DURATION")
            WrappingFlow(spacing: 8) {
                ForEach([30, 45, 60, 75, 90], id: \.self) { mins in
                    OnboardingChip(
                        label: "\(mins) min",
                        selected: durationMinutes == mins,
                        action: { durationMinutes = mins }
                    )
                }
            }

            Text("The coach picks exercises that fit your equipment, injuries, and dislikes. Tap Generate to see a workout — you can re-roll if you don't like it.")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(Color.ink3)
                .padding(.top, 4)
        }
    }

    // MARK: - Preview phase

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let preview {
                if let reasoning = coachReasoning, !reasoning.isEmpty {
                    // The LLM's one-line "why this workout" — shown above
                    // the listing so the user understands the strategy.
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accent)
                            .padding(.top, 2)
                        Text(reasoning)
                            .font(.custom("Inter-Regular", size: 13))
                            .foregroundStyle(Color.ink2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentWash)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentBorder, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.title.uppercased())
                        .styled(.micro)
                        .foregroundStyle(Color.accent)
                    Text("\(preview.exercises.count) movements · ~\(preview.estimatedMinutes) min")
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(Color.ink2)
                }

                VStack(spacing: 8) {
                    ForEach(Array(preview.exercises.enumerated()), id: \.element.id) { idx, ex in
                        generatedExerciseTile(ex, position: idx + 1)
                    }
                }

                section("NAME (OPTIONAL)")
                TextField("", text: $name,
                          prompt: Text(preview.title).foregroundColor(Color.ink3))
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text("Nothing generated yet — go back and tap Generate.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    /// HANDOFF §4a: composite-tile migration. Same shape as TodayScreen —
    /// `.composite` leading + `.overflow` trailing + `.presentation` density.
    /// Tap anywhere on the row → ExerciseActionSheet. CoachRequest is a draft
    /// surface so onEdit/onDelete are omitted; details / history / replace
    /// still apply.
    private func generatedExerciseTile(_ ex: GeneratedExercise, position: Int) -> some View {
        let bucket = ExerciseLookupCache.shared.bucket(forName: ex.name) ?? .chest
        let photoURL = ExerciseLookupCache.shared.thumbnailURL(forName: ex.name)
        let exId = ex.id
        return ExerciseTile(
            vm: .init(
                leading: .composite(photoURL: photoURL, group: bucket, side: bucket.naturalSide),
                title: ex.name,
                meta: "\(ex.sets) × \(ex.reps) · rest \(ex.restSeconds)s",
                trailing: .overflow(onTap: {
                    actionSheetExIdx = preview?.exercises.firstIndex(where: { $0.id == exId })
                }),
                onTap: {
                    actionSheetExIdx = preview?.exercises.firstIndex(where: { $0.id == exId })
                }
            ),
            density: .presentation
        )
    }

    /// Action sheet binding — wraps optional `actionSheetExIdx` for `.sheet(item:)`.
    private var actionSheetBinding: Binding<PreviewRowIndex?> {
        Binding(
            get: { actionSheetExIdx.map(PreviewRowIndex.init) },
            set: { actionSheetExIdx = $0?.index }
        )
    }

    /// Filtered-history sheet binding.
    private var filteredHistoryBinding: Binding<CoachReqNamedExercise?> {
        Binding(
            get: { historyFilterExerciseName.map(CoachReqNamedExercise.init) },
            set: { historyFilterExerciseName = $0?.name }
        )
    }

    // MARK: - Bottom bar (state-dependent)

    @ViewBuilder
    private var bottomBar: some View {
        switch phase {
        case .input:
            VStack(spacing: 0) {
                Button(action: generate) {
                    HStack(spacing: 8) {
                        if generating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color.accentInk)
                        }
                        Text(generating
                             ? (consentGranted ? "Coach is thinking…" : "Generating…")
                             : (consentGranted ? "Ask coach to build" : "Generate"))
                        .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                        .foregroundStyle(Color.accentInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(generating ? Color.accent.opacity(0.6) : Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(generating)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

        case .preview:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: generate) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Regenerate")
                                .styled(.micro)
                        }
                        .foregroundStyle(Color.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button { save(startNow: false) } label: {
                        Text("Save")
                            .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(preview == nil)
                }
                Button { save(startNow: true) } label: {
                    Text("Save & start workout")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                        .foregroundStyle(Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(preview == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Generation

    /// Option-D entry point: the LLM coach decides the parameters
    /// (focus, duration, pattern emphasis, intensity, target overrides),
    /// then the deterministic generator executes deterministically.
    ///
    /// Flow:
    ///   1. If consent off OR LLM unavailable → fall back to chip-driven
    ///      .auto strategy. The deterministic path still ships a workout.
    ///   2. If consent on → stream the LLM with the build_workout tool,
    ///      accumulate the tool_use JSON, decode into a GeneratorStrategy,
    ///      then run the generator with strategy + context.
    ///
    /// Either path produces a workout. The LLM path adds the coach's
    /// reasoning line shown above the preview.
    private func generate() {
        llmTask?.cancel()
        coachReasoning = nil

        // Chip selections become a "starter" strategy the LLM can override.
        // When the LLM falls back to .auto we still get focus + duration
        // from the chips — the deterministic path stays useful offline.
        let starterFocus = focus.workoutFocus
        let starter = GeneratorStrategy(
            focus: starterFocus,
            durationMinutes: durationMinutes,
            emphasizePatterns: [],
            deprioritizePatterns: [],
            targetWeightOverrides: [:],
            rpeOverrides: [:],
            tempoOverrides: [:],
            intensityBias: .normal
        )

        // Skip the LLM entirely when consent isn't granted — pure deterministic
        // path, no token spend, no waiting.
        guard consentGranted else {
            runGenerator(with: starter, reasoning: nil)
            return
        }

        generating = true
        llmTask = Task {
            let (strategy, reasoning) = await requestStrategyFromLLM(starter: starter)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                generating = false
                runGenerator(with: strategy, reasoning: reasoning)
            }
        }
    }

    /// Stream the LLM with the build_workout tool. Accumulate the first
    /// tool_use block's input JSON, decode it into a GeneratorStrategy, and
    /// return. On any error / no tool call / cancellation → return the
    /// starter strategy unchanged. Graceful degradation: app never breaks.
    private func requestStrategyFromLLM(starter: GeneratorStrategy) async -> (GeneratorStrategy, String?) {
        let snapshot = CoachContext.snapshot(
            activeTab: tabSelection.selected,
            memory: memoryStore.memory,
            plan: planStore.plan,
            recentSessions: sessionStore.savedSessions,
            recentFeedback: memoryStore.memory.feedback,
            recentSoreness: memoryStore.memory.soreness
        )
        let userPrompt = """
        Build me a workout. The user picked focus = \(focus.label), duration = \(durationMinutes) min as a starting point — adjust based on the context if you see better signal. Call build_workout once and only once.
        """
        let stream = client.stream(
            cachedSystem: CoachSystemPrompt.cachedHeader,
            perTurnContext: CoachSystemPrompt.contextBlock(snapshot: snapshot),
            history: [],
            userMessage: userPrompt,
            tools: [CoachTools.buildWorkout]
        )
        var toolCallData: Data? = nil
        do {
            for try await part in stream {
                if Task.isCancelled { return (starter, nil) }
                switch part {
                case .toolCall(_, let name, let input):
                    if name == "build_workout", toolCallData == nil {
                        toolCallData = input
                    }
                case .textDelta:
                    continue   // pre-tool reasoning text — not surfaced
                }
            }
        } catch {
            return (starter, nil)
        }
        guard let data = toolCallData,
              let proposal = CoachToolDecoder.decodeBuildWorkout(from: data) else {
            return (starter, nil)
        }
        // Merge the LLM's strategy over the starter (LLM wins for fields it sets).
        var merged = proposal.strategy
        if merged.focus == nil { merged.focus = starter.focus }
        if merged.durationMinutes == nil { merged.durationMinutes = starter.durationMinutes }
        return (merged, proposal.reasoning)
    }

    /// Pure deterministic generation given a strategy. Same code regardless
    /// of whether the LLM populated the strategy or it came from chips.
    private func runGenerator(with strategy: GeneratorStrategy, reasoning: String?) {
        let seed = "coach-req-\(focus.rawValue)-\(durationMinutes)-\(Date().timeIntervalSince1970)"
        lastSeed = seed
        var mem = memoryStore.memory
        mem.sessionMinutes = strategy.durationMinutes ?? durationMinutes
        let profile = DemographicProfile.from(mem)
        let context = GeneratorContext.from(
            sessions: sessionStore.savedSessions,
            soreness: mem.soreness,
            feedback: mem.feedback
        )
        let workout: GeneratedWorkout
        let effectiveFocus = strategy.focus ?? focus.workoutFocus
        if effectiveFocus == .mobility {
            workout = WorkoutGenerator.generateMobility(
                memory: mem, profile: profile, hashSeed: seed,
                context: context, strategy: strategy
            )
        } else {
            // Map the focus back to a liftIndex/totalLifts pair that resolves
            // to it via WorkoutFocus.lift — generator preserves the override.
            let (liftIdx, total) = liftIndexTotalPair(for: effectiveFocus)
            workout = WorkoutGenerator.generateLift(
                liftIndex: liftIdx, totalLifts: total,
                memory: mem, profile: profile, hashSeed: seed,
                context: context, strategy: strategy
            )
        }
        coachReasoning = reasoning
        preview = workout
        phase = .preview
    }

    private func liftIndexTotalPair(for focus: WorkoutFocus) -> (Int, Int) {
        switch focus {
        case .fullBodyA, .fullBodyB: return (0, 1)
        case .push:     return (0, 3)
        case .pull:     return (1, 3)
        case .legs:     return (2, 3)
        case .upper:    return (0, 4)
        case .lower:    return (1, 4)
        case .mobility: return (0, 0)
        }
    }

    // MARK: - Pre-workout swap

    private var swappingBinding: Binding<PreviewRowIndex?> {
        Binding(
            get: { swappingPreviewIdx.map(PreviewRowIndex.init) },
            set: { swappingPreviewIdx = $0?.index }
        )
    }

    /// Apply a substitution to the in-flight preview. Replaces the exercise
    /// name + id and stamps the picked exercise's default sets/reps/rest when
    /// available, falling back to the generated values so the swap doesn't
    /// silently downgrade prescriptions.
    private func swapPreviewExercise(at idx: Int, with picked: Exercise) {
        guard var workout = preview, workout.exercises.indices.contains(idx) else { return }
        var slot = workout.exercises[idx]
        slot.exerciseId = picked.id
        slot.name = picked.name
        slot.isCompound = picked.isCompound
        if let s = picked.defaultSets { slot.sets = s }
        if let r = picked.defaultReps, !r.isEmpty { slot.reps = r }
        if let rest = picked.defaultRest, let seconds = restSeconds(from: rest) {
            slot.restSeconds = seconds
        }
        workout.exercises[idx] = slot
        preview = workout
    }

    /// Parse "90s" / "2m" / "120" strings into integer seconds.
    private func restSeconds(from text: String) -> Int? {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("s"), let n = Int(t.dropLast()) { return n }
        if t.hasSuffix("m"), let n = Int(t.dropLast()) { return n * 60 }
        return Int(t)
    }

    private func save(startNow: Bool) {
        guard let workout = preview else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let routine = CustomRoutine(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? workout.title : trimmed,
            exercises: workout.exercises.enumerated().map { idx, gex in
                CustomRoutineExercise(
                    id: UUID().uuidString,
                    exerciseId: gex.exerciseId,
                    name: gex.name,
                    position: idx + 1,
                    sets: gex.sets,
                    reps: gex.reps,
                    rest: "\(gex.restSeconds)s",
                    notes: gex.notes
                )
            },
            createdAt: Date()
        )
        onSaved(routine, startNow)
    }

    // MARK: - Helpers

    private func section(_ s: String) -> some View {
        Text(s)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }
}

/// Identifiable wrapper so `.sheet(item:)` can bind to `swappingPreviewIdx`.
private struct PreviewRowIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - RequestFocus

/// Focus options the user can request. Maps to WorkoutGenerator's
/// (liftIndex, totalLifts) inputs, except `.mobility` which has its own entry
/// on the generator.
enum RequestFocus: String, CaseIterable, Hashable {
    case fullBody, push, pull, legs, upper, lower, mobility

    var label: String {
        switch self {
        case .fullBody: return "Full body"
        case .push:     return "Push"
        case .pull:     return "Pull"
        case .legs:     return "Legs"
        case .upper:    return "Upper body"
        case .lower:    return "Lower body"
        case .mobility: return "Mobility"
        }
    }

    /// Return (liftIndex, totalLifts) such that WorkoutFocus.lift(...) yields
    /// the focus this request asks for. Mobility is handled separately.
    func liftIndexTotalPair() -> (Int, Int) {
        switch self {
        case .fullBody: return (0, 1)   // totalLifts 0/1 → fullBodyA
        case .push:     return (0, 3)   // 3-day rotation: 0=push
        case .pull:     return (1, 3)   // 1=pull
        case .legs:     return (2, 3)   // 2=legs
        case .upper:    return (0, 4)   // 4-day rotation: 0=upper
        case .lower:    return (1, 4)   // 1=lower
        case .mobility: return (0, 0)   // unused, caller branches first
        }
    }

    /// Direct mapping to WorkoutFocus. Used by the LLM strategy path which
    /// expresses focus as a WorkoutFocus value rather than the chip-derived
    /// (liftIndex, totalLifts) pair.
    var workoutFocus: WorkoutFocus {
        switch self {
        case .fullBody: return .fullBodyA
        case .push:     return .push
        case .pull:     return .pull
        case .legs:     return .legs
        case .upper:    return .upper
        case .lower:    return .lower
        case .mobility: return .mobility
        }
    }
}

// MARK: - Preview

#Preview {
    let suite = "CoachRequestScreen.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let memory = MemoryStore(defaults: defaults)
    memory.update { m in
        m.liftDaysPerWeek = 3
        m.sessionMinutes = 60
        m.equipment = [.barbell, .dumbbells, .pullUpBar]
        m.experience = .intermediate
    }
    return CoachRequestScreen(onSaved: { _, _ in })
        .environmentObject(memory)
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(TabSelectionStore())
}

/// Identifiable wrapper so `.sheet(item:)` can bind to an optional exercise
/// name — drives the filtered HistoryScreen from the action sheet.
private struct CoachReqNamedExercise: Identifiable {
    let name: String
    var id: String { name }
}
