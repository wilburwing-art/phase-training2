// RestActivityButtonActions.swift: what the Live Activity Skip and +15
// buttons do in the app process.
//
// The buttons run with the app in the background, where LogScreen's
// `onChange(of: rest)` may not fire, so the activity is synced here as well.
// A second sync of the same snapshot issues nothing.

import Foundation

@MainActor
enum RestActivityButtonActions {
    /// Wire the buttons to the live workout and the app-wide coordinator.
    static func install() {
        RestActivityButtonHandler.handle = { button in
            handle(button, controller: ActiveWorkoutRegistry.shared.resolve(),
                   coordinator: RestActivityCenter.shared)
        }
    }

    static func handle(_ button: RestActivityButton,
                       controller: ActiveWorkoutController?,
                       coordinator: RestActivityCoordinator,
                       now: Date = Date()) {
        guard let controller else {
            // Nothing drives the activity, so Skip clears it. +15 has no rest to extend.
            if button == .skip { coordinator.sync(nil, now: now) }
            return
        }
        switch button {
        case .skip:
            _ = WorkoutIntentActions.skipRest(in: controller, now: now)
        case .add(let seconds):
            _ = WorkoutIntentActions.addRest(seconds: seconds, in: controller, now: now)
        }
        coordinator.sync(controller.liveActivitySnapshot(), now: now)
    }
}

extension ActiveWorkoutController {
    /// The running rest, for the Live Activity coordinator. nil when no rest
    /// is anchored. An already-expired rest still reports (the coordinator
    /// shows it as done) until the next set or the end of the workout clears it.
    func liveActivitySnapshot() -> RestSnapshot? {
        guard let exIdx = rest.exIdx, let setIdx = rest.setIdx,
              let started = rest.startedAt, let duration = rest.duration,
              session.exercises.indices.contains(exIdx) else { return nil }
        let ex = session.exercises[exIdx]
        return RestSnapshot(workoutName: session.name,
                            exerciseName: ex.name,
                            setNumber: setIdx + 1,
                            totalSets: ex.sets.count,
                            endDate: started.addingTimeInterval(TimeInterval(duration)))
    }
}
