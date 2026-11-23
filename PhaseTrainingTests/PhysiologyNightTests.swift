// PhysiologyNightTests.swift — 1c capture slice: the pure nightly summariser.
//
// Night attribution at the 18:00 boundary, the HRV overnight window, the
// sleep-stage filter and interval union, resting HR per day, the fetch
// window, the merge that never erases on an empty read, and the store's
// backup round trip. Then the HealthKit sample conversion and the capture
// flow (connect, refresh gating, write-back) against a fake source.

import XCTest
import HealthKit
@testable import PhaseTraining

final class PhysiologyNightTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    /// Monday 2026-10-05, local midnight.
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 5))! }
    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(byAdding: .minute, value: (dayOffset * 24 + hour) * 60 + minute, to: monday)!
    }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: monday)! }
    private func sleep(_ from: Date, _ to: Date, _ stage: PhysiologySleepStage) -> PhysiologySleepSample {
        PhysiologySleepSample(start: from, end: to, stage: stage)
    }
    private func summarise(sleep: [PhysiologySleepSample] = [], hrv: [PhysiologyReading] = [],
                           rhr: [PhysiologyReading] = []) -> [PhysiologyNight] {
        PhysiologySummariser.summarise(sleep: sleep, hrv: hrv, restingHR: rhr, calendar: cal)
    }

    // MARK: - Sleep stages

    func test_stageRawValues_matchHealthKit() {
        XCTAssertEqual(PhysiologySleepStage(healthKitValue: 0), .inBed)
        XCTAssertEqual(PhysiologySleepStage(healthKitValue: 1), .asleepUnspecified, "also the legacy .asleep")
        XCTAssertEqual(PhysiologySleepStage(healthKitValue: 2), .awake)
        XCTAssertEqual(PhysiologySleepStage(healthKitValue: 3), .asleepCore)
        XCTAssertEqual(PhysiologySleepStage(healthKitValue: 4), .asleepDeep)
        XCTAssertEqual(PhysiologySleepStage(healthKitValue: 5), .asleepREM)
        XCTAssertNil(PhysiologySleepStage(healthKitValue: 99))
    }

    func test_sleep_sumsAsleepStages_excludesInBedAndAwake() {
        // Sunday night into Monday: in bed 22:30 to 06:45, stages inside it.
        let nights = summarise(sleep: [
            sleep(at(-1, 22, 30), at(0, 6, 45), .inBed),
            sleep(at(-1, 23, 0), at(0, 1, 0), .asleepCore),   // 120
            sleep(at(0, 1, 0), at(0, 2, 0), .asleepDeep),     // 60
            sleep(at(0, 2, 0), at(0, 2, 20), .awake),
            sleep(at(0, 2, 20), at(0, 4, 0), .asleepREM),     // 100
            sleep(at(0, 4, 0), at(0, 6, 30), .asleepUnspecified), // 150
        ])
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].date, day(0), "keyed by the wake day")
        XCTAssertEqual(nights[0].asleepMinutes!, 430, accuracy: 0.001)
        XCTAssertEqual(nights[0].sleepSamples, 4)
        XCTAssertNil(nights[0].hrvMs)
        XCTAssertNil(nights[0].restingHR)
    }

    func test_sleep_overlappingSources_countOnce() {
        // Watch stages and a phone "asleep" for the same hours.
        let nights = summarise(sleep: [
            sleep(at(-1, 23, 0), at(0, 3, 0), .asleepCore),
            sleep(at(0, 3, 0), at(0, 7, 0), .asleepDeep),
            sleep(at(-1, 23, 30), at(0, 6, 0), .asleepUnspecified),
        ])
        XCTAssertEqual(nights[0].asleepMinutes!, 480, accuracy: 0.001)
        XCTAssertEqual(nights[0].sleepSamples, 3)
    }

    func test_sleep_eveningBoundary() {
        // A segment ending 23:40 belongs to the next morning; a 14:00 nap to
        // that same day; one ending exactly 18:00 to the next day.
        XCTAssertEqual(PhysiologySummariser.nightDate(forSleepEnd: at(0, 23, 40), calendar: cal), day(1))
        XCTAssertEqual(PhysiologySummariser.nightDate(forSleepEnd: at(0, 15, 0), calendar: cal), day(0))
        XCTAssertEqual(PhysiologySummariser.nightDate(forSleepEnd: at(0, 17, 59), calendar: cal), day(0))
        XCTAssertEqual(PhysiologySummariser.nightDate(forSleepEnd: at(0, 18, 0), calendar: cal), day(1))

        let nights = summarise(sleep: [
            sleep(at(0, 22, 15), at(0, 23, 40), .asleepCore),
            sleep(at(1, 0, 10), at(1, 6, 10), .asleepCore),
        ])
        XCTAssertEqual(nights.map(\.date), [day(1)], "a split night is still one night")
        XCTAssertEqual(nights[0].asleepMinutes!, 85 + 360, accuracy: 0.001)
    }

    func test_inBedOnly_night_hasNoSleepRecord() {
        XCTAssertEqual(summarise(sleep: [sleep(at(-1, 23, 0), at(0, 7, 0), .inBed)]), [])
    }

    // MARK: - HRV

    func test_hrv_meanOfOvernightWindow_dropsDaytime() {
        let nights = summarise(hrv: [
            PhysiologyReading(date: at(-1, 18, 0), value: 40),  // window opens
            PhysiologyReading(date: at(0, 3, 0), value: 60),
            PhysiologyReading(date: at(0, 11, 59), value: 50),  // window closes 12:00
            PhysiologyReading(date: at(0, 12, 0), value: 999),  // daytime
            PhysiologyReading(date: at(0, 16, 0), value: 999),  // daytime
            PhysiologyReading(date: at(0, 20, 0), value: 70),   // next night
        ])
        XCTAssertEqual(nights.map(\.date), [day(0), day(1)])
        XCTAssertEqual(nights[0].hrvMs!, 50, accuracy: 0.001)
        XCTAssertEqual(nights[0].hrvSamples, 3)
        XCTAssertEqual(nights[1].hrvMs!, 70, accuracy: 0.001)
        XCTAssertEqual(nights[1].hrvSamples, 1)
    }

    func test_nonPositiveReadings_areIgnored() {
        let nights = summarise(hrv: [PhysiologyReading(date: at(0, 3), value: 0)],
                               rhr: [PhysiologyReading(date: at(0, 8), value: -1)])
        XCTAssertEqual(nights, [])
    }

    // MARK: - Resting HR and the joined record

    func test_restingHR_perCalendarDay_joinsTheNight() {
        let nights = summarise(
            sleep: [sleep(at(-1, 23), at(0, 7), .asleepCore)],
            hrv: [PhysiologyReading(date: at(0, 4), value: 55)],
            rhr: [PhysiologyReading(date: at(0, 9), value: 52),
                  PhysiologyReading(date: at(0, 21), value: 54),
                  PhysiologyReading(date: at(1, 9), value: 58)])
        XCTAssertEqual(nights.map(\.date), [day(0), day(1)])
        let mon = nights[0]
        XCTAssertEqual(mon.restingHR!, 53, accuracy: 0.001)
        XCTAssertEqual(mon.restingHRSamples, 2)
        XCTAssertEqual(mon.hrvMs!, 55, accuracy: 0.001)
        XCTAssertEqual(mon.asleepMinutes!, 480, accuracy: 0.001)
        XCTAssertNil(nights[1].asleepMinutes)
        XCTAssertEqual(nights[1].restingHR!, 58, accuracy: 0.001)
    }

    // MARK: - Fetch window

    func test_fetchWindow_firstRunReadsThirtyNights_fromTheEveningBefore() {
        let now = at(0, 9)
        let w = PhysiologySummariser.fetchWindow(lastStoredNight: nil, now: now, calendar: cal)
        XCTAssertEqual(w.firstNight, day(-30))
        XCTAssertEqual(w.queryStart, at(-31, 18))
    }

    func test_fetchWindow_incremental_rereadsLastStoredNight_capped() {
        let now = at(0, 9)
        XCTAssertEqual(PhysiologySummariser.fetchWindow(lastStoredNight: day(-2), now: now, calendar: cal).firstNight, day(-2))
        XCTAssertEqual(PhysiologySummariser.fetchWindow(lastStoredNight: day(0), now: now, calendar: cal).firstNight, day(0))
        XCTAssertEqual(PhysiologySummariser.fetchWindow(lastStoredNight: day(-400), now: now, calendar: cal).firstNight, day(-90))
    }

    // MARK: - Merge

    private func n(_ d: Int, hrv: Double? = nil) -> PhysiologyNight {
        PhysiologyNight(date: day(d), hrvMs: hrv, hrvSamples: hrv == nil ? 0 : 1, restingHR: nil,
                        restingHRSamples: 0, asleepMinutes: nil, sleepSamples: 0)
    }

    func test_merge_freshReplacesSameDate_keepsOthers_dropsPartialFirstNight() {
        let existing = [n(-3, hrv: 40), n(-1, hrv: 41)]
        let fresh = [n(-2, hrv: 99), n(-1, hrv: 50), n(0, hrv: 60)]
        let merged = PhysiologySummariser.merge(existing: existing, fresh: fresh, firstNight: day(-1),
                                                now: at(0, 9), calendar: cal)
        XCTAssertEqual(merged.map(\.date), [day(-3), day(-1), day(0)],
                       "a fresh night before the window start was only partly read")
        XCTAssertEqual(merged.map(\.hrvMs), [40, 50, 60])
    }

    func test_merge_emptyRead_neverErases_andPrunesPastRetention() {
        let existing = [n(-400, hrv: 30), n(-1, hrv: 41)]
        let merged = PhysiologySummariser.merge(existing: existing, fresh: [], firstNight: day(-1),
                                                now: at(0, 9), calendar: cal)
        XCTAssertEqual(merged.map(\.date), [day(-1)])
    }

    // MARK: - Summary, store and backup

    func test_captureSummary_countsEachSignal() {
        var a = n(-2, hrv: 50); a.asleepMinutes = 420; a.sleepSamples = 3
        var b = n(-1); b.restingHR = 52; b.restingHRSamples = 1
        let s = PhysiologyCaptureSummary.make([a, b])
        XCTAssertEqual(s, PhysiologyCaptureSummary(nights: 2, lastNight: day(-1), daysWithHRV: 1,
                                                   daysWithRestingHR: 1, daysWithSleep: 1))
        XCTAssertEqual(PhysiologyCaptureSummary.make([]).nights, 0)
    }

    func test_store_roundTrips_andBackupCarriesNights() throws {
        let suite = "PhysiologyNightTests.store"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PhysiologyStore(defaults: defaults)
        XCTAssertFalse(store.isEnabled)
        store.isEnabled = true
        store.saveNights([n(-1, hrv: 41)])
        XCTAssertEqual(store.loadNights(), [n(-1, hrv: 41)])

        let envelope = try BackupManager.decode(
            BackupManager.encode(BackupManager.snapshot(defaults: defaults, userDB: UserDatabase(path: ":memory:"))))
        XCTAssertEqual(envelope.physiologyNights, [n(-1, hrv: 41)])

        let restoredSuite = "PhysiologyNightTests.restored"
        let restored = UserDefaults(suiteName: restoredSuite)!
        restored.removePersistentDomain(forName: restoredSuite)
        try BackupManager.restore(envelope, into: restored, userDB: UserDatabase(path: ":memory:"))
        XCTAssertEqual(PhysiologyStore(defaults: restored).loadNights(), [n(-1, hrv: 41)])
        XCTAssertFalse(PhysiologyStore(defaults: restored).isEnabled, "the grant is per device")

        store.stopAndDelete()
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.loadNights(), [])
    }

    func test_wipe_clearsPhysiologyKeys() {
        let suite = "PhysiologyNightTests.wipe"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PhysiologyStore(defaults: defaults)
        store.isEnabled = true
        store.saveNights([n(-1, hrv: 41)])
        store.lastRefresh = at(0, 9)
        MemoryStore.wipeAllUserData(defaults: defaults, userDB: UserDatabase(path: ":memory:"))
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.loadNights(), [])
        XCTAssertNil(store.lastRefresh)
    }

    // MARK: - HealthKit conversion

    func test_readings_hrvSecondsReadBackAsMilliseconds() throws {
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        let start = at(0, 3)
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .second(), doubleValue: 0.045),
                                      start: start, end: start)
        let out = PhysiologyReader.readings([sample], unit: HKUnit.secondUnit(with: .milli))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].value, 45, accuracy: 1e-9)
        XCTAssertEqual(out[0].date, start)
    }

    func test_readings_restingHRPerSecondReadsBackPerMinute() throws {
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .restingHeartRate))
        let perSecond = HKUnit.count().unitDivided(by: .second())
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: perSecond, doubleValue: 1),
                                      start: at(0, 7), end: at(0, 7))
        let out = PhysiologyReader.readings([sample], unit: HKUnit.count().unitDivided(by: HKUnit.minute()))
        XCTAssertEqual(out.map(\.value), [60])
    }

    /// HealthKit refuses to build a sleepAnalysis sample with a raw value it
    /// does not define (_HKObjectValidationFailureException for 99), so the
    /// drop of an unknown value is checked at the stage mapping the
    /// conversion's compactMap guards on.
    func test_sleepSamples_mapsEachStage_dropsUnknownRawValue() throws {
        XCTAssertNil(PhysiologySleepStage(healthKitValue: 99), "an unknown raw value has no stage")
        let type = try XCTUnwrap(HKCategoryType.categoryType(forIdentifier: .sleepAnalysis))
        let raws = [0, 1, 2, 3, 4, 5]
        let samples = raws.enumerated().map { i, raw in
            HKCategorySample(type: type, value: raw, start: at(0, i), end: at(0, i, 30))
        }
        let out = PhysiologyReader.sleepSamples(samples)
        XCTAssertEqual(out, [
            sleep(at(0, 0), at(0, 0, 30), .inBed),
            sleep(at(0, 1), at(0, 1, 30), .asleepUnspecified),
            sleep(at(0, 2), at(0, 2, 30), .awake),
            sleep(at(0, 3), at(0, 3, 30), .asleepCore),
            sleep(at(0, 4), at(0, 4, 30), .asleepDeep),
            sleep(at(0, 5), at(0, 5, 30), .asleepREM),
        ], "inBed and awake keep their stage; start and end carry through")
    }

    // MARK: - Capture

    private final class FakeSource: PhysiologySource {
        var auth: Result<Bool, Error> = .success(true)
        var read: Result<PhysiologyRawSamples, Error> = .success(PhysiologyRawSamples(sleep: [], hrv: [], restingHR: []))
        var duringRead: (() -> Void)?
        private(set) var authCalls = 0
        private(set) var reads: [(start: Date, end: Date)] = []

        func requestAuthorization() async throws -> Bool {
            authCalls += 1
            return try auth.get()
        }

        func samples(from start: Date, to end: Date) async throws -> PhysiologyRawSamples {
            reads.append((start, end))
            duringRead?()
            return try read.get()
        }
    }

    private struct AuthError: LocalizedError {
        var errorDescription: String? { "Health access was refused." }
    }

    private struct ReadError: Error {}

    private var suites: [String] = []

    override func tearDown() {
        for s in suites { UserDefaults().removePersistentDomain(forName: s) }
        suites = []
        super.tearDown()
    }

    private func freshStore() -> PhysiologyStore {
        let suite = "PhysiologyNightTests.capture.\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PhysiologyStore(defaults: defaults)
    }

    /// One overnight HRV reading (02:00) on each of the `nights` days before
    /// `now`, on the calendar the summariser defaults to.
    private func hrvSamples(nights: Int, before now: Date) -> PhysiologyRawSamples {
        let c = Calendar.current
        let today = c.startOfDay(for: now)
        let hrv = (1...nights).map { k -> PhysiologyReading in
            let d = c.date(byAdding: .day, value: -k, to: today)!
            return PhysiologyReading(date: c.date(byAdding: .hour, value: 2, to: d)!, value: 40 + Double(k))
        }
        return PhysiologyRawSamples(sleep: [], hrv: hrv, restingHR: [])
    }

    @MainActor
    func test_connect_unavailable_staysOff_andNeverReads() async {
        let store = freshStore()
        let source = FakeSource()
        source.auth = .success(false)
        let result = await PhysiologyCapture.connect(store: store, source: source)
        XCTAssertEqual(result, .unavailable)
        XCTAssertFalse(store.isEnabled)
        XCTAssertTrue(source.reads.isEmpty)
        XCTAssertNil(store.lastRefresh)
    }

    @MainActor
    func test_connect_authThrows_failsWithItsDescription_andStaysOff() async {
        let store = freshStore()
        let source = FakeSource()
        source.auth = .failure(AuthError())
        let result = await PhysiologyCapture.connect(store: store, source: source)
        XCTAssertEqual(result, .failed("Health access was refused."))
        XCTAssertFalse(store.isEnabled)
        XCTAssertTrue(source.reads.isEmpty)
    }

    @MainActor
    func test_connect_success_turnsOn_readsOnce_andSavesNights() async throws {
        let store = freshStore()
        let source = FakeSource()
        let before = Date()
        source.read = .success(hrvSamples(nights: 3, before: before))
        let result = await PhysiologyCapture.connect(store: store, source: source)
        let after = Date()
        XCTAssertEqual(result, .connected(nights: 3))
        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(source.authCalls, 1)
        XCTAssertEqual(source.reads.count, 1)
        XCTAssertEqual(store.loadNights().count, 3)
        let last = try XCTUnwrap(store.lastRefresh)
        XCTAssertGreaterThanOrEqual(last.timeIntervalSince1970, before.timeIntervalSince1970.rounded(.down))
        XCTAssertLessThanOrEqual(last.timeIntervalSince1970, after.timeIntervalSince1970.rounded(.up))
    }

    @MainActor
    func test_refresh_whileDisabled_neverCallsSource() async {
        let store = freshStore()
        let source = FakeSource()
        await PhysiologyCapture.refreshIfEnabled(store: store, source: source, now: Date(), force: true)
        XCTAssertTrue(source.reads.isEmpty)
        XCTAssertEqual(source.authCalls, 0)
        XCTAssertNil(store.lastRefresh)
    }

    @MainActor
    func test_refresh_withinInterval_skips_forceReads_afterIntervalReads() async {
        let store = freshStore()
        let source = FakeSource()
        store.isEnabled = true
        let last = Date(timeIntervalSince1970: 1_790_000_000)
        store.lastRefresh = last

        let soon = last.addingTimeInterval(PhysiologyCapture.minRefreshInterval - 1)
        await PhysiologyCapture.refreshIfEnabled(store: store, source: source, now: soon)
        XCTAssertTrue(source.reads.isEmpty, "inside the interval a refresh is skipped")
        XCTAssertEqual(store.lastRefresh, last)

        await PhysiologyCapture.refreshIfEnabled(store: store, source: source, now: soon, force: true)
        XCTAssertEqual(source.reads.count, 1, "force reads inside the interval")
        XCTAssertEqual(source.reads.last?.end, soon)
        XCTAssertEqual(store.lastRefresh, soon)

        let later = soon.addingTimeInterval(PhysiologyCapture.minRefreshInterval)
        await PhysiologyCapture.refreshIfEnabled(store: store, source: source, now: later)
        XCTAssertEqual(source.reads.count, 2, "a full interval after the last refresh reads")
        XCTAssertEqual(store.lastRefresh, later)
    }

    @MainActor
    func test_refresh_readThrows_leavesNightsAndLastRefresh() async {
        let store = freshStore()
        let source = FakeSource()
        store.isEnabled = true
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
        let stored = hrvSamples(nights: 2, before: now)
        let nights = PhysiologySummariser.summarise(sleep: [], hrv: stored.hrv, restingHR: [])
        store.saveNights(nights)
        let last = now.addingTimeInterval(-2 * PhysiologyCapture.minRefreshInterval)
        store.lastRefresh = last
        source.read = .failure(ReadError())

        await PhysiologyCapture.refreshIfEnabled(store: store, source: source, now: now)
        XCTAssertEqual(source.reads.count, 1)
        XCTAssertEqual(store.loadNights(), nights)
        XCTAssertEqual(store.lastRefresh, last)
        XCTAssertTrue(store.isEnabled)
    }

    @MainActor
    func test_refresh_stopAndDeleteDuringRead_writesNothingBack() async {
        let store = freshStore()
        let source = FakeSource()
        store.isEnabled = true
        let now = Date()
        source.read = .success(hrvSamples(nights: 3, before: now))
        source.duringRead = { store.stopAndDelete() }

        await PhysiologyCapture.refreshIfEnabled(store: store, source: source, now: now, force: true)
        XCTAssertEqual(source.reads.count, 1)
        XCTAssertEqual(store.loadNights(), [])
        XCTAssertNil(store.lastRefresh)
        XCTAssertFalse(store.isEnabled)
    }

    // MARK: - Recovery capture pre-prompt

    func test_recoveryPrePrompt_freshShows() {
        let suite = "PhysiologyNightTests.prePrompt"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(RecoveryCapturePrePrompt.shouldOffer(captureEnabled: false, defaults: d))
    }

    func test_recoveryPrePrompt_enabledHides() {
        let suite = "PhysiologyNightTests.prePrompt"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(RecoveryCapturePrePrompt.shouldOffer(captureEnabled: true, defaults: d))
    }

    func test_recoveryPrePrompt_answeredHides() {
        let suite = "PhysiologyNightTests.prePrompt"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        RecoveryCapturePrePrompt.markAnswered(defaults: d)
        XCTAssertFalse(RecoveryCapturePrePrompt.shouldOffer(captureEnabled: false, defaults: d))
    }
}
