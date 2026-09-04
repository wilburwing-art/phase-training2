# 13. Test-suite critique

**Status:** closed 2026-09-03
**Lens:** meta

## Question

90 test files and roughly 969 tests. Which subsystems could be deleted and still
leave the suite green? That answer is also the coverage gate blocking the Tier 3
architecture work.

## Depth actually reached

Full on the gate, on coverage mapping and on CI health. The coverage map is by
symbol reference rather than by line coverage: a type with zero mentions across
the unit target is genuinely untested, but a type that is mentioned is not
thereby well tested. `xcodebuild` coverage numbers were not collected.

Current size: **1,013 `func test` declarations** across 90 files in
`PhaseTrainingTests`, plus the UI target.

## Findings

### F1 (critical) The suite is red on main and has been for at least thirteen consecutive runs

Established in critique 05 and repeated here because it is this critique's
subject. Main's latest run (`33837141294`, 2026-09-04) fails with seven UI tests,
each having failed all three attempts of `-retry-tests-on-failure
-test-iterations 3`. `gh run list --workflow test.yml` shows failure on every run
back through 2026-08-29.

Two of the seven are attributable (critique 05 F2: T0-5's consent gate versus two
test walks that do not pick an option). The other five are an unexplained cluster
around starting and finishing a session:

```
test_completeScreen_presentsWithKettle     "finishing should present the complete screen"
testTapBudget_discardWorkout               "Finish should auto-save and show the summary"
testBuildAndStartWorkoutRoutesIntoLiveLog  "Starting a built workout should route into the live log"
testTapBudget_buildAndStartWorkout         same assertion
testTapBudget_startSavedWorkout
```

That is the core loop. Whether it is a rig problem or a real regression is the
top open question in this whole suite, and thirteen red runs is long enough that
nobody can currently tell.

### F2 (critical) The Tier 3 gate is not met, so the architecture work is still correctly blocked

The gate is five named tests (`audits/2026-08-23-backlog.md:205-210`):

| # | gate | status |
|---|---|---|
| 1 | SessionStore save/load round-trip incl. bodyweight sets **and warmup flags** | **partial** |
| 2 | Backup snapshot → wipe → restore over the T0-3 envelope | met |
| 3 | `wireHistory()` contract: role alternation + empty-assistant filtering | **not met** |
| 4 | Season-pool health across ALL plannable sports | met |
| 5 | StrengthStandards matcher table | met |

- **Gate 1 partial.** Bodyweight has its own file (`LoggedExerciseBodyweightTests`),
  and `isWarmup` appears in eight test files, but zero of them is
  `SessionStoreTests`. The specific claim, that a warmup flag survives a save and
  load through `SessionStore`, is not asserted anywhere.
- **Gate 3 not met.** `wireHistory` appears **zero times** in
  `PhaseTrainingTests`. It is defined at `CoachConversationStore.swift:152` and
  called from `CoachDrawer.swift:352`, and it is the function that decides what
  conversation history goes over the wire to Anthropic. The gate item itself
  described it as "the untested wire contract" and it is still untested.
  Given critique 11, this is a privacy surface, not only a correctness one.
- Gate 4 is met by the T0-7 regression test that iterates what a user can
  actually pick, not by `test_catalog_pools_are_healthy`, which only walks the
  two hardcoded fixture sports (`SeasonFidelityTest.swift:81-87`).

Three of five, one partial, one absent. Tier 3 stays blocked, and gate 3 is the
smallest piece of work standing in the way.

### F3 (critical) The season engine, the only live generator, lost its invariant harness and never got it back

