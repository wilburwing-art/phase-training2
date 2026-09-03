// ActivityDetectionStore.swift — app-lifetime owner of the on-open
// Health activity scan (see ActivityDetection.swift for the use case).
//
// Responsibilities:
//   - run the scan when the app becomes active (PhaseTrainingApp's
//     scenePhase hook calls `scan`), silently: no auth dialog, no error UI
//   - hold the pending candidates the Today banner renders
//   - persist which HK workout UUIDs were already confirmed/dismissed so
//     the same outing never re-prompts across launches
//   - persist a (day, sport) tombstone per DISMISSED outing, so a
//     fragment of that outing that syncs into Health later (fresh UUID,
//     same morning) can't resurrect a banner the user said "Not me" to
//
// Both maps persist as [key: epochSeconds] under pt_-prefixed keys
// (covered by the MemoryStore.wipeAllUserData prefix sweep). Entries
// older than 30 days are pruned on write — the scan window is 7 days,
// so anything older can never match again.

import Foundation
import Combine

@MainActor
final class ActivityDetectionStore: ObservableObject {
    private static let seenKey = "pt_detected_activity_seen"
    private static let dismissedKey = "pt_detected_activity_dismissed"
    private static let enabledKey = "pt_activity_detection_enabled"
    /// Entries older than this can never re-surface (scan window is 7
    /// days), so they're pruned to keep the defaults payload tiny.
    private static let retentionDays = 30.0

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
    /// HK workout uuid → epoch seconds of when it was handled.
    private var seen: [String: Double]
    /// DetectedActivity.outingKey → epoch seconds of when it was dismissed.
    private var dismissed: [String: Double]

    init(importer: HealthKitImporter = HealthKitImporter(),
         defaults: UserDefaults = .standard) {
        self.importer = importer
        self.defaults = defaults
        self.enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.seen = (defaults.dictionary(forKey: Self.seenKey) as? [String: Double]) ?? [:]
        self.dismissed = (defaults.dictionary(forKey: Self.dismissedKey) as? [String: Double]) ?? [:]
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
            dismissedOutingKeys: Set(dismissed.keys),
            now: now
        )
    }

    /// Record a CONFIRMED outing. Marks its workout ids seen and drops
    /// every pending candidate on the same calendar day — the confirm just
    /// wrote a SportLogEntry for that day, and detect()'s own rule is that
    /// a day with a sport log never prompts, so a second same-day
    /// candidate (ski + hike on one Saturday) must not survive to
    /// double-log the day. The other candidates' ids are NOT marked seen;
    /// the sport-log exclusion covers them on every future scan.
    func markConfirmed(_ activity: DetectedActivity, now: Date = Date()) {
        for uuid in activity.workoutIds {
            seen[uuid] = now.timeIntervalSince1970
        }
        persist(now: now)
        pending.removeAll { Calendar.current.isDate($0.day, inSameDayAs: activity.day) }
    }

    /// Record a DISMISSED ("Not me") outing. Marks its workout ids seen
    /// AND tombstones the (day, sport) outing key, so a late-syncing
    /// fragment of the same outing — fresh UUID, clears the duration
    /// floor on its own — can't re-prompt what the user rejected. Only
    /// this outing leaves `pending`: a different same-day candidate might
    /// be the one the user actually wants to confirm.
    func markDismissed(_ activity: DetectedActivity, now: Date = Date()) {
        for uuid in activity.workoutIds {
            seen[uuid] = now.timeIntervalSince1970
        }
        dismissed[activity.outingKey] = now.timeIntervalSince1970
        persist(now: now)
        pending.removeAll { $0.id == activity.id }
    }

    /// Drop live state after a full data wipe, mirroring
    /// SportLogStore.reset(): this store is an app-lifetime @StateObject,
    /// so without this the in-memory maps would outlive the wipe and the
    /// next persist would write them straight back.
    func reset() {
        pending = []
        seen = [:]
        dismissed = [:]
        defaults.removeObject(forKey: Self.seenKey)
        defaults.removeObject(forKey: Self.dismissedKey)
        // Restore the fresh-install default too — the wipe swept the
        // backing key, and a live `false` here would leave detection
        // silently off (and the Settings toggle showing OFF) until the
        // next cold launch re-read the missing key as true. didSet
        // re-persists `true`, which matches missing-key semantics.
        if !enabled { enabled = true }
    }

    /// Test seam: the persisted seen set, so ActivityDetectionStoreTests
    /// can assert dedupe survives a relaunch without poking defaults keys.
    var seenIdsForTesting: Set<String> { Set(seen.keys) }

    /// Test seam: the persisted dismissed-outing tombstones.
    var dismissedOutingKeysForTesting: Set<String> { Set(dismissed.keys) }

    private func persist(now: Date) {
        let cutoff = now.timeIntervalSince1970 - Self.retentionDays * 86_400
        seen = seen.filter { $0.value >= cutoff }
        dismissed = dismissed.filter { $0.value >= cutoff }
        defaults.set(seen, forKey: Self.seenKey)
        defaults.set(dismissed, forKey: Self.dismissedKey)
    }
}
