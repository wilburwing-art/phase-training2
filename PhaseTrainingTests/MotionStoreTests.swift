// MotionStoreTests.swift — the labeled-motion file format, the windowing
// rule and the phone's capped store (PLAN-watch.md, step 3).

import XCTest
@testable import PhaseTraining

final class MotionStoreTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func window(setNum: Int = 1, samples count: Int = 100) -> MotionWindow {
        let header = MotionWindowHeader(sessionId: "pt-session-1790000000000", exerciseId: "gex-57",
                                        exerciseName: "Barbell Back Squat", setNum: setNum,
                                        plannedWeight: "135", plannedReps: 5, loggedWeight: "140", loggedReps: "5",
                                        start: start, end: start.addingTimeInterval(Double(count) / 50),
                                        sampleRateHz: 50, sampleCount: count, device: "Watch7,1 watchOS 26.0")
        let samples = (0 ..< count * 6).map { Float($0) * 0.001 - 0.3 }
        return MotionWindow(header: header, samples: samples)
    }

    // MARK: - Codec

    func test_codec_roundTripsBitExact() throws {
        let w = window()
        let data = try MotionWindowCodec.encode(w)
        XCTAssertEqual(data.prefix(4), Data("PTM1".utf8))
        XCTAssertEqual(try MotionWindowCodec.decode(data), w)
        // 100 samples x 6 channels x 4 bytes, plus the header.
        XCTAssertGreaterThan(data.count, 2400)
        XCTAssertLessThan(data.count, 2400 + 600)
    }

    func test_codec_refusesGarbageAndTruncation() throws {
        XCTAssertThrowsError(try MotionWindowCodec.decode(Data("nope".utf8)))
        let data = try MotionWindowCodec.encode(window())
        XCTAssertThrowsError(try MotionWindowCodec.decode(data.prefix(data.count - 4)))
        var bad = window()
        bad.samples.removeLast()
        XCTAssertThrowsError(try MotionWindowCodec.encode(bad))
    }

    func test_fileName_isPerSet() {
        XCTAssertEqual(window(setNum: 3).fileName, "gex-57-set3.ptmotion")
    }

    // MARK: - Windowing

    func test_window_startsAtTheLaterOfPreviousTapAndRestEnd() {
        let w = MotionWindowCodec.window(previousDoneAt: start.addingTimeInterval(60),
                                         restEndedAt: start.addingTimeInterval(150),
                                         doneAt: start.addingTimeInterval(200), sessionStart: start)
        XCTAssertEqual(w?.start, start.addingTimeInterval(150))
        XCTAssertEqual(w?.end, start.addingTimeInterval(200))
        let first = MotionWindowCodec.window(previousDoneAt: nil, restEndedAt: nil,
                                             doneAt: start.addingTimeInterval(40), sessionStart: start)
        XCTAssertEqual(first?.start, start)
    }

    func test_window_dropsSpansUnderThreeSeconds() {
        XCTAssertNil(MotionWindowCodec.window(previousDoneAt: start.addingTimeInterval(10), restEndedAt: nil,
                                              doneAt: start.addingTimeInterval(12), sessionStart: start))
        XCTAssertNil(MotionWindowCodec.window(previousDoneAt: start.addingTimeInterval(20), restEndedAt: nil,
                                              doneAt: start.addingTimeInterval(10), sessionStart: start))
    }

    // MARK: - Store

    private func tempStore() throws -> MotionStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("motion-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return MotionStore(root: root)
    }

    private func incoming(_ bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("in-\(UUID().uuidString).ptmotion")
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    func test_store_movesTheFileIntoTheSessionDirectory() throws {
        let store = try tempStore()
        let url = try incoming(10)
        let dest = try store.store(fileAt: url, sessionId: "pt-session-1", fileName: "gex-57-set1.ptmotion", now: start)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "moved, not copied")
        XCTAssertEqual(dest.lastPathComponent, "gex-57-set1.ptmotion")
        XCTAssertEqual(store.entries().map(\.sessionId), ["pt-session-1"])
        XCTAssertEqual(store.summary().windows, 1)
        // A re-sent file replaces the earlier one.
        try store.store(fileAt: try incoming(12), sessionId: "pt-session-1", fileName: "gex-57-set1.ptmotion", now: start)
        XCTAssertEqual(store.entries().count, 1)
        XCTAssertEqual(store.totalBytes, 12)
    }

    func test_store_refusesPathsThatEscapeTheRoot() throws {
        let store = try tempStore()
        XCTAssertThrowsError(try store.store(fileAt: try incoming(1), sessionId: "../x", fileName: "a.ptmotion"))
        XCTAssertThrowsError(try store.store(fileAt: try incoming(1), sessionId: "s", fileName: "../a.ptmotion"))
        XCTAssertThrowsError(try store.store(fileAt: try incoming(1), sessionId: "s", fileName: "a.txt"))
    }

    func test_prune_dropsOldWindows_thenTheOldestOverTheByteCap() throws {
        let store = try tempStore()
        let old = start.addingTimeInterval(-MotionStore.maxAge - 60)
        try store.store(fileAt: try incoming(10), sessionId: "old", fileName: "a-set1.ptmotion", now: old)
        try store.store(fileAt: try incoming(10), sessionId: "new", fileName: "a-set1.ptmotion", now: start)
        store.prune(now: start)
        XCTAssertEqual(store.entries().map(\.sessionId), ["new"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("old").path),
                       "empty session directory removed")

        // Byte cap: three files just over it together, oldest goes first.
        let big = MotionStore.maxBytes / 2
        try store.store(fileAt: try incoming(big), sessionId: "s1", fileName: "a-set1.ptmotion", now: start.addingTimeInterval(1))
        try store.store(fileAt: try incoming(big), sessionId: "s2", fileName: "a-set1.ptmotion", now: start.addingTimeInterval(2))
        try store.store(fileAt: try incoming(big), sessionId: "s3", fileName: "a-set1.ptmotion", now: start.addingTimeInterval(3))
        XCTAssertLessThanOrEqual(store.totalBytes, MotionStore.maxBytes)
        // Oldest first: the tiny "new" file and s1 go, s2 and s3 sit exactly at the cap.
        XCTAssertEqual(Set(store.entries().map(\.sessionId)), ["s2", "s3"])
    }

    func test_wipe_removesEverything() throws {
        let store = try tempStore()
        try store.store(fileAt: try incoming(5), sessionId: "s", fileName: "a-set1.ptmotion", now: start)
        store.wipe()
        XCTAssertTrue(store.entries().isEmpty)
        XCTAssertEqual(store.summary().windows, 0)
    }
}
