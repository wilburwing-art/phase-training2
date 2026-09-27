// HealthWorkoutWriter.swift — the phone's Apple Health write (PLAN-watch.md, step 2).
//
// One session, one workout in Health. The phone saves a completed session
// unless the watch ran a workout session for it (`SavedSession.healthWriter
// == .watch`), in which case the watch saves and this does nothing. Every
// save carries the sync identifier and version, so a retry or a repeated
// save replaces the earlier copy, plus the `pt_session` tag the importer
// filters on.
//
// The share grant is asked the first time there is something to write, not
// at launch and not during setup. A denied grant is silent: Health simply
// stays without the session.
//
// Pure part: `payload(for:)`. The store call sits behind a protocol so
// tests never touch HealthKit.

import Foundation
import HealthKit
import OSLog

struct HealthWorkoutPayload: Equatable {
    let sessionId: String
    let name: String
    let start: Date
    let end: Date
    let activityType: HKWorkoutActivityType

    var metadata: [String: Any] {
        [HKMetadataKeySyncIdentifier: sessionId,
         HKMetadataKeySyncVersion: HealthWorkoutTag.syncVersion,
         HKMetadataKeyWorkoutBrandName: "Phase Training",
         HealthWorkoutTag.sessionKey: sessionId]
    }
}

protocol HealthWorkoutStore: Sendable {
    /// Ask for the workout share grant. Returns false when Health is not
    /// available or the user declined.
    func requestWorkoutShareAuthorization() async throws -> Bool
    func save(_ payload: HealthWorkoutPayload) async throws
}

enum HealthWorkoutWriter {

    private static let log = Logger(subsystem: "com.phasetraining.app", category: "health-write")

    /// What to write for a saved session, or nil when nothing should be:
    /// the watch owns the write, or no set was completed (a session with
    /// zero work is not a workout).
    static func payload(for session: SavedSession) -> HealthWorkoutPayload? {
        guard session.healthWriter != .watch else { return nil }
        guard session.exercises.contains(where: { $0.sets.contains { $0.done } }) else { return nil }
        let end = max(session.endTime, session.startTime.addingTimeInterval(60))
        return HealthWorkoutPayload(sessionId: HealthWorkoutTag.sessionId(for: session.startTime),
                                    name: session.name,
                                    start: session.startTime,
                                    end: end,
                                    activityType: .traditionalStrengthTraining)
    }

    /// Save a session's workout. Fire and forget from the save hook.
    static func record(_ session: SavedSession, store: HealthWorkoutStore = HKWorkoutWriterStore()) async {
        guard let payload = payload(for: session) else { return }
        do {
            guard try await store.requestWorkoutShareAuthorization() else {
                log.notice("workout not written: no share grant")
                return
            }
            try await store.save(payload)
            log.notice("workout written: \(payload.sessionId, privacy: .public)")
        } catch {
            log.error("workout write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Production store. `HKWorkoutBuilder` rather than the deprecated
/// `HKWorkout` initialisers; no samples are attached, since the phone has no
/// heart rate of its own. The watch's builder collects those live.
struct HKWorkoutWriterStore: HealthWorkoutStore, @unchecked Sendable {
    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    func requestWorkoutShareAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let type = HKObjectType.workoutType()
        if store.authorizationStatus(for: type) == .notDetermined {
            try await store.requestAuthorization(toShare: [type], read: [])
        }
        return store.authorizationStatus(for: type) == .sharingAuthorized
    }

    func save(_ payload: HealthWorkoutPayload) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = payload.activityType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: payload.start)
        try await builder.addMetadata(payload.metadata)
        try await builder.endCollection(at: payload.end)
        _ = try await builder.finishWorkout()
    }
}
