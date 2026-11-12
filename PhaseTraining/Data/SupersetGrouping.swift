// SupersetGrouping.swift — visual + nav helpers around `supersetGroup`.
//
// The superset_group column on routine_exercises (mirrored on
// CustomRoutineExercise) is an opaque integer: any two-plus rows that share
// it form one superset. The integer carries no display meaning — it's just
// an identity key.
//
// LogScreen + DayWorkoutPreviewSheet both need:
//   1. A render order where grouped rows are adjacent (and stable within
//      a group), with un-grouped rows interleaved in their original slots.
//   2. Per-row metadata: the user-facing letter (A, B, C…) assigned by
//      encounter order, the within-group index (1, 2, 3…), and is-
//      first / is-last hints so they can draw the colored left band.
//   3. Navigation between siblings during active workouts (LogScreen's
//      rest-timer state machine round-robins within the group).
//
// This file exposes one entry point — `SupersetGrouping.layout(...)` —
// returning a `[SupersetGroupedItem]` whose `.element` preserves the
// original payload (LoggedExercise / ExerciseTemplate / any T) so callers
// don't have to plumb extra types through their views.

import Foundation

/// View-side metadata for one row inside a superset-aware layout.
/// `groupLetter` + `withinGroupIndex` are non-nil only for elements
/// that belong to a superset (≥ 2 members sharing the same id). Solo
/// supersets (a group of 1) collapse to "no label" — the user assigned
/// a number but never partnered the row.
struct SupersetGroupedItem<Element> {
    /// The original payload at this render position.
    let element: Element
    /// Original index in the input array (before re-ordering). Useful when
    /// the caller still needs to mutate the source-of-truth array by index.
    let originalIndex: Int
    /// A, B, C, … assigned by group-encounter order. Nil for rows not in
    /// any superset, AND for rows in a "group of one" (no partner).
    let groupLetter: String?
    /// 1, 2, 3, … within the group. Nil under the same conditions as
    /// `groupLetter`.
    let withinGroupIndex: Int?
    /// Size of the group this row belongs to (1 if solo / un-grouped).
    let groupSize: Int
    /// True when this is the first rendered row of its group. Always true
    /// for un-grouped rows.
    let isFirstInGroup: Bool
    /// True when this is the last rendered row of its group. Always true
    /// for un-grouped rows.
    let isLastInGroup: Bool
    /// The raw `supersetGroup` integer (nil = un-grouped). Carried through
    /// so callers can group / compare without re-deriving it.
    let supersetGroup: Int?
}

extension SupersetGroupedItem {
    /// Convenience: A1 / B2 prefix for the title, or nil if un-labeled.
    var label: String? {
        guard let groupLetter, let withinGroupIndex else { return nil }
        return "\(groupLetter)\(withinGroupIndex)"
    }
}

