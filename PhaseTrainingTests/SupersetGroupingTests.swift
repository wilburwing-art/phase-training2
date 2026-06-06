import XCTest
@testable import PhaseTraining

/// Characterization tests for `SupersetGrouping.layout(_:groupOf:)` — the
/// pure re-ordering + metadata pass behind LogScreen's and
/// DayWorkoutPreviewSheet's superset rendering. Locks in: adjacency pull
/// (group anchors at first encounter, siblings drain in source order),
/// letter assignment by encounter order, the "group of one gets no label"
/// rule, and the first/last band hints.
final class SupersetGroupingTests: XCTestCase {

    // MARK: - Fixtures

    private typealias Row = (name: String, group: Int?)

    private func layout(_ rows: [Row]) -> [SupersetGroupedItem<Row>] {
        SupersetGrouping.layout(rows) { $0.group }
    }

    private func names(_ items: [SupersetGroupedItem<Row>]) -> [String] {
        items.map { $0.element.name }
    }

    // MARK: - Empty / ungrouped passthrough

    func test_emptyInput_returnsEmptyLayout() {
        XCTAssertTrue(layout([]).isEmpty)
    }

    func test_allUngrouped_passThroughInOriginalOrder() {
        let r = layout([("squat", nil), ("bench", nil), ("row", nil)])
        XCTAssertEqual(names(r), ["squat", "bench", "row"])
        for (i, item) in r.enumerated() {
            XCTAssertEqual(item.originalIndex, i)
            XCTAssertNil(item.groupLetter)
            XCTAssertNil(item.withinGroupIndex)
            XCTAssertNil(item.label)
            XCTAssertNil(item.supersetGroup)
            XCTAssertEqual(item.groupSize, 1)
            XCTAssertTrue(item.isFirstInGroup)
            XCTAssertTrue(item.isLastInGroup)
        }
    }

    // MARK: - Pairs / adjacency

    func test_consecutivePair_labeledAndAdjacent() {
        let r = layout([("curl", 1), ("pushdown", 1), ("plank", nil)])
        XCTAssertEqual(names(r), ["curl", "pushdown", "plank"])

        XCTAssertEqual(r[0].label, "A1")
        XCTAssertEqual(r[0].groupSize, 2)
        XCTAssertTrue(r[0].isFirstInGroup)
        XCTAssertFalse(r[0].isLastInGroup)
        XCTAssertEqual(r[0].supersetGroup, 1)

        XCTAssertEqual(r[1].label, "A2")
        XCTAssertEqual(r[1].groupSize, 2)
        XCTAssertFalse(r[1].isFirstInGroup)
        XCTAssertTrue(r[1].isLastInGroup)

        XCTAssertNil(r[2].label)
        XCTAssertEqual(r[2].groupSize, 1)
    }

    func test_nonAdjacentPair_pulledTogetherAtFirstEncounter() {
        // The pair anchors where its first member sat; the interleaved
        // un-grouped row shifts after the drained group. Siblings keep
        // source order, and originalIndex still points at the input slot.
        let r = layout([("curl", 1), ("plank", nil), ("pushdown", 1)])
        XCTAssertEqual(names(r), ["curl", "pushdown", "plank"])
        XCTAssertEqual(r.map(\.originalIndex), [0, 2, 1])
        XCTAssertEqual(r[0].label, "A1")
        XCTAssertEqual(r[1].label, "A2")
        XCTAssertNil(r[2].label)
    }

    // MARK: - Orphaned half of a pair

