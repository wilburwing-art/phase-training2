import Foundation

/// The live `ActiveWorkoutController`, for code outside the view tree (App
/// Intents, Live Activity buttons). `TodayTab` registers the controller it
/// shows and drops it when the log route closes. When no log screen is open
/// but `SessionStore.active` holds a workout (log route closed, or Siri
/// launched a killed app), `resolve()` builds a controller from the store and
/// keeps it until `TodayTab` adopts it or the workout ends.
@MainActor
final class ActiveWorkoutRegistry {
    static let shared = ActiveWorkoutRegistry()

    /// Weak, so a controller the view drops does not live on.
    weak var current: ActiveWorkoutController?
    /// The app's session store. Set in `PhaseTrainingApp.init`, before any view.
    var store: SessionStore?
    /// A controller `resolve()` built itself. Held strongly because no view does.
    private var built: ActiveWorkoutController?
    /// Passed to controllers `resolve()` builds, so UI tests see the same rest behavior.
    var suppressAutoRest = false

    /// The registered controller, or one built from `store.active` when none is.
    func resolve() -> ActiveWorkoutController? {
        // A built controller goes stale when its workout ends or another starts.
        if let b = built, b.session.startTime != store?.active?.startTime {
            if current === b { current = nil }
            built = nil
        }
        if let current { return current }
        guard let store, let active = store.active else {
            built = nil
            return nil
        }
        let c = ActiveWorkoutController(store: store, session: active,
                                        suppressAutoRest: suppressAutoRest)
        built = c
        current = c
        return c
    }

    /// The log route closed: forget the shown controller and any built one.
    func drop() {
        current = nil
        built = nil
    }
}
