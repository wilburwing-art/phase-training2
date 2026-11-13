import XCTest
@testable import PhaseTraining

/// `SupersetEditing` backs "Superset with next" and "Remove from superset"
/// in Log. Indices are source-order; "next" is the row drawn after this one.
final class SupersetEditingTests: XCTestCase {

    private struct Row: Equatable {
        var name: String
        var group: Int?
    }

    private func rows(_ spec: [(String, Int?)]) -> [Row] {
        spec.map { Row(name: $0.0, group: $0.1) }
    }

    private func groups(_ r: [Row]) -> [Int?] { r.map(\.group) }

    func test_pair_twoPlainRowsGetAFreshGroup() {
        var r = rows([("a", nil), ("b", nil), ("c", 4)])
        XCTAssertTrue(SupersetEditing.pairWithNext(&r, at: 0, group: \.group))
        XCTAssertEqual(groups(r), [5, 5, 4], "fresh id is one past the highest in use")
    }

    func test_pair_lastRowHasNoNext() {
        var r = rows([("a", nil), ("b", nil)])
        XCTAssertFalse(SupersetEditing.pairWithNext(&r, at: 1, group: \.group))
        XCTAssertFalse(SupersetEditing.pairWithNext(&r, at: 9, group: \.group))
        XCTAssertEqual(groups(r), [nil, nil])
    }

    func test_pair_plainRowJoinsTheGroupBelow() {
        var r = rows([("a", nil), ("b", 1), ("c", 1)])
        SupersetEditing.pairWithNext(&r, at: 0, group: \.group)
        XCTAssertEqual(groups(r), [1, 1, 1])
    }

    func test_pair_groupedRowPullsInTheRowAfterItsGroup() {
        // Render order is a, c, b, d: the group is drawn together, so the
        // row after it is b, and pairing from `a` pulls b in.
        var r = rows([("a", 1), ("b", nil), ("c", 1), ("d", nil)])
        XCTAssertEqual(SupersetEditing.nextIndex(r, after: 0, groupOf: { $0.group }), 1)
        SupersetEditing.pairWithNext(&r, at: 0, group: \.group)
        XCTAssertEqual(groups(r), [1, 1, 1, nil])
    }

    func test_pair_twoGroupsMerge() {
        var r = rows([("a", 1), ("b", 1), ("c", 2), ("d", 2)])
        SupersetEditing.pairWithNext(&r, at: 1, group: \.group)
        XCTAssertEqual(groups(r), [1, 1, 1, 1])
    }

    func test_remove_dissolvesAPair() {
        var r = rows([("a", 1), ("b", 1), ("c", nil)])
        SupersetEditing.remove(&r, at: 0, group: \.group)
        XCTAssertEqual(groups(r), [nil, nil, nil])
    }

    func test_remove_fromThreeLeavesTheOtherTwoPaired() {
        var r = rows([("a", 1), ("b", 1), ("c", 1)])
        SupersetEditing.remove(&r, at: 1, group: \.group)
        XCTAssertEqual(groups(r), [1, nil, 1])
    }

    func test_remove_plainRowIsANoOp() {
        var r = rows([("a", nil), ("b", 1), ("c", 1)])
        SupersetEditing.remove(&r, at: 0, group: \.group)
        XCTAssertEqual(groups(r), [nil, 1, 1])
    }

    func test_pairThenLayout_labelsBothRows() {
        var r = rows([("a", nil), ("b", nil)])
        SupersetEditing.pairWithNext(&r, at: 0, group: \.group)
        let labels = SupersetGrouping.layout(r) { $0.group }.map(\.label)
        XCTAssertEqual(labels, ["A1", "A2"])
    }

    /// The day preview pairs `ExerciseTemplate` rows; the group has to reach
    /// Log, where the pair is drawn as A1 and A2.
    @MainActor
    func test_pairMadeOnATemplateStartsInLogAsOneSuperset() {
        let suite = "superset-editing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var exercises = ["Bench Press", "Barbell Row", "Plank"].enumerated().map { i, name in
            ExerciseTemplate(id: "e\(i)", name: name, type: nil, unit: "lbs",
                             targetSets: 3, targetReps: 8, rest: 90)
        }
        XCTAssertTrue(SupersetEditing.pairWithNext(&exercises, at: 0, group: \.supersetGroup))
        let template = WorkoutTemplate(id: "t", name: "T", category: "c", exercises: exercises)
        let store = SessionStore(defaults: defaults, userDB: UserDatabase(path: ":memory:"))
        let session = store.createSession(from: template)
        let laidOut = SupersetGrouping.layout(session.exercises) { $0.supersetGroup }
        XCTAssertEqual(laidOut.map(\.label), ["A1", "A2", nil])
    }
}
