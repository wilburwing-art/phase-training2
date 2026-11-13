// ActivityKitRestHost.swift: the real ActivityKit side of the rest-timer
// Live Activity. Every call degrades to a no-op on failure: the expiry
// notification in RestTimerState is unchanged and remains the fallback.

import Foundation
import ActivityKit

final class ActivityKitRestHost: RestActivityHost {
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(workoutName: String, state: RestActivityState, staleDate: Date) -> Bool {
        do {
            _ = try Activity<RestActivityAttributes>.request(
                attributes: RestActivityAttributes(workoutName: workoutName),
                content: .init(state: state, staleDate: staleDate),
                pushType: nil)
            return true
        } catch {
            return false
        }
    }

    func update(state: RestActivityState, staleDate: Date) {
        let content = ActivityContent(state: state, staleDate: staleDate)
        Task {
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.update(content)
            }
        }
    }

    func endAll() {
        Task {
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

/// App-wide coordinator wired to ActivityKit.
enum RestActivityCenter {
    static let shared = RestActivityCoordinator(host: ActivityKitRestHost())
}
