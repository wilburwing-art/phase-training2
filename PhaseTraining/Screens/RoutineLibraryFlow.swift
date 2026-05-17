// RoutineLibraryFlow.swift — coach.db routine library + user custom workouts,
// presented modally.
//
// Was the Train tab in builds 19-24. Phase 11 dropped Train from the tab
// bar; the library is now a sheet you reach from Today ("Pick a different
// routine") or from a Week-day edit ("Change routine").
//
// Flow surfaces:
//   - RoutinePickerScreen → routine list, also "+ Create custom" entry
//   - RoutineDetailScreen → editing a bundled routine (in-memory only)
//   - CustomRoutineEditor → editing a user-created routine (persisted via
//     CustomRoutineStore)
//   - ExercisePickerScreen → reused by both routine detail surfaces
//   - ExerciseDetailScreen → preview a single exercise
//
// `onWorkoutStarted` fires after a session is created from any routine; the
// presenter (Today or Week) dismisses the sheet in response.
//
// Both detail surfaces use the same picker-confirm pattern: the flow owns
// the editing exercise list as @State and passes it as a Binding to the
// detail screen, then applies picker results back into the same array.

import SwiftUI

struct RoutineLibraryFlow: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var customStore: CustomRoutineStore
    let onWorkoutStarted: () -> Void
    let onDismiss: () -> Void

    @State private var route: Route = .routines

    // Bundled-routine editing state
    @State private var editingRoutine: Routine? = nil
    @State private var editingExercises: [RoutineExercise] = []

    // Custom-routine editing state. nil `editingCustom` + customExercises
    // populated = new workout in progress.
    @State private var editingCustom: CustomRoutine? = nil
    @State private var customName: String = ""
    @State private var customExercises: [RoutineExercise] = []

    enum Route: Equatable {
        case routines
        case routineDetail
        case customEditor
        case exercisePicker(ExercisePickerMode, target: PickerTarget)
        case exerciseDetail(Int, canAdd: Bool, returnTo: PickerTarget)
    }

    /// Which surface owns the picker / detail when control returns.
    enum PickerTarget: Equatable {
        case bundled
        case custom
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .routines:
            RoutinePickerScreen(
                customRoutines: customStore.routines,
                onBack: onDismiss,
                onPickBundled: { routine in
                    editingRoutine = routine
                    editingExercises = CoachDatabase.shared.exercises(forRoutineId: routine.id)
                    transition(.routineDetail)
                },
                onPickCustom: { custom in
                    editingCustom = custom
                    customName = custom.name
                    customExercises = custom.toRoutineExercises()
                    transition(.customEditor)
                },
                onCreateCustom: {
                    editingCustom = nil
                    customName = ""
                    customExercises = []
                    transition(.customEditor)
                }
            )

        case .routineDetail:
            if let routine = editingRoutine {
                RoutineDetailScreen(
                    routine: routine,
                    exercises: $editingExercises,
                    onBack: { transition(.routines) },
                    onStart: { startWorkoutFromBundled() },
                    onTapExercise: { rex in
                        if let ex = CoachDatabase.shared.exercise(id: rex.exerciseId) {
                            transition(.exerciseDetail(ex.id, canAdd: false, returnTo: .bundled))
                        }
                    },
                    onAddExercise: { transition(.exercisePicker(.add, target: .bundled)) },
                    onReplaceExercise: { idx in
                        transition(.exercisePicker(.replace(rowIndex: idx), target: .bundled))
                    }
                )
            } else {
                Color.bg.onAppear { transition(.routines) }
            }

        case .customEditor:
            CustomRoutineEditor(
                existing: editingCustom,
                name: $customName,
                exercises: $customExercises,
                onBack: {
                    editingCustom = nil
                    customName = ""
                    customExercises = []
                    transition(.routines)
                },
                onWorkoutStarted: {
                    editingCustom = nil
                    customName = ""
                    customExercises = []
                    onWorkoutStarted()
                },
                onAddExercises: { transition(.exercisePicker(.add, target: .custom)) },
                onPickFromLibrary: { idx in
                    transition(.exercisePicker(.replace(rowIndex: idx), target: .custom))
                },
                onPreviewExercise: { ex in
                    transition(.exerciseDetail(ex.id, canAdd: false, returnTo: .custom))
                }
            )

        case .exercisePicker(let mode, let target):
            ExercisePickerScreen(
                mode: mode,
                onCancel: { transition(returnRoute(for: target)) },
                onConfirm: { picks in
                    applyPicks(picks, mode: mode, target: target)
                    transition(returnRoute(for: target))
                },
                onPreview: { ex in
                    transition(.exerciseDetail(ex.id, canAdd: true, returnTo: target))
                }
            )

        case .exerciseDetail(let exerciseId, let canAdd, let returnTo):
            if let exercise = CoachDatabase.shared.exercise(id: exerciseId) {
                ExerciseDetailScreen(
                    exercise: exercise,
                    canAdd: canAdd,
                    onBack: {
                        transition(canAdd
                                   ? .exercisePicker(.add, target: returnTo)
                                   : returnRoute(for: returnTo))
                    },
                    onAdd: canAdd ? {
                        applyPicks([exercise], mode: .add, target: returnTo)
                        transition(returnRoute(for: returnTo))
                    } : nil
                )
            } else {
                Color.bg.onAppear { transition(.routines) }
            }
        }
    }

    private func returnRoute(for target: PickerTarget) -> Route {
        switch target {
        case .bundled: return .routineDetail
        case .custom:  return .customEditor
        }
    }

    private func transition(_ next: Route) {
        withAnimation(.easeInOut(duration: 0.18)) { route = next }
    }

    private func startWorkoutFromBundled() {
        guard let routine = editingRoutine else { return }
        let template = routine.toWorkoutTemplate(with: editingExercises)
        store.saveActive(store.createSession(from: template))
        onWorkoutStarted()
    }

    private func applyPicks(_ picks: [Exercise], mode: ExercisePickerMode, target: PickerTarget) {
        switch target {
        case .bundled:
            applyPicksTo(&editingExercises, picks: picks, mode: mode)
        case .custom:
            applyPicksTo(&customExercises, picks: picks, mode: mode)
        }
    }

    private func applyPicksTo(_ list: inout [RoutineExercise], picks: [Exercise], mode: ExercisePickerMode) {
        switch mode {
        case .add:
            let nextPosition = (list.map(\.position).max() ?? 0) + 1
            for (offset, ex) in picks.enumerated() {
                list.append(
                    RoutineExercise(
                        id: -(list.count + offset + 1),
                        exerciseId: ex.id,
                        name: ex.name,
                        position: nextPosition + offset,
                        sets: ex.defaultSets,
                        reps: ex.defaultReps,
                        rest: ex.defaultRest,
                        notes: nil
                    )
                )
            }
        case .replace(let idx):
            guard let ex = picks.first, list.indices.contains(idx) else { return }
            let old = list[idx]
            list[idx] = RoutineExercise(
                id: old.id,
                exerciseId: ex.id,
                name: ex.name,
                position: old.position,
                sets: ex.defaultSets ?? old.sets,
                reps: ex.defaultReps ?? old.reps,
                rest: ex.defaultRest ?? old.rest,
                notes: old.notes
            )
        }
    }
}