Commit `449bd8d` (2026-06-27, "remove the legacy demographic selection engine +
eval-rig") deleted three test files whole:

```
PhaseTrainingTests/GeneratorSweepReportTest.swift   902 lines
PhaseTrainingTests/EvalRigExportSmokeTest.swift     426 lines
PhaseTrainingTests/GeneratorInvariantTest.swift     312 lines
```

That was correct at the time: they tested the selection engine the commit
removed. What did not follow is a replacement for the engine that survived.

`SeasonFidelityTest` is real and good, and it is a fidelity test: 18 assertions
about demand mix and volume caps across two sports and five phases. It is not
the property-based invariant harness that `GeneratorInvariantTest` was, which
fuzzed a 486-cell grid for must-hold-for-all-inputs properties (sets in [1,8],
no empty day, no duplicate movement, non-empty reps, dislikes never leak) plus
the injury-contraindication safety invariant.

Concretely: the injury-contraindication invariant died with that file, and
critique 03 F1 found a live injury-filter hole on the authored path. An
invariant test that asserted "no contraindicated exercise appears in any
generated session, for any profile" would have caught it. Nothing asserts that
today.

### F4 (high) Several Tier 0 and Tier 1 fixes landed in files with zero unit-test coverage

Types with **zero mentions** anywhere in `PhaseTrainingTests`:

```
BackupCoordinator      CoachClient          CoachConsent       CoachDrawer
CoachSystemPrompt      CommonInjury         InsightGenerator   RestTimerState
InactivityReminderScheduler                 MissedWorkoutEntry TrainingConstraints
SportSeasonModels      MiniDiffCardChrome   MiniPlanDiffCard
MiniMemoryDiffCard     MiniWorkoutDiffCard
```

Cross-referencing against the fixes that landed in them:

| fix | file | tests |
|---|---|---|
| T0-1 gateway request ceiling | `CoachClient` | none; `dailyRequestCeiling` appears in zero test files |
| T0-2 erase-all store resets | `BackupCoordinator` | none; `EraseAllDataTests` tests the UserDefaults and SQLite wipes and never names the coordinator |
| T0-5 consent gate | `CoachConsent` | none |
| T1-2 rest-timer notification | `RestTimerState` | none |
| T1-46 diff-card re-entry guard | `MiniWorkoutDiffCard` | none |
| T1-47 insight sanitizer | `InsightGenerator` | none |
| T1-55 inactivity generation token | `InactivityReminderScheduler` | none |

Seven fixes from the ship-blocker and user-facing tiers, all unprotected against
regression. T0-1's ceiling is the sharpest: it is the only in-repo control on
LLM spend and nothing asserts it fires.

The four `Mini*DiffCard` views are worth calling out as a group. `WorkoutDiff`
and its builder are well tested (`WorkoutDiffBuilderTests`,
`PlanStoreWorkoutDiffTests`), and the cards that gate whether a proposal can be
applied are not tested at all. That is the boundary between the model proposing
and the app mutating.

### F5 (high) The build gate the backlog used excludes the target that broke

`audits/2026-08-23-backlog.md:19` sets the gate as "`xcodebuild test` on **the
unit suite**", and each tier's status reports against it ("969 unit tests
green", "972 unit tests green"). CI, by contrast, runs the whole scheme with no
`-only-testing`, so it exercises both targets.

The consequence is F1: a per-item gate that could not observe the suite the
change broke, and status notes that read as "green" while CI was red. The fix is
either to say "unit only" in the status line or to point the gate at the scheme.

### F6 (medium) The tap-budget tracker is non-gating and went silent rather than red

`scripts/quality/tap_budget_diff.py` "is NON-GATING by design (honors the
2026-05-31 track-don't-gate decision): it always exits 0", and its workflow step
is `if: always()`. Track-don't-gate is a defensible decision for a metric that
drifts.

The failure mode it did not anticipate: when the test that emits the
`TAP-BUDGET-JSON` marker stops running, the tracker prints nothing and reports
nothing. Three of the seven failing tests are tap-budget flows, so three
baselines have been unobserved for two weeks. A "flow expected but not seen"
line would cost one loop.

### F7 (medium) There are no Dynamic Type or accessibility tests

A grep for `dynamicTypeSize`, `accessibilitySize`, `AX5` or
`UICTContentSizeCategory` across the app and both test targets returns nothing.
Given critique 07 F1 (the type system cannot scale at all), a single test
asserting that a font resolves differently at two content-size categories would
have caught it at any point in the app's life.

## What holds up

- **1,013 unit tests is a lot**, and the areas that are covered are covered
  seriously: `WorkoutDiffBuilderTests`, `PlanStore*` (six files), `Planner*`
  (three), the Coach decoder and sanitization suites, the backup round-trip, and
  `SeasonFidelityTest`'s 18 phase-fidelity assertions.
- **The CI retry configuration is right.** `-retry-tests-on-failure
  -test-iterations 3` with the reasoning written into the workflow means a name
  in the failed roster failed three times, which is what made critique 05's
  attribution possible in one command.
- **Serial execution is documented with its reason** (`Project.yml:31-37`,
  the intermittent "0 results from CoachDatabase" flake). That is the right way
  to record a workaround.

## Refuted

- **"`test_catalog_pools_are_healthy` satisfies gate 4."** It does not on its own;
  it iterates two hardcoded fixture sports. The T0-7 regression test beside it
  iterates what a user can pick, and that is what meets the gate.
- **"`EraseAllDataTests` covers T0-2."** It covers the UserDefaults sweep and the
  SQLite wipe. T0-2's actual fix was adding `reset()` to three in-memory stores
  and calling them from `BackupCoordinator`, and no test names that coordinator.

## The smallest set that unblocks Tier 3

1. Fix the two onboarding test walks (critique 05 F2). One line each; un-reds
   two of seven.
2. Diagnose the five-test start/finish cluster. Until that is understood, no
   claim about suite health means anything.
3. Write gate 3 (`wireHistory` role alternation and empty-assistant filtering).
   It is a pure function over an array of turns.
4. Add warmup-flag assertions to `SessionStoreTests` to close gate 1.
5. Port an invariant test for the season engine, starting with the one that
   matters most and is currently absent: no contraindicated exercise appears in
   any generated session, for any profile, on **either** generation path.

Item 5 is the highest-value test in this list, because critique 03 F1 is the
defect it would have caught.
