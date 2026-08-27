---
name: phase-training-llm-refinement-clobbers-edits
description: >
  Diagnose why a workout edited in phase-training/phase-training2 (Week-tab
  "Override workout", custom-routine schedule, or substitute-exercise) reverts
  on its own 5-10 seconds after the user makes it. The cause is the background
  LLM refinement pass (PlanStore+LLMRefinement.swift) re-rolling the day. Trigger
  when the user says "my workout reverts", "it changes back after a few seconds",
  "my override doesn't stick", or any edit-then-silent-revert report in a
  phase-training-family iOS app with coach consent on.
when-to-use: >
  A user edit to a single day's workout disappears/reverts seconds later. Only
  reproduces with coach consent ON. Skip if consent is off (no refinement runs).
---

# phase-training: LLM refinement silently reverts user edits

## The mechanism
`PlanStore.generate()` and friends fire `kickOffLLMRefinementIfConsented` after
stamping the plan. The background task (`refineCurrentPlanWithLLM`) re-rolls
candidate days via `WorkoutGenerator.generateLift`, ignoring whatever the user
just set. The LLM API latency is ~5-10s — that's the revert delay.

## The load-bearing detail: the candidate filter
Candidates are chosen in `PlanStore+LLMRefinement.swift`:
```swift
guard day.kind == .lift else { return nil }
guard day.generatedWorkout != nil else { return nil }
if day.generatedWorkout?.refinedByLLMAt != nil { return nil }   // <-- the marker
```
`refinedByLLMAt == nil` means "not yet polished, eligible." The trap: paths
write a workout with `refinedByLLMAt = nil`, so they LOOK like fresh candidates:
- **Custom-routine override** (`composeWorkout(fromCustom:)`, Week-tab "Override
  workout") — never stamps it. THIS is the classic reported revert.
- **Coach-applied workout diff** (`applyWorkoutDiff`, from `MiniWorkoutDiffCard`
  "Apply") — old build-99 code *cleared* the flag + refired refinement "to
  re-personalize from the edited baseline," but `refineSingleDay` regenerates
  the day from scratch (never reads the edited exercises) → silent reroll.

NOT a trap: the Today-tab substitute (`TodayScreen.swapExercise`/`appendExercise`)
edits a LOCAL `@State editableTemplate`, guarded by `didModify` in
`onChange(of: template)` — it never writes the plan or triggers refinement.
Don't "fix" it. `regenerateToday`/`regenerateWeek` are test-only (no app callers).

## The fix pattern
Two seams, one principle: a user/coach edit is final — refinement must skip it.
1. **Override days** — exclude in the candidate filter:
   `if overrides.customRoutineId(for: day.date) != nil { return nil }`
   (`overrides` is reachable from the extension; written into
   `customRoutineByDate` BEFORE `generate()` calls kickOff, so the filter sees it.)
2. **Applied diffs** (`applyWorkoutDiff`) — STAMP `edited.refinedByLLMAt = Date()`
   (not nil) and DELETE the `kickOffLLMRefinementIfConsented` refire. The next
   full regen re-personalizes from scratch anyway.

Extract the predicate into `refinementCandidates(in plan:) -> [(index, day)]`
so both rules are unit-testable without a live `CoachClient`. No UI reads
`refinedByLLMAt` (verify with grep) — it's purely a refinement-exclusion marker,
so stamping it tells no UI lie.

## Verify
Build the repo you actually edited — session defaults may point at a different
worktree. Build explicitly: `xcodebuild build -project PhaseTraining.xcodeproj
-scheme PhaseTraining -destination 'platform=iOS Simulator,id=<sim>'`.
Confirm the symptom only repros with `CoachConsent` on.
