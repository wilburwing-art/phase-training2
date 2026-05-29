// HealthKitImporter.swift — Phase 2 read-only HK workout intake.
//
// Read-only on HKWorkoutType. No HK write. No clinical-record access.
// Auth happens lazily on first open of Settings → Health & Imports, never
// during onboarding. If the user dismisses or denies, the rest of the app
// works unchanged: GeneratorContext.from(...) sees zero imported workouts,
// ReadinessSignal.compute(...) returns 0.5 (neutral), generator scales by
// 1.0 (no effect).
//
// Why an actor: HKHealthStore is thread-safe but our convenience around
// it (auth state cache, error mapping) is not — funneling through an
// actor lets the rest of the app `await` without explicit serial queues.
//
// Mockability: the production path uses HKHealthStore directly. Tests pass
// a HKHealthStoreInterface that fakes auth + sample queries (see
// HealthKitImporterTests). The interface mirrors only the two methods we
// use, so we don't have to fake the whole HK surface.
//
// HKWorkoutActivityType → WorkoutKind mapping (documented inline near
// `mapKind(_:)` below):
//   .traditionalStrengthTraining, .functionalStrengthTraining,
//   .crossTraining, .highIntensityIntervalTraining
//     → .strength
//   .running, .cycling, .walking, .swimming, .rowing, .elliptical,
//   .stairs, .stepTraining, .hiking, .mixedCardio
//     → .cardio
//   everything else (sports, mind-body, water sports, etc.)
//     → .sport
//
// This is the same axis the rest of the app uses for "did the user do
// strength work or non-strength" — readiness density+trend treat strength
// + cardio + sport as one bucket (a "session"), but downstream Phase 3
// will route strength → priorBest extraction and cardio → sport-log.

import Foundation
import HealthKit

/// Source-of-record marker on an imported workout. Phase 2 only emits
/// `.healthKit`; the CSV cases are reserved for Phase 3 so the persistence
/// + readiness layers don't churn when CSV lands.
enum ImportSource: String, Codable, CaseIterable, Sendable {
    case healthKit
    case fitbodCSV
    case hevyCSV
    case stravaCSV
}

/// Coarse workout kind. The readiness signal treats all three as
/// equivalent "sessions" for density/trend; the bucketing matters more
/// in Phase 3 (CSV parsers route strength sets to a separate table).
enum WorkoutKind: String, Codable, CaseIterable, Sendable {
    case strength
    case cardio
    case sport
}

/// One imported workout row. Pure value type with no HK dependency at
/// the persistence layer — once mapped, the rest of the app handles
/// these like native sessions. `id` is the HK UUID for HK-sourced rows
/// (idempotent re-import) and a generated UUID for CSV-sourced rows.
struct ImportedWorkout: Equatable, Sendable, Codable {
    let id: String
    let source: ImportSource
    let kind: WorkoutKind
    let startTime: Date
    let duration: TimeInterval
    let energyKcal: Double?
}

// MARK: - HKHealthStore protocol seam (for testability)

/// Minimal surface of HKHealthStore that the importer touches. Tests fake
/// this; production passes a `HKHealthStoreWrapper` that forwards to the
/// real HKHealthStore. Kept tiny so we don't shadow the whole HK surface.
protocol HKHealthStoreInterface: Sendable {
    func requestWorkoutReadAuthorization() async throws -> Bool
    func recentWorkouts(days: Int) async throws -> [HKWorkoutLike]
}

/// Decoupled HKWorkout shape — the fields we actually need. Tests can
/// build these directly; the production wrapper maps from HKWorkout.
struct HKWorkoutLike: Sendable {
    let uuid: UUID
    let activityType: HKWorkoutActivityType
    let startDate: Date
    let duration: TimeInterval
    let totalEnergyBurnedKcal: Double?
}