    func test_orphanedHalfOfPair_keepsGroupIdButNoLabel() {
        // A group of one (partner deleted / never added) keeps the raw
        // supersetGroup id so callers can still compare, but renders
        // un-labeled per the "≥ 2 = superset" UX rule.
        let r = layout([("dip", 7)])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].supersetGroup, 7)
        XCTAssertNil(r[0].groupLetter)
        XCTAssertNil(r[0].withinGroupIndex)
        XCTAssertNil(r[0].label)
        XCTAssertEqual(r[0].groupSize, 1)
        XCTAssertTrue(r[0].isFirstInGroup)
        XCTAssertTrue(r[0].isLastInGroup)
    }

    func test_orphanAmidUngroupedRows_staysInPlace() {
        let r = layout([("squat", nil), ("dip", 3), ("row", nil)])
        XCTAssertEqual(names(r), ["squat", "dip", "row"])
        XCTAssertEqual(r.map(\.originalIndex), [0, 1, 2])
        XCTAssertNil(r[1].label)
        XCTAssertEqual(r[1].supersetGroup, 3)
    }

    // MARK: - Mixed grouped / ungrouped sequences

    func test_mixedGroupedAndUngrouped_complexSequence() {
        let r = layout([
            ("warmup", nil),   // 0
            ("curl", 1),       // 1
            ("squat", nil),    // 2
            ("pushdown", 1),   // 3
            ("row", nil),      // 4
            ("flye", 2),       // 5
            ("rear delt", 2),  // 6
        ])
        // Group 1 drains at curl's slot; squat and row shift after it.
        // Group 2 was already adjacent.
        XCTAssertEqual(names(r), ["warmup", "curl", "pushdown",
                                  "squat", "row", "flye", "rear delt"])
        XCTAssertEqual(r.map(\.originalIndex), [0, 1, 3, 2, 4, 5, 6])
        XCTAssertEqual(r.map(\.label), [nil, "A1", "A2", nil, nil, "B1", "B2"])
        XCTAssertEqual(r.map(\.supersetGroup), [nil, 1, 1, nil, nil, 2, 2])
    }

    // MARK: - Letter assignment

    func test_lettersAssignedByEncounterOrder_notByGroupNumber() {
        // Group ids are opaque — a high id seen first still gets "A".
        let r = layout([("a", 9), ("b", 9), ("c", 2), ("d", 2)])
        XCTAssertEqual(r.map(\.label), ["A1", "A2", "B1", "B2"])
    }

    func test_soloGroupConsumesALetterSlot() {
        // Characterizes current behavior: a group of one never displays a
        // letter, but it still occupies its encounter-order slot — so the
        // pair behind it letters as "B", not "A".
        let r = layout([("orphan", 5), ("curl", 9), ("pushdown", 9)])
        XCTAssertNil(r[0].label)
        XCTAssertEqual(r[1].label, "B1")
        XCTAssertEqual(r[2].label, "B2")
    }

    func test_letterOverflow_27thGroupGetsAA() {
        // 27 pairs: groups 0..25 letter A..Z, group 26 rolls to "AA"
        // (Excel-column style). Ids offset by 100 to prove letters come
        // from encounter order, not the id value.
        var rows: [Row] = []
        for g in 0..<27 {
            rows.append(("g\(g)-1", 100 + g))
            rows.append(("g\(g)-2", 100 + g))
        }
        let r = layout(rows)
        XCTAssertEqual(r.count, 54)
        XCTAssertEqual(r[50].groupLetter, "Z")   // 26th group (index 25)
        XCTAssertEqual(r[52].groupLetter, "AA")  // 27th group (index 26)
        XCTAssertEqual(r[53].label, "AA2")
    }

    // MARK: - Larger groups / metadata

    func test_tripleGroup_firstLastHintsAndWithinIndices() {
        let r = layout([("a", 4), ("b", 4), ("c", 4)])
        XCTAssertEqual(r.map(\.label), ["A1", "A2", "A3"])
        XCTAssertEqual(r.map(\.groupSize), [3, 3, 3])
        XCTAssertEqual(r.map(\.isFirstInGroup), [true, false, false])
        XCTAssertEqual(r.map(\.isLastInGroup), [false, false, true])
        XCTAssertEqual(r.map(\.withinGroupIndex), [1, 2, 3])
    }

    func test_labelConvenience_combinesLetterAndIndex() {
        let r = layout([("a", 1), ("b", 1), ("solo", nil), ("orphan", 8)])
        XCTAssertEqual(r[0].label, "A1")
        XCTAssertEqual(r[1].label, "A2")
        XCTAssertNil(r[2].label, "un-grouped rows have no label")
        XCTAssertNil(r[3].label, "group-of-one rows have no label")
    }
}
