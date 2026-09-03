// ActivityDetectionStore.swift — app-lifetime owner of the on-open
// Health activity scan (see ActivityDetection.swift for the use case).
//
// Responsibilities:
//   - run the scan when the app becomes active (PhaseTrainingApp's
//     scenePhase hook calls `scan`), silently: no auth dialog, no error UI
//   - hold the pending candidates the Today banner renders
//   - persist which HK workout UUIDs were already confirmed/dismissed so
//     the same outing never re-prompts across launches
//
// Seen-id persistence is a [uuid: epochSeconds] map under
// `pt_detected_activity_seen` (pt_ prefix → covered by the
// MemoryStore.wipeAllUserData prefix sweep). Entries older than 30 days
// are pruned on write — the scan window is 7 days, so anything older can
// never match again.

import Foundation
import Combine

@MainActor
final class ActivityDetectionStore: ObservableObject {
    private static let seenKey = "pt_detected_activity_seen"
    private static let enabledKey = "pt_activity_detection_enabled"
    /// Seen ids older than this can never re-surface (scan window is 7
    /// days), so they're pruned to keep the defaults payload tiny.
    private static let seenRetentionDays = 30.0

    /// Candidates awaiting a confirm/dismiss, newest first. TodayScreen
    /// banners the first one; resolving it promotes the next.
    @Published private(set) var pending: [DetectedActivity] = []

    /// User-facing kill switch (Settings → Health & Imports). Defaults ON —
    /// the feature is inert anyway until Health read access is granted.
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            if !enabled { pending = [] }
        }
    }

    private let importer: HealthKitImporter
    private let defaults: UserDefaults
    /// uuid → epoch seconds of when it was handled.
    private var seen: [String: Double]

    init(importer: HealthKitImporter = HealthKitImporter(),
         defaults: UserDefaults = .standard) {
        self.importer = importer
        self.defaults = defaults
        self.enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.seen = (defaults.dictionary(forKey: Self.seenKey) as? [String: Double]) ?? [:]
    }

    /// Run one detection pass. Safe to call on every foreground — the HK
    /// query is a single 7-day sample read. Errors (auth never requested,
    /// HK unavailable on iPad/simulator) leave `pending` untouched: this
    /// surface must never nag someone who hasn't opted into Health.
    func scan(sportLogs: [SportLogEntry], now: Date = Date()) async {
        guard enabled else { return }
        let raw: [HKWorkoutLike]
        do {
            raw = try await importer.recentRawWorkouts(days: ActivityDetector.windowDays)
        } catch {
            return
        }
        pending = ActivityDetector.detect(
            workouts: raw,
            sportLogs: sportLogs,
            seenIds: Set(seen.keys),
            now: now
        )
    }

    /// Record an outcome (confirmed or dismissed — both mean "asked and
    /// answered") and drop the candidate from `pending`.
    func markHandled(_ activity: DetectedActivity, now: Date = Date()) {
        for uuid in activity.workoutIds {
            seen[uuid] = now.timeIntervalSince1970
        }
        persistSeen(now: now)
        pending.removeAll { $0.id == activity.id }
    }

    /// Drop live state after a full data wipe, mirroring
    /// SportLogStore.reset(): this store is an app-lifetime @StateObject,
    /// so without this the in-memory seen map would outlive the wipe and
    /// the next persist would write it straight back.
    func reset() {
        pending = []
        seen = [:]
        defaults.removeObject(forKey: Self.seenKey)
    }

    /// Test seam: the persisted seen set, so ActivityDetectionStoreTests
    /// can assert dedupe survives a relaunch without poking defaults keys.
    var seenIdsForTesting: Set<String> { Set(seen.keys) }

    private func persistSeen(now: Date) {
        let cutoff = now.timeIntervalSince1970 - Self.seenRetentionDays * 86_400
        seen = seen.filter { $0.value >= cutoff }
        defaults.set(seen, forKey: Self.seenKey)
    }
}
