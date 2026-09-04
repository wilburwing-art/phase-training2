# 05. Cold-install funnel

**Status:** closed 2026-09-03
**Lens:** experience

## Question

How many taps and how much reading stand between a fresh install and a first
logged set, and where would a stranger quit?

## Depth actually reached

Full, and measured rather than read. The repo already carries a committed tap
budget (`PhaseTrainingUITests/tap-budget-baseline.json`) and a UI test that
walks the minimal path. That test was run this session on an iPhone 17 simulator
and it **fails**, which turned out to be the most useful thing this critique
found. Screenshots were not captured: the flow does not reach the screens worth
photographing.

## The flow

Eleven steps, `OnboardingStep` (`OnboardingFlow.swift:15-36`):

| # | step | required? |
|---|---|---|
| 1 | welcome | tap through |
| 2 | sports | **gated** — `nextEnabled: !draft.sports.isEmpty` |
| 3 | sportSeasons | defaults |
| 4 | availability | defaults |
| 5 | equipment | defaults to bodyweight |
| 6 | experience | defaults |
| 7 | about (age, gender) | explicitly optional |
| 8 | eraAffinity | accept derived / pick / skip |
| 9 | constraints | `.disabled(!canCommit)` on the commit action only |
| 10 | coachConsent | **gated** — `nextEnabled: localOn != nil` |
| 11 | planPreview | Accept, enabled once generation finishes |

Committed budget: `onboarding-to-first-plan: 12` taps. Two gated steps, both
reasonable: you must say what you train for, and you must make an affirmative
choice about sending your data to an LLM.

## Findings

### F1 (critical, ship blocker) Onboarding cannot be completed by the UI suite, and CI has been red for at least thirteen consecutive runs

Run locally this session:

```
testTapBudget_onboardingToFirstPlan
  TapBudgetTests.swift:293: error: button 'onboarding-continue-planPreview'
  never became enabled within 15s
** TEST FAILED **
```

Checked against main's CI roster before attributing it, per
`attribute-red-tests-to-ci-baseline`. Latest run on main
(`33837141294`, 2026-09-04) fails with a roster of seven:

```
test_completeScreen_presentsWithKettle
test_planPreview_tapLiftDay_showsExercises
testBuildAndStartWorkoutRoutesIntoLiveLog
testTapBudget_buildAndStartWorkout
testTapBudget_discardWorkout
testTapBudget_onboardingToFirstPlan
testTapBudget_startSavedWorkout
```

`gh run list --workflow test.yml` shows **failure on every run back to
2026-08-29**, the full visible window, 13 runs. CI runs
`-retry-tests-on-failure -test-iterations 3`, so each of these failed three
times, which makes them persistent rather than rig flake.

### F2 (critical, cause) T0-5 gated the consent step and two onboarding walks were never updated

Both failing onboarding tests do the same thing:

```swift
counter.tap("onboarding-continue-coachConsent")   // TapBudgetTests.swift:292
step(app, "onboarding-continue-coachConsent")     // OnboardingPlanDetailUITests.swift:30
```

Neither picks a consent option first. `OnboardingCoachConsentScreen.swift:35`
is `nextEnabled: localOn != nil`, and `localOn` starts nil, so Continue is
disabled. The tap does nothing, the flow stays on step 10, and the assertions
that follow time out on a plan preview that never presents. That is exactly the
observed error text in both tests.

`5b761be` ("T0-5 consent was pre-ticked and wrong about what it sends") landed
**2026-08-24**. The CI failure window starts before the oldest run visible in
the list. The two facts line up.

This is a test-maintenance break, and the product behaviour is correct: a real
user taps one of the two options and continues. But it has cost thirteen red CI
runs, and it has kept the roster red long enough that a genuine regression
landing now would be invisible.

### F3 (high) The committed tap budget is stale and the mechanism that would catch it is non-gating

The baseline says 12. The minimal path now needs **13**: T0-5 added a required
consent tap that did not exist when the baseline was written.

The drift will not surface on its own. `scripts/quality/tap_budget_diff.py`
states in its own docstring that it "is NON-GATING by design (honors the
2026-05-31 track-don't-gate decision): it always exits 0", and the workflow step
is `if: always()` with no failure path
(`.github/workflows/test.yml:76-82`). Tracking rather than gating is a
defensible decision. The consequence here is that when the test that produces
the number stopped running at all, the tracker printed nothing and nobody was
told.

### F4 (high) Two of the eleven steps are asking a stranger for things a stranger will not want to give

- **eraAffinity** (step 8) asks a user who has been in the app for ninety
  seconds to express a preference about training eras. It is the app's most
  distinctive idea and the worst possible place for it. It is skippable, which
  helps, but it still costs a screen and a moment of "why are you asking me
  this" at exactly the point where a stranger is deciding whether this app is
  serious.
- **coachConsent** (step 10) is now a required, unskippable decision about
  sending body metrics and injuries to an AI, presented before the user has seen
  a single workout. The gating is correct for App Review (Guideline 5.1.2(i),
  named in the code) and it is the right ethical default. It is also a hard
  stop in front of the value, and the value has not been shown yet.

Both are placement questions, not existence questions. The plan preview at step
11 is the first moment the app shows what it is for.

### F5 (medium) Sports is the only content gate, and it is the one that matters

Worth recording as working. `OnboardingSportsScreen.swift:16` gates Continue on
a non-empty selection and auto-designates the first pick as primary if the user
does not choose one (`:21`). This closes the path where a user completes
onboarding with `primarySport == nil` and receives the empty "Rest / No
supported sport set" workout from `WorkoutGenerator.swift:82`, since the
authored selector also requires a non-nil primary sport.

### F6 (medium) The user sees ten questions before the first thing worth seeing

The plan preview is step 11 of 11. Nine question screens sit between the welcome
and the payoff. Given critique 01 F1, what arrives after those nine screens is
a week of four-exercise sessions where two of the three are identical.

## Refuted

- **"A user can finish onboarding without picking a sport."** They cannot. F5.
- **"The onboarding failure is something this session caused."** It is not.
  No code was changed this session, and the local failure is a member of main's
  pre-existing CI roster (run `33837141294`).
- **"The failing tests mean onboarding is broken for real users."** They do not.
  The break is in the test walks, which tap a button that T0-5 correctly
  disabled. A human picks an option and proceeds.

## Ordering

F2 is a two-line fix in two test files and it un-reds thirteen runs of CI. Do it
before anything else in this suite, because every other critique's
recommendations will land on a suite nobody can read.
