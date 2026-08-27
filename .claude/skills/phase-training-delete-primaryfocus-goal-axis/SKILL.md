---
name: phase-training-delete-primaryfocus-goal-axis
description: The complete consumer map for deleting the `PrimaryFocus` goal axis (6-case get-stronger/build-muscle/sport-performance/endurance/lose-weight/longevity enum + `focuses: [PrimaryFocus]` field) from the phase-training2 generator, once onboarding is gated to season-engine sports (ski/climb) and the legacy demographic generator is only a nil-sport fallback. Verified 2026-06-26 on feat/season-aware-generator (the M2c/M2d "goal-axis deletion"). Trigger when removing/finishing removal of PrimaryFocus or the goal/focus axis from phase-training, phase-training2, or workout-plan. Skip for WorkoutFocus (day type — stays) and for removing a single enum case (use swift-codable-enum-case-removal).
when-to-use: Deleting the entire PrimaryFocus goal axis from a phase-training-family generator after the app has been narrowed to season-engine sports, so the focus-driven legacy path is dead. You need the full list of wired consumers and the persistence-safety reasoning.
---

# Deleting the `PrimaryFocus` goal axis (phase-training2 M2c/M2d)

`PrimaryFocus` (the GOAL) ≠ `WorkoutFocus` (push/pull/legs DAY TYPE — keep it; deleting it cascades).
After M2b gates onboarding to ski/climb and `generateLift` dispatches via
`SportSeasonGenerator.supports(...)`, the legacy demographic generator only runs when
`primarySport == nil` (pre-sport onboarding/profile previews). So `PrimaryFocus` shapes no real
user's workout → full delete, not the frozen-shim that the pre-gate reuse-map assumed.

## Persistence correction (refines reuse-map trap #2)
You do NOT need a tolerant-decode shim. Swift's keyed decoder **ignores unknown JSON keys**, so
once you drop `focuses`/`primaryFocus` from `CodingKeys` + encode/decode, old saves that still
contain those keys load cleanly with no migration. (This is unknown *keys* — distinct from unknown
*raw values* inside an array, which DO throw; that's the case [[swift-codable-enum-case-removal]] covers.)

## Consumer map (grep `PrimaryFocus|primaryFocus|\.focuses`, exclude `WorkoutFocus`)
Generation path (commit as M2c-2):
- `WeeklyShape.swift` — `resolve(focus:)` param + `focusShapes` table + the focus fallthrough. Drop all; resolution becomes (sport,season)→(sport,.maintenance)→defaultShape.
- `Planner.swift` (~203) — the `focus: memory.primaryFocus` arg into `WeeklyShape.resolve`.
- `WorkoutGenerator+Prescription.swift` — `switch memory.primaryFocus` in `rpeTempoHints`; `focusBias(memory.primaryFocus,...)` in `prescription`; the `focusBias(_:isPrimary:)` func. Collapse to one neutral scheme; sets/reps/rest fall to `exercise.defaultSets`/`defaultSetsFromFormula`/coach.db.
- `WorkoutGenerator.swift` (~293,307) — the two `== .hypertrophy` accessory gates →
  `WorkoutGenerator+Accessories.swift` `appendHypertrophy{UpperPush,LowerBody}Accessories` become dead → delete.

Surface + type + persistence (commit as M2d):
- `TrainingMemory.swift` — `focuses` field, `primaryFocus` computed accessor, `enum PrimaryFocus`, the Codable keys/bodies.
- **`WeekPlan.swift` `planInputsHash` `"fc:\(focuses...)"` — easy to miss; dropping it triggers one benign regen on upgrade (correct).**
- `CoachContext.swift` (focus line), `OnboardingPlanPreviewScreen.swift` (dead `else` — sport always set now).
- `ProfileScreen.swift` (state + "Focuses" row + sheet + dev-preview seed), `ProfileScreen+RowSummaries.swift` (`focusesSummary`), delete `FocusesEditorSheet.swift` whole.

## File deletion + tests
XcodeGen path-based `sources` + gitignored `.xcodeproj` ([[phase-training2-gitignored-pbxproj]]) → delete
`FocusesEditorSheet.swift` from disk + `xcodegen generate`; no pbxproj edit.
~13 test files / ~100 refs reference the axis: delete focus-*assertion* tests (RpeTempoPrescriptionTests
focus cases, hypertrophy-accessory tests), strip the focus *dimension* from sweeps/invariants
(GeneratorSweepReportTest `primaryFocus` variants, GeneratorInvariantTest `mem(focus:)` loops over
`PrimaryFocus.allCases`), drop incidental `m.focuses = [...]` fixtures elsewhere. Verify via the
one-pass generator harness ([[phase-training-generator-strip-down-scope]]); confirm grep returns only `WorkoutFocus`.

Pairs with [[phase-training-season-aware-generator-reuse-map]] (the inverse — what stays).
