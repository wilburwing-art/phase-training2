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

    /// Pre-workout substitution: the index into preview.exercises whose
    /// alternatives the user is browsing. nil = sheet closed.
    @State private var swappingPreviewIdx: Int? = nil
    /// Read-only detail view for an exercise tapped from the preview row.
    @State private var detailExercise: Exercise? = nil

    enum Phase: Equatable {
        case input
        case preview
    }

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
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.title.uppercased())
                        .styled(.micro)
                        .foregroundStyle(Color.accent)
                    Text("\(preview.exercises.count) movements · ~\(preview.estimatedMinutes) min")
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(Color.ink2)
                }

                VStack(spacing: 0) {
                    ForEach(Array(preview.exercises.enumerated()), id: \.element.id) { idx, ex in
                        exerciseRow(ex, position: idx + 1)
                        if idx < preview.exercises.count - 1 {
                            Rectangle()
                                .fill(Color.lineSoft)
                                .frame(height: 0.5)
                        }
                    }
                }
                .background(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))

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

    private func exerciseRow(_ ex: GeneratedExercise, position: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name)
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text("\(ex.sets) × \(ex.reps) · rest \(ex.restSeconds)s")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Spacer(minLength: 8)
            Button {
                detailExercise = CoachDatabase.shared.exercise(id: ex.exerciseId)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show details for \(ex.name)")

            Button {
                swappingPreviewIdx = (preview?.exercises.firstIndex(where: { $0.id == ex.id }))
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Swap \(ex.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Bottom bar (state-dependent)

    @ViewBuilder
    private var bottomBar: some View {
        switch phase {
        case .input:
            VStack(spacing: 0) {
                Button(action: generate) {
                    Text("Generate")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                        .foregroundStyle(Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
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

    private func generate() {
        // Build a fresh per-tap seed so each Generate / Regenerate gives variety
        // without polluting the user's permanent planInputsHash.
        let seed = "coach-req-\(focus.rawValue)-\(durationMinutes)-\(Date().timeIntervalSince1970)"
        lastSeed = seed

        // Use a memory snapshot with the user's chosen duration so the
        // generator's budget math respects it. We don't write back to memory.
        var mem = memoryStore.memory
        mem.sessionMinutes = durationMinutes

        let profile = DemographicProfile.from(mem)
        // Build a runtime-history context so the coach-requested workout
        // benefits from the same signals the planner gets — progressive
        // overload targets, sore-area avoidance, stagnation swaps, etc.
        let context = GeneratorContext.from(
            sessions: sessionStore.savedSessions,
            soreness: mem.soreness,
            feedback: mem.feedback
        )
        let workout: GeneratedWorkout
        switch focus {
        case .mobility:
            workout = WorkoutGenerator.generateMobility(
                memory: mem, profile: profile, hashSeed: seed, context: context
            )
        default:
            let (liftIdx, total) = focus.liftIndexTotalPair()
            workout = WorkoutGenerator.generateLift(
                liftIndex: liftIdx, totalLifts: total,
                memory: mem, profile: profile, hashSeed: seed, context: context
            )
        }
        preview = workout
        phase = .preview
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
}
