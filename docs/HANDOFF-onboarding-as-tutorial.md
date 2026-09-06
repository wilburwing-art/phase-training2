# Handoff — branch `claude/onboarding-plan-interaction-fn3z4u`

Written for whoever picks this up next. Design rationale is in
`docs/PLAN-onboarding-as-tutorial.md`; this file is state, risk, and what to do
first.

## Read this first

**Nothing on this branch has been compiled or run.** It was authored in a Linux
container with no Swift toolchain and no `xcodebuild`. Every claim about
behavior is from reading the code, not from executing it.

So the first job is not to keep building. It is:

```
xcodegen generate      # REQUIRED: 6 files added, 14 deleted, pbxproj is gitignored
xcodebuild build-for-testing -project PhaseTraining.xcodeproj ...
```

Expect compile errors. Fix them before trusting anything below.

## Commits (oldest first)

| Commit | What |
|---|---|
| `fe6eb31` | Remove the training-era personalization axis |
| `820a0d5` | Scaffold the plan doc |
| `c666ade` | Cut onboarding to the gate; add assumption chips + setup checklist |
| `c9a0194` | Fix: keep the assumptions sheet host outside its own conditional |

49 files, +1033 / −2532.

## What changed, in one pass

**Onboarding is now 4 steps**: `welcome → sports → sportSeasons → coachConsent`.
The consent step's Continue commits, generates the first week, and dismisses.
Tap floor 12 → 6.

**Deleted**: the era axis entirely (`EraAffinity.swift`, `TrainingMemory.eraOverride`,
6 files), and 6 onboarding screens (availability, equipment, experience, about,
constraints, planPreview).

**Added**: `ProfileField.swift` (the assumed/stated model),
`PlanAssumptionsRow.swift` (Week-tab chips + `ProfileFieldEditorHost` +
`AvailabilityEditorSheet`), `SetupChecklistSheet.swift` (the permanent Profile
checklist), `OnboardingLandingUITests.swift`.

## Verification order

1. **Compile.** See above.
2. **Unit suite.** Highest-risk: `ProfileFieldCoverageTests` (Mirror-based, needs
   a Probe per stored property — `statedFields` was added, `eraOverride`
   removed), `ReadinessSignalTests` (two cohort tests replaced with flat-norm
   ones), `BackupManagerTests` (equipment fixture moved off the new default).
3. **UITest target, separately.** It is a different target and slow, so the unit
   suite going green proves nothing about it:
   ```
   xcodebuild test-without-building \
     -only-testing:PhaseTrainingUITests/TapBudgetTests/testTapBudget_onboardingToFirstPlan
   xcodebuild test-without-building \
     -only-testing:PhaseTrainingUITests/OnboardingLandingUITests
   ```
4. **By hand, on a wiped install.** The chips and checklist have never been
   rendered. Check: does the assumptions row actually appear on Week; does a
   chip open the right editor; does the chip disappear after an edit; does the
   row collapse cleanly when the last one goes.

## Where I'd expect to be wrong

Ranked by how likely it is to bite, given none of it ran.

1. **SwiftUI layout of the two new surfaces.** `PlanAssumptionsRow` sits inside
   `WeekScreen`'s `content(plan:)`, which is a fixed Mon→Sun layout deliberately
   sized by `GeometryReader` so all seven rows fit any device from SE up. I
   added height above that GeometryReader. On a small screen the seven day rows
   may now be squeezed below their 48pt floor, and there is no ScrollView to
   absorb the overflow. **This is the single most likely real defect on the
   branch.** In its favour: `PlanValidationBanner` already occupies the same
   position under the same constraint, so the pattern is not unprecedented —
   but that banner only appears on unhealthy weeks, whereas the assumptions row
   appears on every fresh install. Verify on an SE. If it bites, the fix is
   probably to overlay or collapse the row rather than let it take vertical
   budget from the day rows.
2. **`ProfileFieldEditorHost` presenting `EquipmentEditorSheet` from a chip.**
   Those editors were only ever presented from Profile. They set their own
   `presentationDetents`, and nesting a sheet-configured view inside another
   sheet presentation can behave differently than expected.
3. **`AvailabilityEditorSheet` is new UI I wrote blind.** Its stepper mirrors the
   deleted onboarding screen's, but it has never rendered.
4. **`OnboardingLandingUITests` element queries.** I guessed at
   `app.otherElements["week-day-row-0"]` vs `.buttons`, and hedged with an `||`.
   Tighten it once you can see which one actually matches.

## Decisions that are deliberate — don't silently revert

- **`equipment` defaults to `[.fullGym]`, not `[.bodyweight]`.** With the
  mandatory step gone, a silent user lives on the default forever. Conservative
  defaults are only free when something forces the question.
- **`statedFields` is NOT in `planInputsHash`.** That hash doubles as the
  `deterministicPick` seed, so adding presentation state to it would reshuffle
  the entire week the first time anyone opened an editor. This is exactly the
  bug the deleted era axis had.
- **Chips cover only availability / equipment / experience.** Age, gender,
  dislikes, injuries are intentionally excluded: an empty injury list is a real
  answer, not an assumption.
- **The plan-preview step was deleted, not given a second button.** It asked for
  a verdict the user couldn't form, on a plan that wasn't the one they'd get.
- **Coach consent stays a blocking step.** Moving it to first-coach-tap is
  defensible but is an App Store review question, not a refactor.

## Behavior changes a reviewer should know about

- Coach prose no longer carries an era vocabulary block.
- Readiness density norm is flat 3.0/wk for everyone (was a 2.5–4.5 age ladder).
  Users under ~40 score slightly denser than before, 70+ slightly sparser.
- `"er:"` left `planInputsHash`, so **every existing user takes a one-time plan
  regen** on first launch after this ships.
- Existing installs decode `statedFields` as fully-stated, so upgraders do not
  get assumption chips for values they picked by hand. Fresh installs start
  with nothing stated. Both paths were traced in `MemoryStore`; neither was run.

## Not done, on purpose

Slice 5 (just-in-time asks: equipment when a workout list first opens, injuries
in `PostWorkoutFeedbackSheet` after session one) is deferred. It needs an
ask-ledger — fired / dismissed / cooldown — or it becomes nagware. The chips and
checklist are the pull-based version; ship those and see whether push is even
needed before building the ledger.

## Two traps this branch already fell into, twice each

Worth internalizing before extending it:

1. **Deleting a screen orphans whatever only it wrote.** Era was the original
   orphan (an onboarding step with no Profile home, unreachable forever after).
   Then `startingState` was about to become one, and `EquipmentTier` was defined
   in a screen but consumed by two survivors. **Grep the writes before deleting
   any screen.**
2. **Onboarding step counts live in more places than you think.** The walk in
   `TapBudgetTests`, its doc comment, `tap-budget-baseline.json`,
   `OnboardingLandingUITests`, the tap-budget skill, AND user-facing copy on
   `OnboardingWelcomeScreen` ("Three quick questions"). That copy has been wrong
   twice in this repo's history.
