// RestActivityAttributes.swift: the data a rest-timer Live Activity carries.
//
// Compiled by the app and by the widget extension (both read it), and by the
// watch target because it sits under Shared/, so everything ActivityKit is
// behind a canImport/os guard. The content state itself is plain Foundation so
// the coordinator and its tests never touch ActivityKit.

import Foundation

/// What the Lock Screen and Dynamic Island show during a rest.
struct RestActivityState: Codable, Hashable {
    var exerciseName: String
    /// The set just completed (1-based).
    var setNumber: Int
    var totalSets: Int
    /// When the countdown reaches zero.
    var restEndDate: Date
    /// True once the app has seen the rest run out. The widget also treats a
    /// stale activity as finished, since the system cannot run code at expiry.
    var finished: Bool = false
}

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

struct RestActivityAttributes: ActivityAttributes {
    typealias ContentState = RestActivityState
    /// Static for the life of the activity: one activity per workout.
    var workoutName: String
}
#endif
