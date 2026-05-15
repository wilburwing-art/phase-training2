// RoutineLibraryFlow.swift — coach.db routine library, presented modally.
//
// Was the Train tab in builds 19-24. Phase 11 dropped Train from the tab
// bar; the library is now a sheet you reach from Today ("Pick a different
// routine") or from a Week-day edit ("Change routine"). The flow itself —
// Routines → RoutineDetail → ExercisePicker → ExerciseDetail — is unchanged.
//
// `onWorkoutStarted` fires after a session is created from a routine; the
// presenter (Today or Week) dismisses the sheet in response.

import SwiftUI

struct RoutineLibraryFlow: View {
    @EnvironmentObject private var store: SessionStore
    let onWorkoutStarted: () -> Void
    let onDismiss: () -> Void

    @State private var route: Route = .routines
    @State private var editingRoutine: Routine? = nil
    @State private var editingExercises: [RoutineExercise] = []

    enum Route: Equatable {
        case routines
        case routineDetail
        case exercisePicker(ExercisePickerMode)
        case exerciseDetail(Int, canAdd: Bool)
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
                onBack: onDismiss,
                onPick: { routine in
                    editingRoutine = routine
                    editingExercises = CoachDatabase.shared.exercises(forRoutineId: routine.id)
                    transition(.routineDetail)
                }
            )

        case .routineDetail:
            if let routine = editingRoutine {
                RoutineDetailScreen(
                    routine: routine,
                    exercises: $editingExercises,
                    onBack: { transition(.routines) },
                    onStart: { startWorkoutFromEditing() },
                    onTapExercise: { rex in
                        if let ex = CoachDatabase.shared.exercise(id: rex.exerciseId) {
                            transition(.exerciseDetail(ex.id, canAdd: false))
                        }
                    },
                    onAddExercise: { transition(.exercisePicker(.add)) },
                    onReplaceExercise: { idx in
                        transition(.exercisePicker(.replace(rowIndex: idx)))
                    }
                )
            } else {
                Color.bg.onAppear { transition(.routines) }
            }

        case .exercisePicker(let mode):
            ExercisePickerScreen(
                mode: mode,
                onCancel: { transition(.routineDetail) },
                onConfirm: { picks in
                    applyPicks(picks, mode: mode)
                    transition(.routineDetail)
                },
                onPreview: { ex in
                    transition(.exerciseDetail(ex.id, canAdd: true))
                }
            )

        case .exerciseDetail(let exerciseId, let canAdd):
            if let exercise = CoachDatabase.shared.exercise(id: exerciseId) {
                ExerciseDetailScreen(
                    exercise: exercise,
                    canAdd: canAdd,
                    onBack: { transition(canAdd ? .exercisePicker(.add) : .routineDetail) },
                    onAdd: canAdd ? {
                        applyPicks([exercise], mode: .add)
                        transition(.routineDetail)
                    } : nil
                )
            } else {
                Color.bg.onAppear { transition(.routineDetail) }
            }
        }
    }

    private func transition(_ next: Route) {
        withAnimation(.easeInOut(duration: 0.18)) { route = next }
    }

    private func startWorkoutFromEditing() {
        guard let routine = editingRoutine else { return }
        let template = routine.toWorkoutTemplate(with: editingExercises)
        store.saveActive(store.createSession(from: template))
        onWorkoutStarted()
    }

    private func applyPicks(_ picks: [Exercise], mode: ExercisePickerMode) {
        switch mode {
        case .add:
            let nextPosition = (editingExercises.map(\.position).max() ?? 0) + 1
            for (offset, ex) in picks.enumerated() {
                editingExercises.append(
                    RoutineExercise(
                        id: -(editingExercises.count + offset + 1),
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
            guard let ex = picks.first, editingExercises.indices.contains(idx) else { return }
            let old = editingExercises[idx]
            editingExercises[idx] = RoutineExercise(
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
