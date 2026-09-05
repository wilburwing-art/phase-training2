# R3 · 13 Test suite

State: CI `test.yml` run `33921643920` on `cb7a798` **success**. Locally the
unit target ran 1,075 passed / 0 failed before the R2-05 wiring, and the four
classes that wiring touches re-ran 94 / 0 after it. UI subset for the Today tab
(WorkoutWheel, BuildAndStartWorkout, TapBudget, KettleSport, ConsolidateFlow)
19 / 0.

Seven tests were added this range. Two of them have holes worth fixing before
they are trusted.

## F1 (high) — the floor test skips the failure it exists to catch

Cross-reference 03 F2, **downgraded 2026-09-05**.
`testInjuryFilterNeverLeavesASessionUnderTheMovementFloor` opens each case with
`if w.exercises.isEmpty { continue }`, so an injury filter that removes
everything would pass. Generating the worst case showed it does not empty the
session, it fills it with the wrong demand, so this is a latent hole rather
than an active blind spot. Still worth closing; the assertion that would have
caught the real failure is signature coverage, not emptiness, and that one now
exists as `test_everyFundedDemandRealizesASlot` plus the summary line 03 F2
describes.

## F2 (medium) — `test_pools_have_no_duplicate_exercise_ids` hardcodes the sport list

    for slug in ["alpine-skiing", "climbing"] {

`SELECT DISTINCT sport FROM sport_movements` returns exactly those two today, so
coverage is complete and the test would have caught the crash it was written
for. It rots the moment a sport is added, and it rots silently: the new sport is
simply not checked, and nothing says so. Drive the loop from the distinct sports
in the database instead. Same shape as the static candidate-path list that made
`design-check` skip for months in the atlas repos.

## F3 (medium) — a test-host crash reports as one failure

The duplicate `exerciseId` took the host down three times via
`Dictionary(uniqueKeysWithValues:)`, and the run summary read
`passed=1071 failed=1`. The real signal was three `Fatal error: Duplicate values
for key: '238'` lines in the log, not the counts. Any local gate that greps only
`Test Case .* failed` under-reads this. Add `Fatal error` to whatever the run
summary greps, alongside the existing `preflight checks` check for simulator
collapse.

## F4 (info) — three routine-shape tests now pin `.fullGym`

`testMTBPreSeasonRoutineBuildsRunnableWorkout`,
`testDistilledSnowboardRoutineBuildsRunnableWorkout` and
`testEasyStrengthBuildsRunnableWorkout` set `memory.equipment = [.fullGym]`
because an empty selection reads as bodyweight-only and the R2-05 pass would
swap or drop rows out from under an exact-count assertion. Correct, and worth
knowing: an equipment-unset `TrainingMemory` is not a neutral fixture on the
authored path any more, the way it already was not on the engine path.

## F5 (info) — what the new tests actually pin

`testAuthoredPathNeverServesEquipmentTheUserLacks` (5 sport/gear pairs x 5
phases x 3 slots), `testEquipmentGapIsFilledByASubstituteWhereOneExists`
(asserts a swap fires and that no substitute duplicates a movement already in
the session), `testResolvedRowsDriveBothSelectorAndBuilder` (the selector's
floor and the builder read the same rows), `test_hangboardAppearsInAtMostTwoSessionsAWeek`,
`test_sampleSwitch_stashesPlannedDayAndRestores`, `test_sampleIsDeterministicPerSeason`.
The bodyweight-only invariant in `SeasonInvariantTests` is now asserted on both
paths rather than reported as a count.
