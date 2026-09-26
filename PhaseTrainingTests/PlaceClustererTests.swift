// PlaceClustererTests.swift — 3c capture slice: coarse session-start points.
//
// Covers the ~100 m rounding, PlaceClusterer (radius boundary, centroid,
// counts, first/last seen, accuracy filter, determinism under reordering),
// PlanStore's log (dedupe, 365-day trim, persistence, restore reload, clear),
// the backup round trip, and SessionStore.onSessionStarted firing only for a
// new session.

import XCTest
@testable import PhaseTraining

final class PlaceClustererTests: XCTestCase {

    // MARK: - Fixtures

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21

    /// A gym in Boulder, and a crag about 1.6 km away.
    private let gym = (lat: 40.015, lon: -105.270)
    private let crag = (lat: 40.000, lon: -105.265)

    /// Meters of latitude per degree, close enough for fixture offsets.
    private let metersPerDegreeLat = 111_195.0

    private func pt(_ i: Int, lat: Double, lon: Double, acc: Double = 65,
                    at hours: Double? = nil) -> SessionPlacePoint {
        let when = t0.addingTimeInterval((hours ?? Double(i) * 24) * 3600)
        return SessionPlacePoint(sessionId: when.timeIntervalSince1970, capturedAt: when,
                                 latitude: lat, longitude: lon, horizontalAccuracy: acc)
    }

