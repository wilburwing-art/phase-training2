// LoggedSetTypeTests.swift — set types (normal, warmup, drop, failure) and
// their wire compatibility with payloads that carry only the old isWarmup Bool.

import XCTest
@testable import PhaseTraining

final class LoggedSetTypeTests: XCTestCase {

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    private func decode(_ json: String) throws -> LoggedSet {
        try decoder().decode(LoggedSet.self, from: Data(json.utf8))
    }

    func test_oldPayload_isWarmupTrue_decodesAsWarmup() throws {
        let s = try decode(#"{"num":1,"weight":"95","reps":"5","rpe":"","done":true,"isWarmup":true}"#)
        XCTAssertEqual(s.setType, .warmup)
    }

    func test_oldPayload_isWarmupFalse_decodesAsNormal() throws {
        let s = try decode(#"{"num":1,"weight":"95","reps":"5","rpe":"","done":true,"isWarmup":false}"#)
        XCTAssertEqual(s.setType, .normal)
    }

    func test_preBuild100Payload_noTypeKeys_decodesAsNormal() throws {
        let s = try decode(#"{"num":1,"weight":"95","reps":"5","rpe":"","done":true}"#)
        XCTAssertEqual(s.setType, .normal)
    }

    func test_unknownType_fallsBackToItsIsWarmup() throws {
        let warm = try decode(#"{"num":1,"weight":"95","reps":"5","rpe":"","done":true,"setType":"myo","isWarmup":true}"#)
        XCTAssertEqual(warm.setType, .warmup)
        let work = try decode(#"{"num":1,"weight":"95","reps":"5","rpe":"","done":true,"setType":"myo","isWarmup":false}"#)
        XCTAssertEqual(work.setType, .normal)
    }

    func test_encode_writesSetTypeAndLegacyWarmupKey() throws {
        for type in SetType.allCases {
            let s = LoggedSet(num: 1, weight: "95", reps: "5", rpe: "", done: true, setType: type)
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try encoder().encode(s)) as? [String: Any])
            XCTAssertEqual(obj["setType"] as? String, type.rawValue)
            XCTAssertEqual(obj["isWarmup"] as? Bool, type == .warmup)
        }
    }

    func test_allTypes_roundTrip() throws {
        for type in SetType.allCases {
            let s = LoggedSet(num: 3, weight: "135", reps: "8", rpe: "9", done: true, setType: type, rir: "1")
            XCTAssertEqual(try decoder().decode(LoggedSet.self, from: try encoder().encode(s)), s)
        }
    }

    private func session(types: [SetType]) -> ActiveSession {
        let sets = types.enumerated().map { i, t in
            LoggedSet(num: i + 1, weight: "135", reps: "5", rpe: "", done: false, setType: t)
        }
        let ex = LoggedExercise(id: "squat", name: "Squat", type: nil, unit: "lb", targetSets: 3, targetReps: 5,
                                rest: 120, sets: sets, prevSets: [], rpe: nil, tempo: nil)
        return ActiveSession(templateId: "t", name: "Lower", category: "c", startTime: Date(timeIntervalSince1970: 1_790_000_000),
                             exercises: [ex], feel: nil, note: nil)
    }

    /// An older build decodes without setType, then re-encodes and echoes the
    /// session back (watch sessionStarted, backup restore). Its re-encode has
    /// no setType key, only isWarmup.
    func test_olderWatchEcho_keepsWarmups() throws {
        let original = session(types: [.warmup, .normal, .drop])
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try encoder().encode(original)) as? [String: Any])
        var exercises = try XCTUnwrap(obj["exercises"] as? [[String: Any]])
        exercises = exercises.map { ex in
            var ex = ex
            ex["sets"] = (ex["sets"] as? [[String: Any]])?.map { set in
                var set = set
                set.removeValue(forKey: "setType")
                return set
            }
            return ex
        }
        obj["exercises"] = exercises
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try decoder().decode(ActiveSession.self, from: stripped)
        XCTAssertEqual(decoded.exercises[0].sets.map(\.setType), [.warmup, .normal, .normal],
                       "the warmup survives; the drop set reads normal on an old build")
    }

    func test_watchContext_roundTripsSetTypes() throws {
        let ctx = WatchSyncContext(activeSession: session(types: SetType.allCases), sentAt: Date(timeIntervalSince1970: 1_790_000_100))
        let back = try decoder().decode(WatchSyncContext.self, from: try encoder().encode(ctx))
        XCTAssertEqual(back, ctx)
        XCTAssertEqual(back.activeSession?.exercises[0].sets.map(\.setType), SetType.allCases)
    }

    func test_effortRIR_failureWithNothingLogged_isZero() {
        let s = LoggedSet(num: 1, weight: "135", reps: "8", rpe: "", done: true, setType: .failure)
        XCTAssertEqual(s.effortRIR, 0)
    }

    func test_effortRIR_failureWithLoggedRIR_usesLogged() {
        let s = LoggedSet(num: 1, weight: "135", reps: "8", rpe: "", done: true, setType: .failure, rir: "1")
        XCTAssertEqual(s.effortRIR, 1)
    }

    func test_predicates() {
        XCTAssertEqual(SetType.allCases.filter(\.isWorkingSet), [.normal, .drop, .failure])
        XCTAssertEqual(SetType.allCases.filter(\.countsForStrength), [.normal, .failure])
    }
}
