---
name: phase-training-coach-diff-apply-by-id-not-name
description: In phase-training2, the coach's WorkoutDiff deliberately PRESERVES the slot id across a swap (so the active session can map it back), but SessionStore.applyWorkoutDiffToActiveSession matches exercises by name.lowercased() instead of by id — so a coach SWAP mid-workout drops the old row and re-adds it fresh, LOSING the logged sets. Trigger when editing applyWorkoutDiffToActiveSession or WorkoutDiff, implementing the "dedup by ID not name" audit item, or debugging "coach swapped my exercise and my logged sets vanished" / coach diff apply / active-session identity in phase-training2 (or workout-plan). Skip for the chat-history wiring (coach-chat-history-wiring skill) and LLM refinement clobbering edits (llm-refinement-clobbers-edits skill).
when-to-use: Editing/debugging how a coach WorkoutDiff lands on the active session in phase-training2 — especially swap behavior or exercise identity matching.
---

# Coach diff → active session: match by id, not name

**FIXED 2026-06-05 (PR #46)** — this now documents the contract so it isn't regressed back to name-matching. `applyWorkoutDiffToActiveSession` matches by id (raw + `gex-` prefix) with a name fallback, and updates the name in place on a swap. Guard: `SessionStoreActiveSessionApplyTests` (10 tests incl. swap-preserves-sets, duplicate-name-no-collapse, genuine-add). The history below is why.

## The contract mismatch
- `WorkoutDiff.apply` swap (WorkoutDiff.swift:~95) builds the replacement as `GeneratedExercise(id: existing.id, name: to)` — **keeps the old slot id**, comment: *"keep slot id so SessionStore session id mapping holds."* So the diff is telling SessionStore to map by ID.
- `SessionStore.applyWorkoutDiffToActiveSession` (SessionStore.swift:~177,184) builds its `existing` map keyed by `ex.name.lowercased()` and matches `gex.name.lowercased()` — **by NAME, ignoring the preserved id.**
- Case-insensitive name matching itself is INTENTIONAL (WorkoutDiff.swift:9) — that's NOT the bug. The bug is name-vs-id.

## Consequence
A coach **swap** (Bench → Incline) produces diff.after with the old id but the NEW name. SessionStore keys existing by old name ("bench press"), looks up the new name ("incline press"), misses → treats it as a brand-new add (`id: "gex-\(gex.id)"`, empty prevSets) and the old LoggedExercise is never consumed → **dropped, logged sets lost.** `adjust` ops (sets/reps, name unchanged) work fine. Duplicate-named exercises also collapse in the name-keyed dict.

## The fix (when greenlit)
- The ids ARE comparable: session build sets `LoggedExercise.id = ExerciseTemplate.id` (SessionStore:~298); `GeneratedExercise.id` is the same space.
- Match `gex.id ↔ LoggedExercise.id` instead of name.
- **Wrinkle:** the new-add path prefixes `gex-\(gex.id)` (SessionStore:~204), an id-space seam for previously-coach-added exercises across diffs — reconcile it (stop prefixing, or strip on match) or the next diff won't re-match them.
- Gate: `SessionStoreActiveSessionApplyTests` + new cases: swap-preserves-sets, duplicate-name-no-collapse, genuine-add-still-adds.
- Not a mechanical one-liner — it's an active-session identity change; do it deliberately with tests, not in an autonomous loop.

## Second instance, 2026-09-04: priorBest / lastAttempt, and the ADDITIVE fix

The same defect lived in `GeneratorContext`: `priorBest` and `lastAttempt`
were keyed by `name.lowercased()` only, so a session logged as "Bench Press"
and a generated row named "Barbell Bench Press" (catalog id 900, joined by
`exercise_aliases`) never met, and the progressive-overload hint silently did
not render. Three tests pinned the raw key (`priorBest["bench press"]`), so
switching the key outright would have churned them and hidden any collision.

The fix that costs nothing: **write both keys, read id first.**

```swift
enum ExerciseKey {
    static func id(for name: String) -> String? {
        ExerciseLookupCache.shared.exercise(forName: name).map { "id:\($0.id)" }
    }
    static func lookup<V>(_ map: [String: V], name: String) -> V? {
        if let k = id(for: name), let v = map[k] { return v }
        return map[name.lowercased()]
    }
    static func store<V>(_ v: V, name: String, into map: inout [String: V]) {
        map[name.lowercased()] = v
        if let k = id(for: name), map[k] == nil { map[k] = v }   // never overwrite
    }
}
```

- Every existing reader and test keeps working because the raw key is still
  written.
- The `id:` mirror is only set when EMPTY, so newest-session-wins (decided by
  the caller's raw-key guard) is not undone by an older session under a
  different display name.
- Apply it at EVERY write site of the map, including the branch you forget:
  `buildPriorBest` has a loaded branch and a bodyweight branch, and the first
  pass mirrored only one.

Use this shape whenever a name-keyed map has to start matching by identity and
the old key has readers.
