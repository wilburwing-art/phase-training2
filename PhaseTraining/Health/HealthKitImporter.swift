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

/// One sample of a body-metrics quantity. Lives at this layer so the rest
/// of the app doesn't import HealthKit just to consume the data. Both
/// body-mass and lean-mass arrive in kg; body-fat % arrives 0-100 (already
/// scaled out of HK's native 0-1 unit by the wrapper).
struct HKBodyMetricSample: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case bodyMass        // kg
        case bodyFatPercent  // %
        case leanBodyMass    // kg
    }
    let uuid: UUID
    let kind: Kind
    let date: Date
    let value: Double
}

/// Minimal surface of HKHealthStore that the importer touches. Tests fake
/// this; production passes a `HKHealthStoreWrapper` that forwards to the
/// real HKHealthStore. Kept tiny so we don't shadow the whole HK surface.
///
/// Body-metrics methods come with default no-op implementations so existing
/// fakes (HealthKitImporterTests.FakeStore) don't have to migrate when the
/// build-103 body-metrics intake lands.
protocol HKHealthStoreInterface: Sendable {
    func requestWorkoutReadAuthorization() async throws -> Bool
    func recentWorkouts(days: Int) async throws -> [HKWorkoutLike]
    func requestBodyMetricsReadAuthorization() async throws -> Bool
    func recentBodyMetrics(days: Int) async throws -> [HKBodyMetricSample]
}

extension HKHealthStoreInterface {
    /// Defaults to true (no-op grant) so existing fakes — written before
    /// the body-metrics protocol additions — keep compiling without a
    /// migration. The production wrapper overrides with the real
    /// per-type authorization request.
    func requestBodyMetricsReadAuthorization() async throws -> Bool { true }

    /// Defaults to empty so existing fakes keep returning "no body data"
    /// and the importer's downstream logic (de-dup against existing log)
    /// stays a no-op for those tests.
    func recentBodyMetrics(days: Int) async throws -> [HKBodyMetricSample] { [] }
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

    func requestBodyMetricsReadAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        var types: Set<HKObjectType> = []
        if let bm = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(bm) }
        if let bf = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(bf) }
        if let lm = HKObjectType.quantityType(forIdentifier: .leanBodyMass) { types.insert(lm) }
        guard !types.isEmpty else { return false }
        try await store.requestAuthorization(toShare: [], read: types)
        return true
    }

    func recentBodyMetrics(days: Int) async throws -> [HKBodyMetricSample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        var out: [HKBodyMetricSample] = []
        if let bm = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            out += try await fetchSamples(type: bm, predicate: predicate, descriptor: descriptor,
                                          unit: HKUnit.gramUnit(with: .kilo), kind: .bodyMass)
        }
        if let bf = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
            // HK returns body-fat as a fractional Double (0.0-1.0). Multiply
            // here so every downstream consumer sees the percent in display
            // form ("18.5", not "0.185").
            let raw = try await fetchSamples(type: bf, predicate: predicate, descriptor: descriptor,
                                             unit: HKUnit.percent(), kind: .bodyFatPercent)
            out += raw.map { s in
                HKBodyMetricSample(uuid: s.uuid, kind: s.kind, date: s.date, value: s.value * 100)
            }
        }
        if let lm = HKObjectType.quantityType(forIdentifier: .leanBodyMass) {
            out += try await fetchSamples(type: lm, predicate: predicate, descriptor: descriptor,
                                          unit: HKUnit.gramUnit(with: .kilo), kind: .leanBodyMass)
        }
        return out
    }

    /// Generic sample fetch for the three HKQuantityType reads. Returns
    /// our internal value type so the rest of the importer (and the call
    /// sites in HealthImportsScreen) don't import HealthKit just to
    /// consume one number per row.
    private func fetchSamples(
        type: HKQuantityType,
        predicate: NSPredicate,
        descriptor: NSSortDescriptor,
        unit: HKUnit,
        kind: HKBodyMetricSample.Kind
    ) async throws -> [HKBodyMetricSample] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [descriptor]
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let out: [HKBodyMetricSample] = (samples as? [HKQuantitySample] ?? []).map { s in
                    HKBodyMetricSample(
                        uuid: s.uuid,
                        kind: kind,
                        date: s.startDate,
                        value: s.quantity.doubleValue(for: unit)
                    )
                }
                cont.resume(returning: out)
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

    /// Raw last-`days` workouts, unmapped. The activity-detection layer
    /// (ActivityDetection.swift) needs the specific HKWorkoutActivityType
    /// (ski vs climb vs hike) that ImportedWorkout's coarse WorkoutKind
    /// deliberately drops, so it reads this instead of recentWorkouts.
    /// Same auth posture: never triggers the system dialog — an
    /// undetermined/denied read errors or comes back empty and the caller
    /// stays silent.
    func recentRawWorkouts(days: Int = 7) async throws -> [HKWorkoutLike] {
        try await store.recentWorkouts(days: days)
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

    // MARK: - Body metrics (build 103)

    /// Triggers the body-metrics auth dialog. Returns whether the request
    /// completed (mirrors `requestAuthorization` for workouts — HK won't
    /// expose post-grant read status, so an empty fetch later is
    /// ambiguous between "no data" and "denied").
    func requestBodyMetricsAuthorization() async throws -> Bool {
        try await store.requestBodyMetricsReadAuthorization()
    }

    /// Fetch the user's last `days` of body-metrics samples. Default 365
    /// because composition readings are infrequent (monthly DEXA, weekly
    /// InBody) and a 28-day window would routinely come back empty for
    /// people who care most. Returns mixed body-mass + fat-% + lean-mass
    /// samples sorted newest-first.
    func recentBodyMetrics(days: Int = 365) async throws -> [HKBodyMetricSample] {
        try await store.recentBodyMetrics(days: days)
    }
}