enum SupersetGrouping {
    /// Re-order `items` so members of the same `supersetGroup` render
    /// adjacently, and return per-row metadata (letter + within-group
    /// index + first/last hints).
    ///
    /// Strategy: walk the input in source order. The first time we see a
    /// group, anchor it at the current emit position and immediately emit
    /// every other member of that group too (in source order). On
    /// subsequent encounters of an already-emitted group, skip — we
    /// already drained its members. Un-grouped rows emit in place.
    /// Solo groups (size 1) keep the group number but don't get a label,
    /// matching the "≥ 2 = superset" UX rule.
    static func layout<Element>(
        _ items: [Element],
        groupOf: (Element) -> Int?
    ) -> [SupersetGroupedItem<Element>] {

        // Count members per group so we can tell singletons apart from
        // real supersets, and assign letters by first-encounter order.
        var counts: [Int: Int] = [:]
        var encounterOrder: [Int] = []
        for item in items {
            guard let g = groupOf(item) else { continue }
            counts[g, default: 0] += 1
            if counts[g] == 1 { encounterOrder.append(g) }
        }

        // Group → letter. A, B, … Z, then AA, AB, … (unlikely to overflow
        // in practice — a single routine rarely has > 26 groups).
        var letterByGroup: [Int: String] = [:]
        for (idx, g) in encounterOrder.enumerated() {
            letterByGroup[g] = Self.letter(for: idx)
        }

        // Build (group → ordered indices) map up front so we can emit
        // siblings in one go.
        var indicesByGroup: [Int: [Int]] = [:]
        for (i, item) in items.enumerated() {
            if let g = groupOf(item) {
                indicesByGroup[g, default: []].append(i)
            }
        }

        var out: [SupersetGroupedItem<Element>] = []
        var emittedGroups = Set<Int>()

        for (i, item) in items.enumerated() {
            if let g = groupOf(item) {
                if emittedGroups.contains(g) { continue }
                let memberIndices = indicesByGroup[g] ?? [i]
                let size = memberIndices.count
                emittedGroups.insert(g)
                for (k, mi) in memberIndices.enumerated() {
                    let isLabeled = size >= 2
                    out.append(SupersetGroupedItem(
                        element: items[mi],
                        originalIndex: mi,
                        groupLetter: isLabeled ? letterByGroup[g] : nil,
                        withinGroupIndex: isLabeled ? k + 1 : nil,
                        groupSize: size,
                        isFirstInGroup: k == 0,
                        isLastInGroup: k == size - 1,
                        supersetGroup: g
                    ))
                }
            } else {
                out.append(SupersetGroupedItem(
                    element: item,
                    originalIndex: i,
                    groupLetter: nil,
                    withinGroupIndex: nil,
                    groupSize: 1,
                    isFirstInGroup: true,
                    isLastInGroup: true,
                    supersetGroup: nil
                ))
            }
        }
        return out
    }

    /// 0 → "A", 25 → "Z", 26 → "AA", 27 → "AB", … (Excel-column style).
    private static func letter(for index: Int) -> String {
        var n = index
        var s = ""
        repeat {
            let r = n % 26
            s = String(UnicodeScalar(65 + r)!) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }
}

// MARK: - Editing

/// Create and break supersets on any list that carries a `supersetGroup`.
/// Log uses it mid-workout; the indices are source-order indices into the
/// caller's array.
enum SupersetEditing {
    /// Source index of the row drawn right after `index`'s row (or after
    /// its whole group when it already has one). Nil for the last row.
    static func nextIndex<Element>(
        _ items: [Element], after index: Int, groupOf: (Element) -> Int?
    ) -> Int? {
        guard items.indices.contains(index) else { return nil }
        let rendered = SupersetGrouping.layout(items, groupOf: groupOf)
        let own = groupOf(items[index])
        guard let lastOfMine = rendered.lastIndex(where: {
            $0.originalIndex == index || (own != nil && $0.supersetGroup == own)
        }), rendered.indices.contains(lastOfMine + 1) else { return nil }
        return rendered[lastOfMine + 1].originalIndex
    }

    /// Pair the row at `index` with the row drawn after it. An existing
    /// group on either side grows; two groups merge. Returns false when
    /// there is no next row.
    @discardableResult
    static func pairWithNext<Element>(
        _ items: inout [Element], at index: Int, group: WritableKeyPath<Element, Int?>
    ) -> Bool {
        guard let next = nextIndex(items, after: index, groupOf: { $0[keyPath: group] }) else {
            return false
        }
        let mine = items[index][keyPath: group]
        let theirs = items[next][keyPath: group]
        switch (mine, theirs) {
        case (nil, nil):
            let fresh = (items.compactMap { $0[keyPath: group] }.max() ?? 0) + 1
            items[index][keyPath: group] = fresh
            items[next][keyPath: group] = fresh
        case (nil, let g?):
            items[index][keyPath: group] = g
        case (let g?, nil):
            items[next][keyPath: group] = g
        case (let g?, let other?):
            for i in items.indices where items[i][keyPath: group] == other {
                items[i][keyPath: group] = g
            }
        }
        return true
    }

    /// Take the row out of its superset. A group left with one member is
    /// dissolved, since one exercise is no superset.
    static func remove<Element>(
        _ items: inout [Element], at index: Int, group: WritableKeyPath<Element, Int?>
    ) {
        guard items.indices.contains(index), let g = items[index][keyPath: group] else { return }
        items[index][keyPath: group] = nil
        let rest = items.indices.filter { items[$0][keyPath: group] == g }
        if rest.count == 1 { items[rest[0]][keyPath: group] = nil }
    }
}
