import XCTest
@testable import PhaseTraining

/// A workout logged after the fact keeps the time it happened.
final class LoggedForTests: XCTestCase {

    private func sessions() -> SessionStore {
        SessionStore(defaults: UserDefaults(suiteName: "LoggedFor.\(UUID().uuidString)")!,
                     userDB: UserDatabase(path: ":memory:"))
    }

    private func active(loggedFor: LoggedFor?) -> ActiveSession {
        let squat = LoggedExercise(id: "a", name: "Barbell Back Squat", type: nil, unit: "lbs",
                                   targetSets: 3, targetReps: 5, rest: 120,
                                   sets: (1...3).map { LoggedSet(num: $0, weight: "185", reps: "5", rpe: "", done: true) },
                                   prevSets: [])
        return ActiveSession(templateId: "t", name: "Legs", category: "lift",
                             startTime: Date().addingTimeInterval(-180), exercises: [squat],
                             feel: nil, note: nil, loggedFor: loggedFor)
    }

    func test_backdatedSave_usesThePickedStartAndLength() {
        let store = sessions()
        let start = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let saved = store.saveCompleted(active(loggedFor: LoggedFor(start: start, minutes: 55)),
                                        feel: nil, note: nil)
        XCTAssertEqual(saved.startTime, start)
        XCTAssertEqual(saved.endTime, start.addingTimeInterval(55 * 60))
        XCTAssertEqual(saved.duration, 55 * 60)
        XCTAssertEqual(store.savedSessions.first?.id, start.timeIntervalSince1970)
    }

    func test_backdatedSave_neverReusesASavedSessionsId() {
        let store = sessions()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let first = store.saveCompleted(active(loggedFor: LoggedFor(start: start, minutes: 30)), feel: nil, note: nil)
        let second = store.saveCompleted(active(loggedFor: LoggedFor(start: start, minutes: 30)), feel: nil, note: nil)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.startTime, start.addingTimeInterval(1))
        XCTAssertEqual(store.savedSessions.count, 2)
    }

    func test_unsetLoggedFor_keepsTheLiveTimes() {
        let store = sessions()
        let a = active(loggedFor: nil)
        let end = Date()
        let saved = store.saveCompleted(a, feel: nil, note: nil, endTime: end)
        XCTAssertEqual(saved.startTime, a.startTime)
        XCTAssertEqual(saved.endTime, end)
        XCTAssertEqual(saved.duration, Int(end.timeIntervalSince(a.startTime)))
    }

    func test_oldActiveSessionPayload_decodes() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(active(loggedFor: nil))) as! [String: Any]
        json.removeValue(forKey: "loggedFor")
        let decoded = try JSONDecoder().decode(ActiveSession.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.loggedFor)
    }
}