// MARK: - Sync results

/// What the body-metrics sync actually wrote into TrainingMemory. Surfaced
/// to HealthImportsScreen so the UX can show "imported 5 weights · 2 BF%
/// readings" instead of a silent black box.
struct BodyMetricsSyncSummary: Equatable, Sendable {
    var addedWeightEntries: Int
    var addedCompositionEntries: Int
    var skippedDuplicateSamples: Int
    /// Newest sample timestamp consumed, for "last synced" UX. nil when
    /// the sample list was empty.
    var newestSampleAt: Date?
}

/// Pure merge logic. Given current logs + a batch of HK samples, returns
/// the new logs we'd write + a summary of what changed. De-duplicates by
/// matching real timestamps within a 60-second window (HK's sub-second
/// precision means a re-sync would otherwise spam the log with near-identical
/// entries). Body-fat + lean-mass samples from one reading collapse onto one
/// BodyCompositionEntry — most scales report both within a second or two.
enum BodyMetricsMerger {
    /// Samples this close together are treated as one composition reading.
    /// Wider than a scale's BF%/lean emit gap, narrower than any real
    /// re-measurement interval.
    private static let pairWindow: TimeInterval = 120
    /// Two entries within this window are considered the same reading for
    /// dedup against the existing log + within this batch.
    private static let dedupWindow: TimeInterval = 60

