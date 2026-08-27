---
name: phase-training-test-by-coverage-not-canonical-name
description: When writing XCTest coverage for `WorkoutGenerator`'s accessory layer or stagnation swap in phase-training-family iOS apps, assert the *behavior invariant* (muscle covered, slot replaced) — NOT a specific canonical name from the accessory pool. The slot picker has multiple equivalent paths to the same muscle (e.g. picks "Triceps Extension" instead of the accessory pool's "Rope Pushdown"; picks "Dumbbell Standing Calf Raise" instead of "Standing Calf Raise"), so a canonical-name set check fails even when the desired coverage exists. Substring-match on the muscle name ("Lateral Raise", "Triceps"/"Pushdown"/"Skull Crusher", "Leg Curl", "Calf") is the right granularity. ALSO: for context-conditional tests (stagnation swap, sub-aware behavior) where coach.db data presence matters — ~439/572 exercises have substitutes (2026-06-07 backfill; the rest are the un-substitutable tail) — scan the baseline planner output for an exercise that actually has the relevant data, then mark THAT one as the test input. Don't blindly use `baseline.exercises.first` and skip when it has no subs. Trigger when adding XCTests against `WorkoutGenerator.generateLift` for accessory-layer / stagnation-swap / context-aware branches. Skip for prescription/sets/reps assertions (those genuinely are name-independent already).
---

# Test by behavior, not by canonical name

## The failure mode

Wrote a test asserting `names.isDisjoint(with: ["Rope Pushdown", "Overhead Cable Triceps Extension", "Skull Crusher"])` was `false` for a hypertrophy push day. Test failed. Picked names were `["Cable Lateral Raise", "Decline Bench Press (Barbell)", "Plank", "Push-Up", "Strict Military Press (Barbell)", "Triceps Extension"]`. The slot picker had already grabbed "Triceps Extension" — covering triceps — so the accessory layer's `existingMuscles.contains("triceps")` check correctly skipped appending "Rope Pushdown". Same on legs: picker grabbed "Dumbbell Standing Calf Raise" before the accessory layer ran. Behavior was correct; the test assertion was over-specific.

## The fix

Substring-match on the muscle:

```swift
let hasLateralRaise = names.contains { $0.contains("Lateral Raise") }
let hasTricepIsolation = names.contains {
    $0.contains("Triceps") || $0.contains("Tricep")
        || $0.contains("Pushdown") || $0.contains("Skull Crusher")
}
let hasHamstringIsolation = names.contains { $0.contains("Leg Curl") }
let hasCalfIsolation = names.contains { $0.contains("Calf") }
```

Keep the regression guard for the slug-disjoint double-append separately as `XCTAssertLessThanOrEqual(calfCount, 1)` — that one IS load-bearing (see `phase-training-accessory-layer-slug-and-difficulty-traps`).

## Stagnation-swap data scan

Don't write:
```swift
let first = baseline.exercises.first!
try XCTSkipIf(CoachDatabase.shared.substitutes(forExerciseId: first.exerciseId).isEmpty)
```
because some catalog exercises still have no subs in coach.db (439/572 covered after the 2026-06-07 backfill — ~23% uncovered, the un-substitutable tail). The test will silently skip on those and provide no real coverage.

Instead, scan for the first picked exercise that actually has subs:
```swift
let candidate = baseline.exercises.first { ex in
    !CoachDatabase.shared.substitutes(forExerciseId: ex.exerciseId).isEmpty
}
try XCTSkipIf(candidate == nil, "No picked exercise has subs; swap is a no-op")
```

`applyStagnationSwap` runs per-slot, not just slot 0, so any picked exercise with subs is a valid swap target.

## Verify

```
xcodebuild test -project PhaseTraining.xcodeproj -scheme PhaseTraining \
  -destination 'platform=iOS Simulator,id=<udid>' \
  -only-testing:PhaseTrainingTests/WorkoutGeneratorTests
```
Expect zero skips for the swap test and clean passes for the coverage tests across multiple coach.db churns.