/// Production wrapper around a real HKHealthStore. Read-only on
/// HKWorkoutType — no other HK types are requested.
struct HKHealthStoreWrapper: HKHealthStoreInterface, @unchecked Sendable {
    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    func requestWorkoutReadAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let workoutType = HKObjectType.workoutType()
        // HK auth is per-type: we ask read-only on workouts, no shares.
        // The system dialog appears once per type until the user changes
        // their decision in Settings. Repeat calls after grant are no-ops.
        try await store.requestAuthorization(toShare: [], read: [workoutType])
        // Authorization status for READ is opaque by design (Apple won't
        // let apps distinguish "denied" from "never asked" for reads, to
        // prevent fingerprinting). We treat a successful request as
        // "user saw the prompt"; whether they granted is observed by
        // attempting a query and checking the result count or error.
        return true
    }

    func recentWorkouts(days: Int) async throws -> [HKWorkoutLike] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let workoutType = HKObjectType.workoutType()
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [descriptor]
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let workouts: [HKWorkoutLike] = (samples as? [HKWorkout] ?? []).map { hk in
                    HKWorkoutLike(
                        uuid: hk.uuid,
                        activityType: hk.workoutActivityType,
                        startDate: hk.startDate,
                        duration: hk.duration,
                        totalEnergyBurnedKcal: hk.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    )
                }
                cont.resume(returning: workouts)
            }
            store.execute(q)
        }
    }
}

// MARK: - The importer

/// Read-only HealthKit workout importer. Phase 2's only HK surface.
/// Single instance lives behind `HealthKitImporter.shared` in production;
/// tests instantiate with a fake HKHealthStoreInterface.
actor HealthKitImporter {

    private let store: HKHealthStoreInterface

    init(store: HKHealthStoreInterface = HKHealthStoreWrapper()) {
        self.store = store
    }

    /// Triggers the system HK authorization dialog (once) and returns
    /// whether the request itself completed. As noted on the wrapper:
    /// HK does NOT expose post-grant read-status, so callers should treat
    /// the next `recentWorkouts(...)` empty result as ambiguous (could be
    /// no workouts OR denied access) — Phase 2's Settings UX surfaces the
    /// imported count to make this distinction observable to the user.
    func requestAuthorization() async throws -> Bool {
        try await store.requestWorkoutReadAuthorization()
    }

    /// Fetch the user's last `days` of workouts, mapped to ImportedWorkout.
    /// Default 28 days matches the readiness window (4 weeks). Idempotent:
    /// same HK UUID → same `id`, so re-import is safe with INSERT OR REPLACE.
    func recentWorkouts(days: Int = 28) async throws -> [ImportedWorkout] {
        let raw = try await store.recentWorkouts(days: days)
        return raw.map(Self.map(_:))
    }

    /// Pure mapper exposed for testability. Maps one HK workout to our
    /// internal value type, including the activity-type → WorkoutKind
    /// bucketing documented at the top of this file.
    static func map(_ hk: HKWorkoutLike) -> ImportedWorkout {
        ImportedWorkout(
            id: hk.uuid.uuidString,
            source: .healthKit,
            kind: mapKind(hk.activityType),
            startTime: hk.startDate,
            duration: hk.duration,
            energyKcal: hk.totalEnergyBurnedKcal
        )
    }

    /// HKWorkoutActivityType → coarse WorkoutKind. Strength buckets the
    /// four HK "strength-ish" activity types; cardio covers the common
    /// HK cardio types; everything else is `.sport` (rock climbing,
    /// tennis, soccer, surfing, yoga, etc.). Unknown future HK types
    /// land in `.sport` — safer to under-bucket than mis-bucket strength.
    static func mapKind(_ type: HKWorkoutActivityType) -> WorkoutKind {
        switch type {
        case .traditionalStrengthTraining,
             .functionalStrengthTraining,
             .crossTraining,
             .highIntensityIntervalTraining:
            return .strength
        case .running,
             .cycling,
             .walking,
             .swimming,
             .rowing,
             .elliptical,
             .stairs,
             .stepTraining,
             .hiking,
             .mixedCardio:
            return .cardio
        default:
            return .sport
        }
    }
}
