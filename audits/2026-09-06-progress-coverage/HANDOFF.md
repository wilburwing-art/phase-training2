# Handoff: Progress tab test coverage

**Branch:** `claude/workout-app-test-coverage-2hyesr` (8 commits, based on `main` @ `e19b385`)
**Date:** 2026-09-06
**State:** complete as authored, **not compiled and not run**

---

## The one thing to do first

**Nothing here has been built or executed.** It was authored in a Linux container
with no Swift toolchain and no `xcodebuild`, so every line is verified by
inspection only. Expect compile errors. Before reading anything else:

```sh
xcodegen generate
xcodebuild test -project PhaseTraining.xcodeproj -scheme PhaseTraining \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PhaseTrainingTests/ProgressStatStripTests \
  -only-testing:PhaseTrainingTests/ProgressGenderDisclosureTests \
  -only-testing:PhaseTrainingTests/ProgressBodyCardTests \
  -only-testing:PhaseTrainingTests/ProgressRecoverySectionTests \
  -only-testing:PhaseTrainingTests/ProgressFormattingTests \
  -only-testing:PhaseTrainingTests/ProgressAggregatesCharacterizationTests
```

Test sources are directory-globbed in `Project.yml`, so the new files need no
project edits (and `*.xcodeproj` is gitignored — do not commit one).

On a `xcodebuild ... TEST FAILED` with no visible failure, grep the full log
rather than the tail (`phase-training-xcodebuild-test-failed-grep-full-log`).

---

## Why this branch exists

An audit of the Progress tab found the **data layer well covered**
(`ProgressAggregates`, `MuscleVolume`, `MuscleFreshness`, `StrengthStandards`,
`allPersonalRecords`) and the **view layer on top of it completely uncovered**.
Every helper in the `ProgressScreen` extensions was `private` on a `View`, which
made it unreachable from a test — including two carrying explicit bug-fix
comments (the streak's bounded cursor, the recovery headline's `mainSlugs`
filter) and one user-facing claim about a user's body (the strength-tier gender
routing).

79 new tests across 7 suites.

| Commit | Suite | Tests |
|---|---|---|
| `b4fd00c` | scaffold (all 7, `XCTFail("scaffold")`) | — |
| `f5b1b9a` | `ProgressStatStripTests` | 13 |
| `a3ec37a` | `ProgressGenderDisclosureTests` | 11 |
| `c2246a7` | `ProgressBodyCardTests` | 15 |
| `63b06ac` | `ProgressAggregatesCharacterizationTests` (+2) | 2 |
| `67e4d9c` | `ProgressRecoverySectionTests` | 15 |
| `210bf2a` | `ProgressFormattingTests` | 17 |
| `2d7d461` | `ProgressScreenUITests` | 6 |

---

## Production changes, and why each was needed

The shape is the same throughout: **move a private View helper somewhere a test
can reach it, with `now` / `calendar` injectable**, and leave the call site as a
one-line delegate. Render behavior is unchanged.

### `PhaseTraining/Data/ProgressStats.swift` (new, ~240 lines)

Four groups, each moved verbatim from a `ProgressScreen` extension:

1. **Stat strip** — `sessionsThisWeekCount`, `currentWeeklyTargetStreak`,
   `prsInLastDays`. These called `Date()` inline, so any assertion would have
   been written against the real clock and flaked across a Monday midnight.
2. **Disclosure copy** — `strengthTierDisclosure(gender:)` (see below).
3. **Body cards** — `bodyFatSeries`, `leanMassSeries`, `latestBodyFatPercent`,
   `latestLeanMassKg`, `trendDelta`, `bodyWeightDeltaKg`, `latestBodyWeightKg`.
4. **Formatting** — `formatBigNum`, `daysAgo`, `isWithinDays`,
   `normalizedPoints`.

### `StrengthStandards.Curve` + `curve(for:)`

`tier` routed `.nonbinary` / `.preferNotToSay` to the female thresholds inline,
and the card separately *told* those users it does. Two halves of a claim about
someone's body with nothing holding them together. `curve(for:)` names the
routing, `tier` now uses it, and the copy is asserted against it.

### `ProgressRecoverySection` statics

`freshMainMuscleCount`, `highlights`, `daysSinceLastWorkout`, `subtitle`
promoted to statics beside the existing `mainSlugs` / `side(forSlug:)`.

### Two DEBUG launch seeds in `PhaseTrainingApp.swift`

- `--seed-progress-demo` — six saved sessions over five weeks with progressing
  weights, a bodyweight (so strength ratios un-hides), and body-weight +
  composition logs. **Sessions go in through the legacy `pt_sessions`
  UserDefaults key** that `SessionStore.init` already imports into `user.db`,
  rather than a second write path that could drift. `--ui-test-reset` wipes both
  stores and clears the migration flag, so the import runs.
- `--seed-body-only-demo` — body logs, no sessions, for the per-card gate.

---

## Two deliberate behavior deltas (both unreachable in the UI)

1. `deltaColor` returns `.ink3` for a single-entry weight log where it
   previously returned `.accent`. The delta chip only renders when a delta
   exists (count >= 2), so the branch cannot be hit.
2. `normalizedPoints`' doc comment claimed "flat series → all zeros" while the
   code returned `0.5`. **The code was right** — flooring a plateau pins the
   sparkline to the bottom edge and reads as a collapse in strength. The comment
   is corrected in both places and the behavior is now pinned by a test.

---

## Known risks, ranked

1. **The UI tests are the likeliest to need adjustment.** Card titles and seed
   behavior were inferred from source, never watched rendering. Failures carry
   an element dump (per `phase-training-xcuitest-recipe`) to diagnose
   missing-vs-renamed in one run.
2. **Baseline before blaming this branch.** *(Resolved 2026-09-09: the full
   UI suite was baselined on clean `main` — 43/43 pass on this machine, so the
   "five already fail" claim below no longer holds here. The five named suites
   presumably failed on the authoring machine's older baseline.)* Five UI tests
   were believed to fail on clean
   `main`: `BuildAndStartWorkoutUITests`, `KettleCompleteUITests`, and three
   `TapBudgetTests`.
3. **`MUSCLE BALANCE · 4w` and `STRENGTH RATIOS` need coach.db to resolve**
   "Barbell Bench Press" / "Barbell Back Squat". There is a known intermittent
   empty-catalog read under the xcodebuild runner
   (`phase-training-generator-sweep-harness-silent-exhaustion`); a re-run clears
   it. Do not treat one empty-catalog run as a regression here.
4. **Swift version is 5.9.** Multi-statement closure inference (SE-0326) is
   relied on in a couple of places; one was annotated explicitly to remove the
   question, the rest should be fine.

---

## Recommended next task (found, not fixed)

`SorenessReachabilityUITests.testSorenessCheckInIsReachableAfterASessionExists`
does not test what its comment claims. It launches with `--seed-plan-demo`,
whose `seedPlanDemo()` writes only a **week plan** — no `SavedSession` rows and
no body data. So `ProgressScreen.hasNonWorkoutData` is false, `savedSessions` is
empty, and the tab renders the **empty** branch, exactly like the test above it.
Its comment says it covers "the populated branch". It passes vacuously.

`--seed-progress-demo` now exists and does populate the tab. The fix is to swap
the launch argument in that one test. It was left alone deliberately to keep
this branch scoped to what was asked; it is a one-word change and the owner's
call.

---

## Scope boundary

This branch adds tests and the minimum extraction to make them possible. It
fixes **no** product behavior. The Progress tab's math is, as far as these
assertions go, correct as shipped.
