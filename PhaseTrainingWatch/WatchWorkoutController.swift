// WatchWorkoutController.swift — the watch's Apple Health workout (PLAN-watch.md, step 2).
//
// Runs an HKWorkoutSession with a live builder for a session driven from the
// watch. That keeps the app alive through rests, collects heart rate and
// active energy, and saves the workout when the session ends, stamped with
// the same sync metadata the phone uses (`HealthWorkoutTag`), so the phone's
// importer never reads it back and a repeated save replaces rather than adds.
// Exactly one device saves: once this starts, the watch tells the phone
// (`watchWorkoutStarted`) and the phone's writer stands down.

import Foundation
import Combine
import HealthKit
import OSLog

@MainActor
final class WatchWorkoutController: NSObject, ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeEnergyKcal: Double?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var appSessionStart: Date?

    private static let log = Logger(subsystem: "com.phasetraining.app.watchkitapp", category: "workout")

    /// Ask for the share grant and the live reads. Returns false when Health
    /// is unavailable or the workout share was declined.
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        var read: Set<HKObjectType> = [.workoutType()]
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(energy) }
        do {
            try await store.requestAuthorization(toShare: [.workoutType()], read: read)
        } catch {
            Self.log.error("authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    /// Start collecting for the app session that began at `appSessionStart`.
    func start(appSessionStart: Date) async -> Bool {
        guard !isRunning else { return true }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            self.appSessionStart = appSessionStart
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            isRunning = true
            Self.log.notice("workout started for \(HealthWorkoutTag.sessionId(for: appSessionStart), privacy: .public)")
            return true
        } catch {
            Self.log.error("workout start failed: \(error.localizedDescription, privacy: .public)")
            reset()
            return false
        }
    }

    /// End the workout and save it. Safe to call when nothing is running.
    func end() async {
        guard let session, let builder, let appSessionStart else { reset(); return }
        let sessionId = HealthWorkoutTag.sessionId(for: appSessionStart)
        session.end()
        do {
            try await builder.endCollection(at: Date())
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: sessionId,
                HKMetadataKeySyncVersion: HealthWorkoutTag.syncVersion,
                HKMetadataKeyWorkoutBrandName: "Phase Training",
                HealthWorkoutTag.sessionKey: sessionId,
            ])
            _ = try await builder.finishWorkout()
            Self.log.notice("workout saved: \(sessionId, privacy: .public)")
        } catch {
            Self.log.error("workout save failed: \(error.localizedDescription, privacy: .public)")
        }
        reset()
    }

    private func reset() {
        session = nil
        builder = nil
        appSessionStart = nil
        isRunning = false
        heartRate = nil
        activeEnergyKcal = nil
    }
}

extension WatchWorkoutController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Self.log.notice("session state \(fromState.rawValue) -> \(toState.rawValue)")
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Self.log.error("session failed: \(error.localizedDescription, privacy: .public)")
    }
}

extension WatchWorkoutController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var heartRate: Double?
        var energy: Double?
        for case let type as HKQuantityType in collectedTypes {
            guard let statistics = workoutBuilder.statistics(for: type) else { continue }
            switch type.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                heartRate = statistics.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            default:
                continue
            }
        }
        Task { @MainActor in
            if let heartRate { self.heartRate = heartRate }
            if let energy { self.activeEnergyKcal = energy }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