    static func merge(
        weightLog: [BodyWeightEntry],
        compositionLog: [BodyCompositionEntry],
        samples rawSamples: [HKBodyMetricSample]
    ) -> (weight: [BodyWeightEntry], composition: [BodyCompositionEntry], summary: BodyMetricsSyncSummary) {
        // Drop physiologically impossible readings before anything else. HK
        // constrains its own writes, but third-party apps can push garbage
        // (a 0 kg weight, a 250% body-fat) into Health that we'd otherwise
        // store verbatim.
        let samples = rawSamples.filter(isPlausible)
        var weight = weightLog
        var composition = compositionLog
        var summary = BodyMetricsSyncSummary(
            addedWeightEntries: 0,
            addedCompositionEntries: 0,
            skippedDuplicateSamples: 0,
            newestSampleAt: nil
        )

        for s in samples {
            if summary.newestSampleAt == nil || s.date > summary.newestSampleAt! {
                summary.newestSampleAt = s.date
            }
        }

        // Weight: one entry per sample, deduped against the growing log (so
        // intra-batch near-duplicates collapse too). Uses the real timestamp.
        for s in samples where s.kind == .bodyMass {
            if isDuplicate(date: s.date, dates: weight.map(\.date)) {
                summary.skippedDuplicateSamples += 1
                continue
            }
            weight.append(BodyWeightEntry(date: s.date, weightKg: s.value, note: "From Health"))
            summary.addedWeightEntries += 1
        }

        // Composition: cluster BF% + lean by PROXIMITY (not a minute floor),
        // so a paired reading that straddles a wall-clock minute boundary
        // still collapses onto one row. The cluster's anchor is the EARLIEST
        // real sample time — preserved on the entry, no flooring.
        for group in clusterComposition(samples) {
            let dates = composition.map(\.date)
            if isDuplicate(date: group.date, dates: dates) {
                summary.skippedDuplicateSamples += 1   // per reading — symmetric with adds
                continue
            }
            composition.append(BodyCompositionEntry(
                date: group.date,
                bodyFatPercent: group.bf,
                leanMassKg: group.lean,
                method: "Health",
                note: nil
            ))
            summary.addedCompositionEntries += 1
        }

        // Sort newest-first so re-renders pick up the imports in time
        // order without depending on append order.
        weight.sort { $0.date > $1.date }
        composition.sort { $0.date > $1.date }
        return (weight, composition, summary)
    }

    /// Greedily group composition samples (BF% + lean) that belong to the
    /// same reading. Samples are sorted by time, then each is folded into the
    /// current group when it's within `pairWindow` AND fills an empty slot
    /// (we never overwrite a BF with a second BF). A sample that can't fold
    /// starts a new group. The group date is its earliest sample's real time.
    private static func clusterComposition(
        _ samples: [HKBodyMetricSample]
    ) -> [(date: Date, bf: Double?, lean: Double?)] {
        let comp = samples
            .filter { $0.kind != .bodyMass }
            .sorted { $0.date < $1.date }
        var groups: [(date: Date, bf: Double?, lean: Double?)] = []
        for s in comp {
            let canFold: Bool = {
                guard let last = groups.last,
                      abs(s.date.timeIntervalSince(last.date)) <= pairWindow else { return false }
                if s.kind == .bodyFatPercent { return last.bf == nil }
                if s.kind == .leanBodyMass   { return last.lean == nil }
                return false
            }()
            if canFold {
                var last = groups[groups.count - 1]
                if s.kind == .bodyFatPercent { last.bf = s.value }
                if s.kind == .leanBodyMass   { last.lean = s.value }
                groups[groups.count - 1] = last
            } else {
                groups.append((
                    date: s.date,
                    bf: s.kind == .bodyFatPercent ? s.value : nil,
                    lean: s.kind == .leanBodyMass ? s.value : nil
                ))
            }
        }
        return groups
    }

    /// True when `date` is within the dedup window of any existing entry date.
    /// Compares REAL timestamps on both sides (no flooring), so a genuine new
    /// reading isn't dropped by a floored bucket landing near an unrelated
    /// entry.
    private static func isDuplicate(date: Date, dates: [Date]) -> Bool {
        dates.contains { abs($0.timeIntervalSince(date)) < dedupWindow }
    }

    /// Reject readings outside plausible human ranges. Body-fat upper bound
    /// (75%) sits above any real value yet still catches a bad 0-1→0-100
    /// double-scale or a junk sample; mass lower bound just rejects 0/negative.
    private static func isPlausible(_ s: HKBodyMetricSample) -> Bool {
        switch s.kind {
        case .bodyMass, .leanBodyMass:
            return s.value > 0
        case .bodyFatPercent:
            return s.value > 0 && s.value <= 75
        }
    }
}
