import Foundation

/// The live `ActiveWorkoutController`, for code outside the view tree (App
/// Intents). `TodayTab` sets it when it builds a controller and clears it when
/// it drops one. Weak, so a controller the view drops does not live on.
@MainActor
final class ActiveWorkoutRegistry {
    static let shared = ActiveWorkoutRegistry()
    weak var current: ActiveWorkoutController?
}
