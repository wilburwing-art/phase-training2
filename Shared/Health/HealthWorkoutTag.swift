// HealthWorkoutTag.swift — how a workout this app wrote to Apple Health is
// recognised as its own (PLAN-watch.md, "Apple Health, written once").
//
// Compiled into both the iOS app and the watch app. Whichever of them saves a
// session's workout stamps it with these, and the phone's importer drops any
// workout carrying them before import, activity detection or readiness see
// it. The bundle-id prefix is the second guard: the watch app's bundle id is
// the phone's with a suffix, so one prefix covers both writers.

import Foundation

enum HealthWorkoutTag {
    /// Custom metadata key holding the session id.
    static let sessionKey = "pt_session"
    /// Both apps' bundle ids start with this.
    static let bundlePrefix = "com.phasetraining.app"
    /// `HKMetadataKeySyncVersion`. Bump only if a later save of the same
    /// session should replace an earlier one with different content.
    static let syncVersion = 1

    /// Stable id for a session, from its start time, which is also what
    /// `SavedSession.id` derives from. Used for `HKMetadataKeySyncIdentifier`
    /// and the `pt_session` metadata value, so a retried or repeated save of
    /// the same session replaces the earlier copy instead of adding one.
    static func sessionId(for startTime: Date) -> String {
        "pt-session-\(Int64((startTime.timeIntervalSince1970 * 1000).rounded()))"
    }

    /// True when a workout was written by this app on either device.
    static func isOwn(sessionTag: String?, sourceBundleId: String?) -> Bool {
        if let sessionTag, !sessionTag.isEmpty { return true }
        if let sourceBundleId, sourceBundleId.hasPrefix(bundlePrefix) { return true }
        return false
    }
}

/// Who saves a session's workout to Apple Health. Exactly one of them does.
/// Nil (every session logged before this existed) means the phone.
enum HealthWriter: String, Codable, Equatable {
    case phone
    /// The watch ran an HKWorkoutSession for it and saves it.
    case watch
}
