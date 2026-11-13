// RestActivityCoordinator.swift: decides when the rest-timer Live Activity is
// started, updated or ended. No ActivityKit here: the real wrapper
// (ActivityKitRestHost) implements `RestActivityHost`, and tests use a fake.
//
// LogScreen reports the rest it is showing through `sync`; the coordinator
// diffs it against what it last issued, so one call site covers start, extend,
// shorten, a new rest after the next set, and skip.

import Foundation

/// What the screen is resting on right now. nil passed to `sync` = no rest.
struct RestSnapshot: Equatable {
    var workoutName: String
    var exerciseName: String
    var setNumber: Int
    var totalSets: Int
    var endDate: Date
}

/// The slice of ActivityKit the coordinator needs.
protocol RestActivityHost: AnyObject {
    /// False when the user turned Live Activities off or the device lacks them.
    var isAvailable: Bool { get }
    /// Returns false when the request failed, so the coordinator does not
    /// believe an activity exists.
    func start(workoutName: String, state: RestActivityState, staleDate: Date) -> Bool
    func update(state: RestActivityState, staleDate: Date)
    func endAll()
}

final class RestActivityCoordinator {
    private let host: RestActivityHost
    private(set) var current: RestActivityState?
    private var currentWorkout: String?

    init(host: RestActivityHost) { self.host = host }

    /// Report the rest on screen (or nil when none). Issues at most one host call
    /// (two when a different workout replaces a leftover activity).
    func sync(_ rest: RestSnapshot?, now: Date = Date()) {
        guard let rest else { end(); return }
        guard host.isAvailable else { return }
        let state = RestActivityState(exerciseName: rest.exerciseName,
                                      setNumber: rest.setNumber,
                                      totalSets: rest.totalSets,
                                      restEndDate: rest.endDate)
        // The screen never reports `finished`; after `restExpired` the same
        // snapshot must not flip it back to false.
        if let current, currentWorkout == rest.workoutName,
           Self.equalIgnoringFinished(current, state) { return }
        if current != nil, currentWorkout == rest.workoutName {
            // staleDate is the rest end: past it the widget reads "Rest done"
            // even if the app is suspended and never sends `restExpired`.
            host.update(state: state, staleDate: rest.endDate)
            current = state
        } else {
            if current != nil {
                host.endAll()
                current = nil
                currentWorkout = nil
            }
            // A rest that already ran out would appear reading "Rest done".
            if rest.endDate <= now { return }
            if host.start(workoutName: rest.workoutName, state: state, staleDate: rest.endDate) {
                current = state
                currentWorkout = rest.workoutName
            } else {
                current = nil
                currentWorkout = nil
            }
        }
    }

    /// The countdown reached zero while the app was running.
    func restExpired() {
        guard var state = current, !state.finished else { return }
        state.finished = true
        host.update(state: state, staleDate: state.restEndDate)
        current = state
    }

    /// Workout finished, cancelled or abandoned.
    func sessionEnded() { end() }

    /// Cold launch. Rest state lives in the screen and is not persisted, so an
    /// activity that survived the process has nothing driving it: end all.
    func appLaunched() { end() }

    private static func equalIgnoringFinished(_ a: RestActivityState, _ b: RestActivityState) -> Bool {
        var a = a
        a.finished = b.finished
        return a == b
    }

    private func end() {
        // Always tell the host: after a relaunch `current` is nil but an
        // activity from the previous process may still exist.
        host.endAll()
        current = nil
        currentWorkout = nil
    }
}