    private func freshDefaults(_ suite: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "PlaceClustererTests.\(suite)")!
        d.removePersistentDomain(forName: "PlaceClustererTests.\(suite)")
        return d
    }

    // MARK: - Rounding

    func test_coarse_roundsToThreeDecimals() {
        let p = SessionPlacePoint.coarse(sessionId: 1, capturedAt: t0,
                                         latitude: 40.0154321, longitude: -105.2706789,
                                         horizontalAccuracy: 64.7)
        XCTAssertEqual(p.latitude, 40.015, accuracy: 1e-9)
        XCTAssertEqual(p.longitude, -105.271, accuracy: 1e-9)
        XCTAssertEqual(p.horizontalAccuracy, 65)
        XCTAssertEqual(p.id, 1, "the id is the session id")
    }

    // MARK: - Haversine

    func test_haversine_oneThousandthDegreeLatIsAbout111m() {
        let d = PlaceClusterer.haversineMeters(lat1: 40.000, lon1: -105, lat2: 40.001, lon2: -105)
        XCTAssertEqual(d, 111.2, accuracy: 0.5)
        XCTAssertEqual(PlaceClusterer.haversineMeters(lat1: 1, lon1: 2, lat2: 1, lon2: 2), 0)
    }

    // MARK: - Clustering

    func test_empty_givesNoPlaces() {
        XCTAssertTrue(PlaceClusterer.cluster([]).isEmpty)
    }

    func test_pointsWithinRadius_formOnePlace_withCountsAndSeenDates() {
        let points = [
            pt(0, lat: gym.lat, lon: gym.lon),
            pt(1, lat: gym.lat + 0.001, lon: gym.lon),          // ~111 m north
            pt(2, lat: gym.lat, lon: gym.lon + 0.001),          // ~85 m east
        ]
        let places = PlaceClusterer.cluster(points)
        XCTAssertEqual(places.count, 1)
        let p = places[0]
        XCTAssertEqual(p.visitCount, 3)
        XCTAssertEqual(p.firstSeen, points[0].capturedAt)
        XCTAssertEqual(p.lastSeen, points[2].capturedAt)
        XCTAssertEqual(p.sessionIds, points.map(\.sessionId))
        XCTAssertEqual(p.latitude, gym.lat + 0.001 / 3, accuracy: 1e-9, "centroid is the mean")
        XCTAssertEqual(p.longitude, gym.lon + 0.001 / 3, accuracy: 1e-9)
    }

    func test_radiusBoundary() {
        // 140 m apart joins; 170 m apart does not.
        let near = [pt(0, lat: gym.lat, lon: gym.lon),
                    pt(1, lat: gym.lat + 140 / metersPerDegreeLat, lon: gym.lon)]
        XCTAssertEqual(PlaceClusterer.cluster(near).count, 1)
        let far = [pt(0, lat: gym.lat, lon: gym.lon),
                   pt(1, lat: gym.lat + 170 / metersPerDegreeLat, lon: gym.lon)]
        XCTAssertEqual(PlaceClusterer.cluster(far).count, 2)
    }

    func test_twoPlaces_mostVisitedFirst_idsInOrder() {
        let points = [
            pt(0, lat: crag.lat, lon: crag.lon),
            pt(1, lat: gym.lat, lon: gym.lon),
            pt(2, lat: gym.lat, lon: gym.lon),
            pt(3, lat: crag.lat + 0.001, lon: crag.lon),
            pt(4, lat: gym.lat, lon: gym.lon + 0.001),
        ]
        let places = PlaceClusterer.cluster(points)
        XCTAssertEqual(places.map(\.visitCount), [3, 2])
        XCTAssertEqual(places.map(\.id), [0, 1])
        XCTAssertEqual(places[0].latitude, gym.lat, accuracy: 0.001)
        XCTAssertEqual(places[1].latitude, crag.lat, accuracy: 0.001)
    }

    func test_tie_olderPlaceFirst() {
        let points = [pt(0, lat: crag.lat, lon: crag.lon), pt(1, lat: gym.lat, lon: gym.lon)]
        let places = PlaceClusterer.cluster(points)
        XCTAssertEqual(places.map(\.visitCount), [1, 1])
        XCTAssertEqual(places[0].latitude, crag.lat, "equal counts: first seen wins")
    }

    func test_vagueOrInvalidFixes_areSkipped() {
        let points = [
            pt(0, lat: gym.lat, lon: gym.lon),
            pt(1, lat: gym.lat, lon: gym.lon, acc: 3_000),  // iOS approximate location
            pt(2, lat: crag.lat, lon: crag.lon, acc: -1),   // invalid
        ]
        let places = PlaceClusterer.cluster(points)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].visitCount, 1)
    }

    func test_deterministic_underInputOrder() {
        let points = (0..<12).map { i in
            i % 3 == 0 ? pt(i, lat: crag.lat, lon: crag.lon)
                       : pt(i, lat: gym.lat + Double(i % 2) * 0.001, lon: gym.lon)
        }
        let a = PlaceClusterer.cluster(points)
        let b = PlaceClusterer.cluster(points.reversed())
        let c = PlaceClusterer.cluster(points.shuffled())
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
        XCTAssertEqual(a.map(\.visitCount), [8, 4])
    }

    // MARK: - PlanStore log

    func test_record_isIdempotentPerSession_newestFirst() {
        let store = PlanStore(defaults: freshDefaults(), today: t0)
        store.recordSessionPlace(pt(0, lat: gym.lat, lon: gym.lon), now: t0)
        store.recordSessionPlace(pt(1, lat: gym.lat, lon: gym.lon), now: t0)
        var again = pt(0, lat: crag.lat, lon: crag.lon)
        again.horizontalAccuracy = 30
        store.recordSessionPlace(again, now: t0)
        XCTAssertEqual(store.sessionPlaces.count, 2)
        XCTAssertEqual(store.sessionPlaces.last?.latitude, crag.lat, "a re-record replaces")
        XCTAssertEqual(store.sessionPlaces.first?.sessionId, pt(1, lat: 0, lon: 0).sessionId)
    }

    func test_record_trimsToRetentionWindow() {
        let store = PlanStore(defaults: freshDefaults(), today: t0)
        let old = pt(0, lat: gym.lat, lon: gym.lon,
                     at: -Double(PlanStore.sessionPlacesRetentionDays + 1) * 24)
        store.recordSessionPlace(old, now: t0)
        store.recordSessionPlace(pt(1, lat: gym.lat, lon: gym.lon, at: -1), now: t0)
        XCTAssertEqual(store.sessionPlaces.count, 1)
    }

    func test_log_persistsAcrossRelaunch_andReloadsAfterRestore() {
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: t0)
        store.recordSessionPlace(pt(0, lat: gym.lat, lon: gym.lon, at: -2), now: t0)
        XCTAssertEqual(PlanStore(defaults: defaults, today: t0).sessionPlaces.count, 1)

        let restored = [pt(1, lat: gym.lat, lon: gym.lon, at: -3), pt(2, lat: crag.lat, lon: crag.lon, at: -4)]
        defaults.set(try? PlanStore.encoder().encode(restored), forKey: PlanStore.sessionPlacesKey)
        store.reloadFromDefaults(today: t0)
        XCTAssertEqual(store.sessionPlaces.count, 2)
    }

    func test_clear_removesTheLog() {
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: t0)
        store.recordSessionPlace(pt(0, lat: gym.lat, lon: gym.lon), now: t0)
        store.clear()
        XCTAssertTrue(store.sessionPlaces.isEmpty)
        XCTAssertNil(defaults.object(forKey: PlanStore.sessionPlacesKey))
    }

    func test_eraseAllData_sweepsTheLogKey() {
        let defaults = freshDefaults()
        PlanStore(defaults: defaults, today: t0).recordSessionPlace(pt(0, lat: gym.lat, lon: gym.lon), now: t0)
        MemoryStore.wipeAllUserData(defaults: defaults, userDB: UserDatabase(path: ":memory:"))
        XCTAssertNil(defaults.object(forKey: PlanStore.sessionPlacesKey))
    }

    func test_backup_roundTripsTheLog() throws {
        let original = freshDefaults("backup-original")
        // Whole seconds, so the JSON round trip compares exactly.
        let when = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 3600).rounded(.down))
        let point = SessionPlacePoint(sessionId: when.timeIntervalSince1970, capturedAt: when,
                                      latitude: gym.lat, longitude: gym.lon, horizontalAccuracy: 65)
        PlanStore(defaults: original).recordSessionPlace(point)

        let envelope = BackupManager.snapshot(defaults: original, userDB: UserDatabase(path: ":memory:"))
        XCTAssertEqual(envelope.sessionPlaces, [point])
        let decoded = try BackupManager.decode(try BackupManager.encode(envelope))
        let restored = freshDefaults("backup-restored")
        try BackupManager.restore(decoded, into: restored, userDB: UserDatabase(path: ":memory:"))
        XCTAssertEqual(PlanStore(defaults: restored).sessionPlaces, [point])
    }

    // MARK: - SessionStore hook

    private func active(startTime: Date) -> ActiveSession {
        ActiveSession(templateId: "t1", name: "Lower A", category: "lift", startTime: startTime,
                      exercises: [], feel: nil, note: nil)
    }

    func test_onSessionStarted_firesOncePerNewSession_notOnAutosave() {
        let store = SessionStore(defaults: freshDefaults(), userDB: UserDatabase(path: ":memory:"))
        var started: [Date] = []
        store.onSessionStarted = { started.append($0.startTime) }
        let now = Date()
        var s = active(startTime: now)
        store.saveActive(s)
        s.note = "autosave"
        store.saveActive(s)
        XCTAssertEqual(started, [now])

        let next = active(startTime: now.addingTimeInterval(1))
        store.saveActive(next)
        XCTAssertEqual(started.count, 2)
    }

    func test_onSessionStarted_doesNotFireForAnOldSession() {
        let store = SessionStore(defaults: freshDefaults(), userDB: UserDatabase(path: ":memory:"))
        var calls = 0
        store.onSessionStarted = { _ in calls += 1 }
        store.saveActive(active(startTime: Date().addingTimeInterval(-3600)))
        XCTAssertEqual(calls, 0, "a session that began an hour ago is not starting now")
    }

    func test_captureIsDisabledUnderTests() {
        XCTAssertTrue(SessionLocationCapture.isDisabledForThisProcess,
                      "unit tests must never raise the location prompt")
    }
}
