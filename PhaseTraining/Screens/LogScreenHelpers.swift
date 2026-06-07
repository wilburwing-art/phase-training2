// LogScreenHelpers.swift — Pure logic + formatters for LogScreen.
//
// Extracted from LogScreen.swift (Tier 3 split). Catalog lookups, weight-column
// display rules, progression-suggestion mapping, weight propagation,
// bulk-mark-done, superset round / following-work predicates, and the static
// time formatters. No view code.

import SwiftUI

extension LogScreen {
    /// Coach.db image lookup by exercise name. Used for the row thumbnail —
    /// LoggedExercise only carries name (not the original exerciseId), so we
    /// resolve via case-insensitive name match. Returns nil for exercises
    /// without media or whose name doesn't match a catalog row.
    func thumbnailURL(forName name: String) -> String? {
        CoachDatabase.shared
            .listExercises(search: name)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            .flatMap { $0.thumbnailURL ?? $0.imageURL }
    }

    /// Whether the weight column shows an editable number field for this
    /// exercise. Always true for weighted exercises. Bodyweight exercises
    /// collapse to a "BW" label unless the user opted into weight entry or a
    /// set already carries a weight (a weighted round logged earlier).
    func showsWeightInput(exIdx: Int) -> Bool {
        guard session.exercises.indices.contains(exIdx) else { return true }
        let ex = session.exercises[exIdx]
        if !ex.isBodyweight { return true }
        if weightEntryExercises.contains(exIdx) { return true }
        return ex.sets.contains { !$0.weight.isEmpty }
    }

    /// Header text for the weight column: the exercise's unit normally, "BW"
    /// for a collapsed bodyweight exercise, "+lbs" once weight entry is shown.
    func weightColumnLabel(exIdx: Int) -> String {
        guard session.exercises.indices.contains(exIdx) else { return "lbs" }
        let ex = session.exercises[exIdx]
        if ex.isBodyweight {
            return showsWeightInput(exIdx: exIdx) ? "+lbs" : "BW"
        }
        return ex.unit.isEmpty ? "lbs" : ex.unit
    }

    struct ProgressionPillModel {
        let text: String
        let tint: Color
    }

    func computeProgressionSuggestion(for ex: LoggedExercise) -> ProgressionPillModel? {
        // Shared extraction: the heaviest set that MET target reps (so a
        // pyramid's heavy top single doesn't read as a missed target).
        guard let r = ProgressionSuggestion.suggest(
            prevSets: ex.prevSets,
            targetReps: ex.targetReps,
            exerciseName: ex.name,
            unit: ex.unit
        ) else { return nil }
        let weightStr = r.suggestedWeightString
        let label: String
        let tint: Color
        switch r.delta {
        case let d where d > 0:
            label = "SUGGESTED · \(weightStr) \(ex.unit) · \(r.label)"
            tint = .accent
        case let d where d < 0:
            label = "BACK OFF · \(weightStr) \(ex.unit) · \(r.label)"
            tint = .danger
        default:
            label = "HOLD · \(weightStr) \(ex.unit) — earn the reps"
            tint = .ink2
        }
        return ProgressionPillModel(text: label, tint: tint)
    }

    /// After the user edits a set's weight, copy the new value into any later
    /// sets in the same exercise that are still empty or still matched the
    /// previous value. Lets straight-sets users type once into set 1 and have
    /// 2-N fill in; pyramid users can still overwrite any later row by tapping
    /// into it (their edit propagates forward from there, or stops if the
    /// downstream sets have already been customized).
    func propagateWeight(exIdx: Int, fromSetIdx: Int, oldValue: String, newValue: String) {
        // The debounced caller can fire after an index change (delete/reorder),
        // so guard the exercise index before touching it.
        guard session.exercises.indices.contains(exIdx) else { return }
        let count = session.exercises[exIdx].sets.count
        guard fromSetIdx + 1 < count else { return }
        for i in (fromSetIdx + 1)..<count {
            let target = session.exercises[exIdx].sets[i]
            if target.done { continue }
            if target.weight.isEmpty || target.weight == oldValue {
                session.exercises[exIdx].sets[i].weight = newValue
            }
        }
    }

    /// Propagate the most-recent filled weight + reps into any empty set and
    /// mark every set in this exercise done. No haptic / rest side-effects —
    /// callers own those. Set 1 is usually pre-filled, so sets 2-N inherit even
    /// when the user only edited set 1.
    func markAllSetsDone(exIdx: Int) {
        var sourceWeight: String? = nil
        var sourceReps: String? = nil
        for set in session.exercises[exIdx].sets {
            if !set.weight.isEmpty { sourceWeight = set.weight }
            if !set.reps.isEmpty { sourceReps = set.reps }
        }
        for setIdx in session.exercises[exIdx].sets.indices {
            if session.exercises[exIdx].sets[setIdx].weight.isEmpty, let w = sourceWeight {
                session.exercises[exIdx].sets[setIdx].weight = w
            }
            if session.exercises[exIdx].sets[setIdx].reps.isEmpty, let r = sourceReps {
                session.exercises[exIdx].sets[setIdx].reps = r
            }
            session.exercises[exIdx].sets[setIdx].done = true
        }
    }

    /// True when this exercise belongs to a superset AND at least one
    /// sibling in the same group still has `set[setIdx]` un-done. Used to
    /// suppress the rest timer mid-round so it only fires after the last
    /// group member completes the round.
    func isMidSupersetRound(exIdx: Int, setIdx: Int) -> Bool {
        guard session.exercises.indices.contains(exIdx) else { return false }
        guard let group = session.exercises[exIdx].supersetGroup else { return false }
        let siblings = session.exercises.enumerated().filter {
            $0.offset != exIdx && $0.element.supersetGroup == group
        }
        guard !siblings.isEmpty else { return false }
        for (_, sibling) in siblings {
            // A sibling is "still owed this round" when it has a set at
            // this index that's not yet done. Siblings with fewer sets
            // don't gate the rest timer (their round ended earlier).
            if sibling.sets.indices.contains(setIdx), !sibling.sets[setIdx].done {
                return true
            }
        }
        return false
    }

    /// True when any exercise after `exIdx` in the session still has at least
    /// one un-done set. Used by the inter-exercise auto-rest path so we
    /// don't start a countdown after the very last set of the workout.
    func hasFollowingWork(afterExIdx exIdx: Int) -> Bool {
        guard exIdx + 1 < session.exercises.count else { return false }
        for ex in session.exercises[(exIdx + 1)...] {
            if ex.sets.contains(where: { !$0.done }) { return true }
        }
        return false
    }

    // MARK: - Formatters

    static func fmtTime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func fmtElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}
