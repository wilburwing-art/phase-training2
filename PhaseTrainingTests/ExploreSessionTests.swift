// ExploreSessionTests.swift — A3: the "Looked" tier.
//
// Recorder behavior against an in-memory sink, then UserDatabase storage:
// round trip, 90-day prune, the v1 -> v2 migration on an existing file, and
// wipeAll() clearing the table.

import XCTest
import SQLite3
@testable import PhaseTraining

private final class ArraySink: ExploreSink {
    var sessions: [ExploreSession] = []
    func recordExploreSession(_ session: ExploreSession) { sessions.append(session) }
}

final class ExploreSessionTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_790_000_000)
    private func tick(_ s: TimeInterval = 5) { clock = clock.addingTimeInterval(s) }

    private func recorder(_ sink: ArraySink, surface: ExploreSurface = .exercisePicker) -> ExploreRecorder {
        ExploreRecorder(surface: surface, sink: sink, now: { [unowned self] in self.clock })
    }

    // MARK: - Recorder

    func test_visitWithNoIntent_writesNothing() {
        let sink = ArraySink()
        let r = recorder(sink)
        r.query("", results: 580)
        r.query("   ", results: 580)
        r.flush()
        XCTAssertTrue(sink.sessions.isEmpty)
    }

    func test_lastNonEmptyQueryWins_andKeystrokesAreNotKept() {
        let sink = ArraySink()
        let r = recorder(sink)
        for q in ["p", "pu", "pul", "pull", "pull u", "pull up"] { r.query(q, results: 10) }
        r.query("", results: 580)       // user cleared the box before leaving
        r.flush()
        XCTAssertEqual(sink.sessions.count, 1)
        XCTAssertEqual(sink.sessions[0].query, "pull up")
        XCTAssertEqual(sink.sessions[0].resultCount, 10)
    }

    func test_openAndConversion_snapshotTheQueryInForce() {
        let sink = ArraySink()
        let r = recorder(sink)
        r.query("row", results: 12, tier: 0)
        tick(); r.opened(.exercise, id: "41", name: "Seated Cable Row")
        r.query("pull up", results: 4, tier: 0)
        tick(); r.converted(.swapIn, itemKind: .exercise, id: "88", name: "Pull-Up")
        tick(); r.flush()

        let s = try! XCTUnwrap(sink.sessions.first)
        XCTAssertEqual(s.opens.map(\.query), ["row"])
        XCTAssertEqual(s.conversions.map(\.query), ["pull up"])
        XCTAssertEqual(s.conversions.first?.kind, .swapIn)
        XCTAssertTrue(s.converted)
        XCTAssertEqual(s.endedAt.timeIntervalSince(s.startedAt), 15, accuracy: 0.001)
    }

    func test_openWithoutQuery_isIntent() {
        let sink = ArraySink()
        let r = recorder(sink, surface: .workoutCategory)
        r.opened(.routine, id: "12", name: "Ski Legs")
        r.flush()
        XCTAssertEqual(sink.sessions.count, 1)
        XCTAssertNil(sink.sessions[0].query)
        XCTAssertNil(sink.sessions[0].opens[0].query)
    }

    func test_zeroResultSearch_isRecordedAsADeadEnd() {
        let sink = ArraySink()
        let r = recorder(sink)
        r.query("sled push", results: 0, tier: 2, broadened: true)
        r.flush()
        let s = try! XCTUnwrap(sink.sessions.first)
        XCTAssertEqual(s.resultCount, 0)
        XCTAssertEqual(s.tier, 2)
        XCTAssertTrue(s.broadened)
        XCTAssertFalse(s.converted)
    }

    func test_queryIsNormalisedAndCapped() {
        XCTAssertEqual(ExploreSession.normalise("  Pull   UP \n"), "pull up")
        XCTAssertNil(ExploreSession.normalise(" \t "))
        XCTAssertEqual(ExploreSession.normalise(String(repeating: "a", count: 200))?.count, 60)
    }

    func test_flushStartsAFreshVisit() {
        let sink = ArraySink()
        let r = recorder(sink, surface: .library)
        r.query("squat", results: 30)
        r.flush()
        r.flush()                       // tab left twice with nothing in between
        r.query("lunge", results: 9)
        r.flush()
        XCTAssertEqual(sink.sessions.map(\.query), ["squat", "lunge"])
        XCTAssertNotEqual(sink.sessions[0].id, sink.sessions[1].id)
    }

    func test_defaultSink_isNilUnderTests_soTheRealDatabaseIsNeverWritten() {
        XCTAssertNil(ExploreRecorder.defaultSink())
    }

    // MARK: - Storage

    private func sample(started: Date, query: String? = "pull up") -> ExploreSession {
        ExploreSession(surface: .exercisePicker, startedAt: started, endedAt: started.addingTimeInterval(20),
                       query: query, resultCount: 4, tier: 0, broadened: false,
                       opens: [ExploreOpen(kind: .exercise, id: "88", name: "Pull-Up", query: query, at: started)],
                       conversions: [ExploreConversion(kind: .swapIn, itemKind: .exercise, id: "88",
                                                       name: "Pull-Up", query: query, at: started)])
    }

    func test_database_roundTrip() {
        let db = UserDatabase(path: ":memory:")
        let s = sample(started: clock)
        XCTAssertTrue(db.insertExploreSession(s))
        let back = db.listExploreSessions()
        XCTAssertEqual(back, [s])
    }

    func test_database_pruneDropsOnlyOldSessions() {
        let db = UserDatabase(path: ":memory:")
        let old = sample(started: clock.addingTimeInterval(-Double(UserDatabase.exploreRetentionDays + 1) * 86_400))
        let fresh = sample(started: clock.addingTimeInterval(-86_400))
        db.insertExploreSession(old)
        db.insertExploreSession(fresh)
        XCTAssertEqual(db.pruneExploreSessions(now: clock), 1)
        XCTAssertEqual(db.listExploreSessions().map(\.id), [fresh.id])
    }

    func test_database_wipeAllClearsExploreSessions() {
        let db = UserDatabase(path: ":memory:")
        db.insertExploreSession(sample(started: Date()))
        db.wipeAll()
        XCTAssertTrue(db.listExploreSessions().isEmpty)
    }

    func test_migration_v1FileGainsTheTable_andKeepsItsData() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("explore-migration-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Build a file, then roll it back to what a v1 install looks like.
        do {
            let v = UserDatabase(path: path)
            let db = try XCTUnwrap(v.db)
            XCTAssertEqual(sqlite3_exec(db, "DROP TABLE explore_sessions", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version = 1", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(db, """
                INSERT INTO user_routines (id, name, created_at, updated_at) VALUES ('keep-me', 'Keep', 0, 0)
                """, nil, nil, nil), SQLITE_OK, "fixture insert failed; check user_routines columns")
        }

        let reopened = UserDatabase(path: path)
        XCTAssertNil(reopened.unavailableReason)
        XCTAssertTrue(reopened.insertExploreSession(sample(started: Date())), "v2 table missing after upgrade")
        XCTAssertEqual(reopened.listExploreSessions().count, 1)
        XCTAssertEqual(reopened.withLock { reopened.countLocked(table: "user_routines") }, 1)
    }
}
