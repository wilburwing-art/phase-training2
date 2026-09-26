// PhysiologyReader.swift — the HealthKit side of physiology capture (1c
// capture slice, build 145). PhysiologyNight.swift holds the pure summariser.
//
// Three read types: heartRateVariabilitySDNN, restingHeartRate and
// sleepAnalysis. Their grant is SEPARATE from the workout-import and
// body-metrics grants and is requested only from the "Capture recovery data"
// tap in Health & Imports (PhysiologyCaptureSection). Never at launch, never
// in onboarding.
//
// After that tap, `PhysiologyCapture.refreshIfEnabled` runs on each app
// foreground (at most hourly). It never prompts: HealthKit shows the
// permission sheet only from requestAuthorization, and a sample query for a
// type the user declined just comes back empty.
//
// Nothing read here leaves the device. The nightly summaries are stored
// under `pt_physiology_nights` and are NOT part of the AI Coach snapshot in
// this build (see docs/privacy.md).

import Foundation
import HealthKit

struct PhysiologyRawSamples: Sendable {
    var sleep: [PhysiologySleepSample]
    var hrv: [PhysiologyReading]
    var restingHR: [PhysiologyReading]
}

enum PhysiologyReader {

    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }
        return types
    }

    /// Shows the Health permission sheet for the three types (once; later
    /// calls are no-ops). Read-only, empty share set. Returns false when
    /// Health is unavailable on this device.
    static func requestAuthorization(store: HKHealthStore = HKHealthStore()) async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let types = readTypes
        guard !types.isEmpty else { return false }
        try await store.requestAuthorization(toShare: [], read: types)
        return true
    }

    /// Every sample of the three types that overlaps [start, end].
    static func samples(from start: Date, to end: Date,
                        store: HKHealthStore = HKHealthStore()) async throws -> PhysiologyRawSamples {
        guard HKHealthStore.isHealthDataAvailable() else {
            return PhysiologyRawSamples(sleep: [], hrv: [], restingHR: [])
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        var hrv: [PhysiologyReading] = []
        var rhr: [PhysiologyReading] = []
        var sleep: [PhysiologySleepSample] = []
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            hrv = try await quantities(t, unit: HKUnit.secondUnit(with: .milli),
                                       predicate: predicate, store: store)
        }
        if let t = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            rhr = try await quantities(t, unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                                       predicate: predicate, store: store)
        }
        if let t = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            sleep = try await sleepSamples(t, predicate: predicate, store: store)
        }
        return PhysiologyRawSamples(sleep: sleep, hrv: hrv, restingHR: rhr)
    }

    private static func quantities(_ type: HKQuantityType, unit: HKUnit,
                                   predicate: NSPredicate,
                                   store: HKHealthStore) async throws -> [PhysiologyReading] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let out = (samples as? [HKQuantitySample] ?? []).map {
                    PhysiologyReading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private static func sleepSamples(_ type: HKCategoryType, predicate: NSPredicate,
                                     store: HKHealthStore) async throws -> [PhysiologySleepSample] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let out: [PhysiologySleepSample] = (samples as? [HKCategorySample] ?? []).compactMap { s in
                    guard let stage = PhysiologySleepStage(healthKitValue: s.value) else { return nil }
                    return PhysiologySleepSample(start: s.startDate, end: s.endDate, stage: stage)
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }
}

// MARK: - Store

/// On-device persistence. No in-memory cache: every read goes to defaults, so
/// the `pt_` prefix sweep in `MemoryStore.wipeAllUserData` and a backup
/// restore both take effect with nothing live to reset or reload.
struct PhysiologyStore {
    static let nightsKey = "pt_physiology_nights"
    /// Set by the user's tap. Foreground refreshes run only while true.
    static let enabledKey = "pt_physiology_enabled"
    static let lastRefreshKey = "pt_physiology_last_refresh"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var lastRefresh: Date? {
        get { (defaults.object(forKey: Self.lastRefreshKey) as? Double).map(Date.init(timeIntervalSince1970:)) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: Self.lastRefreshKey)
            } else {
                defaults.removeObject(forKey: Self.lastRefreshKey)
            }
        }
    }

    /// Oldest first.
    func loadNights() -> [PhysiologyNight] {
        guard let data = defaults.data(forKey: Self.nightsKey) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return (try? d.decode([PhysiologyNight].self, from: data)) ?? []
    }

    /// Same date strategy as BackupManager, which decodes this key directly.
    func saveNights(_ nights: [PhysiologyNight]) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        if let data = try? e.encode(nights) { defaults.set(data, forKey: Self.nightsKey) }
    }

    /// "Stop and delete": turn capture off and drop everything stored.
    func stopAndDelete() {
        defaults.removeObject(forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.nightsKey)
        defaults.removeObject(forKey: Self.lastRefreshKey)
    }
}

// MARK: - Capture

enum PhysiologyConnectResult: Equatable {
    case connected(nights: Int)
    case unavailable
    case failed(String)
}

@MainActor
enum PhysiologyCapture {
    /// Foreground refreshes closer together than this are skipped.
    static let minRefreshInterval: TimeInterval = 3600
    private static var inFlight = false

    /// The user's tap: show the permission sheet, mark capture on, and read
    /// the first 30 nights.
    static func connect(store: PhysiologyStore = PhysiologyStore()) async -> PhysiologyConnectResult {
        do {
            guard try await PhysiologyReader.requestAuthorization() else { return .unavailable }
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        store.isEnabled = true
        await refreshIfEnabled(store: store, force: true)
        return .connected(nights: store.loadNights().count)
    }

    /// Silent refresh. No-op unless the user turned capture on; never
    /// prompts; errors leave the stored nights as they were.
    static func refreshIfEnabled(store: PhysiologyStore = PhysiologyStore(),
                                 now: Date = Date(), force: Bool = false) async {
        guard store.isEnabled, !inFlight else { return }
        if !force, let last = store.lastRefresh, now.timeIntervalSince(last) < minRefreshInterval { return }
        inFlight = true
        defer { inFlight = false }

        let window = PhysiologySummariser.fetchWindow(lastStoredNight: store.loadNights().last?.date, now: now)
        let raw: PhysiologyRawSamples
        do {
            raw = try await PhysiologyReader.samples(from: window.queryStart, to: now)
        } catch {
            return
        }
        // Re-check after the await: an erase or "stop and delete" while the
        // read was in flight must not be written back over.
        guard store.isEnabled else { return }
        let fresh = PhysiologySummariser.summarise(sleep: raw.sleep, hrv: raw.hrv, restingHR: raw.restingHR)
        store.saveNights(PhysiologySummariser.merge(existing: store.loadNights(), fresh: fresh,
                                                    firstNight: window.firstNight, now: now))
        store.lastRefresh = now
    }
}
