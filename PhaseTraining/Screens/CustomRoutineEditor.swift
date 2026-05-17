// CustomRoutineEditor.swift — name + exercise-list editor for user workouts.
//
// One screen that handles both "new" and "edit existing". Mirrors the binding
// pattern of RoutineDetailScreen: the parent (RoutineLibraryFlow) owns
// `name` + `exercises` as @State and passes them in as Bindings. That lets
// the shared ExercisePicker (driven by the same flow) mutate the editor's
// list directly via callbacks without any indirection or buffered handoffs.
//
// Long-press on a row → context menu → swap with similar / pick from library
// / remove. Tap a row → preview the source exercise from coach.db.

import SwiftUI

struct CustomRoutineEditor: View {
    @EnvironmentObject private var customStore: CustomRoutineStore
    @EnvironmentObject private var sessionStore: SessionStore

    /// nil = brand-new workout (Save creates a fresh CustomRoutine). non-nil =
    /// editing a saved routine (Save updates by id).
    let existing: CustomRoutine?
    @Binding var name: String
    @Binding var exercises: [RoutineExercise]

    let onBack: () -> Void
    let onWorkoutStarted: () -> Void
    let onAddExercises: () -> Void
    let onPickFromLibrary: (Int) -> Void
    let onPreviewExercise: (Exercise) -> Void

    @State private var substitutingIndex: Int? = nil
    @State private var showDeleteConfirm = false

    private var isExisting: Bool { existing != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !exercises.isEmpty
    }
    private var setCount: Int { exercises.compactMap(\.sets).reduce(0, +) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        nameField
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                        statsLine
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        sectionHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                            .padding(.bottom, 10)
                        if exercises.isEmpty {
                            emptyState
                                .padding(.horizontal, 20)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                                    rowCard(idx: idx, ex: ex)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        addButton
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        Spacer().frame(height: 160)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            bottomBar
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
        .sheet(item: substitutingBinding) { wrapped in
            let originalRex = exercises[wrapped.index]
            SubstituteExerciseSheet(
                originalName: originalRex.name,
                substitutes: CoachDatabase.shared.substitutes(forExerciseId: originalRex.exerciseId),
                onPick: { picked in
                    applySubstitute(picked, at: wrapped.index)
                }
            )
        }
        .alert("Delete this workout?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove it from your library. Past sessions you logged from it stay in history.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("Library")
                            .font(.custom("SpaceGrotesk-Medium", size: 15))
                    }
                    .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(isExisting ? "Edit workout" : "New workout")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 17))
                Spacer()
                if isExisting {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("NEW")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
            Rectangle().fill(Color.line).frame(height: 0.5)
        }
    }

    // MARK: - Header pieces

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            TextField("", text: $name,
                      prompt: Text("e.g. Bench focus push day").foregroundColor(Color.ink3))
                .font(.custom("SpaceGrotesk-SemiBold", size: 24))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
        }
    }

    private var statsLine: some View {
        Text("\(exercises.count) EX · \(setCount) SETS · CUSTOM")
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }

    private var sectionHeader: some View {
        HStack {
            Text("EXERCISES")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Spacer()
            Text("LONG-PRESS TO SWAP")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
    }

    // MARK: - Rows

    private func rowCard(idx: Int, ex: RoutineExercise) -> some View {
        Button {
            if let exercise = CoachDatabase.shared.exercise(id: ex.exerciseId) {
                onPreviewExercise(exercise)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(String(format: "%02d", idx + 1))
                    .font(.custom("JetBrainsMono-Regular", size: 11))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 22, alignment: .trailing)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ex.name)
                        .font(.custom("SpaceGrotesk-SemiBold", size: 17))
                        .tracking(-0.01 * 17)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(rowMeta(ex))
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .tracking(0.05 * 10)
                        .foregroundStyle(Color.ink2)
                        .textCase(.uppercase)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { substitutingIndex = idx } label: {
                Label("Swap with similar…", systemImage: "rectangle.on.rectangle")
            }
            Button { onPickFromLibrary(idx) } label: {
                Label("Pick from library…", systemImage: "magnifyingglass")
            }
            Button(role: .destructive) { exercises.remove(at: idx) } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func rowMeta(_ ex: RoutineExercise) -> String {
        var parts: [String] = []
        if let s = ex.sets { parts.append("\(s) SETS") }
        if let r = ex.reps, !r.isEmpty { parts.append(r.uppercased()) }
        if let rest = ex.rest, !rest.isEmpty { parts.append("\(rest.uppercased()) REST") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Empty state / add

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No exercises yet")
                .font(.custom("SpaceGrotesk-SemiBold", size: 18))
                .foregroundStyle(Color.ink)
            Text("Tap + below to browse the library and add your first one.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var addButton: some View {
        Button(action: onAddExercises) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add exercises")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
            }
            .foregroundStyle(Color.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentWash)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentBorder, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(action: saveAndStart) {
                pillLabel("Save & start", filled: true)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)

            Button(action: saveOnly) {
                pillLabel("Save", filled: false)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
    }

    private func pillLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.custom("SpaceGrotesk-SemiBold", size: 15))
            .foregroundStyle(filled ? Color.accentInk : Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(filled ? Color.accent : Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(filled ? Color.clear : Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(canSave ? 1 : 0.4)
    }

    // MARK: - Substitution

    private var substitutingBinding: Binding<EditorRowIndex?> {
        Binding(
            get: { substitutingIndex.map(EditorRowIndex.init) },
            set: { substitutingIndex = $0?.index }
        )
    }

    private func applySubstitute(_ picked: Exercise, at idx: Int) {
        guard exercises.indices.contains(idx) else { return }
        let old = exercises[idx]
        exercises[idx] = RoutineExercise(
            id: old.id,
            exerciseId: picked.id,
            name: picked.name,
            position: old.position,
            sets: old.sets ?? picked.defaultSets,
            reps: old.reps ?? picked.defaultReps,
            rest: old.rest ?? picked.defaultRest,
            notes: old.notes
        )
    }

    // MARK: - Save / start

    private func currentDraft() -> CustomRoutine {
        var base = existing ?? CustomRoutine.makeBlank()
        base.name = name.trimmingCharacters(in: .whitespaces)
        return base.updatingExercises(from: exercises)
    }

    private func saveOnly() {
        customStore.save(currentDraft())
        onBack()
    }

    private func saveAndStart() {
        let draft = currentDraft()
        customStore.save(draft)
        sessionStore.saveActive(sessionStore.createSession(from: draft.toWorkoutTemplate()))
        onWorkoutStarted()
    }

    private func performDelete() {
        if let existing { customStore.delete(existing) }
        onBack()
    }
}

private struct EditorRowIndex: Identifiable {
    let index: Int
    var id: Int { index }
}
