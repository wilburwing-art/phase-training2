# Handoff — branch `claude/pull-ups-search-issue-l78x5h`

Five user-reported fixes to exercise search and the workout log. Written for
whoever verifies them next.

## Read this first

**Nothing on this branch has been compiled or run.** It was authored in a Linux
container with no Swift toolchain, no `xcodebuild`, and no simulator. Every
claim about compilation is unverified. Claims about *behavior* are verified only
where this file says so, and only by the method it names.

So the first job is not to keep building. It is:

```
xcodegen generate     # REQUIRED: 5 new source files, pbxproj is gitignored
xcodebuild build-for-testing -project PhaseTraining.xcodeproj -scheme PhaseTraining \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
```

Expect compile errors. Fix them before trusting anything below. When running
tests, capture the whole log and grep it — `tail` hides unit-target failures
behind the UI target's summary:

```
xcodebuild test -project PhaseTraining.xcodeproj -scheme PhaseTraining \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' 2>&1 > /tmp/pt_test.log
grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" /tmp/pt_test.log
```

(See the `phase-training-xcodebuild-test-failed-grep-full-log` skill: no iPhone 16
simulator is installed, and a red run whose grep comes back empty is a simulator
flake, not a real failure.)

## What is on the branch

Five commits, oldest first. Each is self-contained.

| Commit | What |
| --- | --- |
| `f99b237` | Search: plural queries ("pull ups") and filter-blocked searches in the exercise picker |
| `e145bd4` | Search: vocabulary layer (abbreviations, synonyms) + a third matching tier |
| `dc64fbd` | Log: focusing a pre-filled weight selects it whole |
| `e551eff` | Log: reps forward-fill to later sets, same as weight |
| `d69989c` | Log: effort menu starts at RPE 5 instead of 6 |

New files (the reason `xcodegen generate` is mandatory):

- `PhaseTraining/Data/ExerciseSearch.swift`
- `PhaseTraining/Data/ExerciseSearchVocabulary.swift`
- `PhaseTraining/Components/View+SelectAllOnFocus.swift`
- `PhaseTrainingTests/SetPropagationTests.swift`
- `PhaseTrainingTests/LogEffortScaleTests.swift`

## What was actually verified, and how

**Search behavior: verified by replay, not by running the app.** The SQL, the
normalization, the fuzzy scoring and the partial scoring were reimplemented in
Python and run against the shipped `PhaseTraining/Resources/coach.db` over a
46-query sweep of real lifter phrasings. That is a faithful replay of the
algorithm, not of the Swift code: it proves the *rules* return sensible rows and
that no previously-working query regressed. It cannot catch a Swift-side
mistake (a wrong bind index, a typo in the WHERE builder). The unit tests in
`CoachDatabaseSearchTests` are what actually pin the Swift path — run them.

Before/after on the queries that drove the work, all against the real catalog:

| Query | Before | After |
| --- | --- | --- |
| `pull ups` | 0 (substring); fuzzy rescued it by luck | 7 |
| `pullups` | **0** | 7 |
| `dumbbell shoulder press` | **0** | 2 (Dumbbell Overhead Press first) |
| `db curls`, `kb swing`, `bb row`, `ohp`, `rdl` | 0 or junk | correct rows |
| `calves` | 1 junk row (Weighted CARVE Squat) | 13 calf movements |
| `weighted dips`, `flat bench`, `rear delt fly` | **0** | ranked partial matches |

**Log behavior: not verified at all.** Select-on-focus and reps forward-fill
were written from reading the code. The select-on-focus technique in particular
depends on SwiftUI's `TextField` still being backed by a `UITextField` that
posts `textDidBeginEditingNotification` — true today, widely relied on, but only
a simulator run proves it here. If it silently does nothing, the modifier
no-ops rather than breaking anything, and `testTappingPrefilledWeightSelectsItForOverwrite`
is what catches it.

## Where to look first if something breaks

Ranked by how likely it is to bite, most likely first.

1. **`CoachDatabase.searchExercises` return-type change.** The picker overload
   of `listExercises` was renamed to `searchExercises` and now returns
   `(exercises:tier:)`; `listExercises` is a thin wrapper that drops the tier.
   Every `return` inside that ~200-line function had to become a tuple. If one
   was missed, it is a compile error there.
   - Note the pre-existing overload pair: `listExercises(search:modality:)` and
     `listExercises(search:muscleSlugs:...)` are both callable as
     `listExercises(search: x)`, and Swift picks the first (fewer defaults
     filled). That is load-bearing for exact-name resolution and is unchanged —
     but if you touch those signatures, `ExerciseLookupCache`, `MuscleVolume`
     and the swap surfaces silently change meaning.
2. **`schedulePropagation` moved into a `LogScreen` extension.** It assigns to
   `@State` dictionaries from inside an escaping `Task` on a struct. That is
   legal (`@State`'s setter is `nonmutating`) and it is what the old inline
   closure did, but it moved, so it is worth a look if the compiler complains
   about mutation or capture.
3. **Type inference in the new code.** `searchTokens(name).map(Array.init)` is
   explicitly annotated `[[Character]]` in two places for this reason; the
   `SetColumn.keyPath` computed property returns bare `\.weight` / `\.reps` and
   leans on the declared return type. If either is ambiguous, annotate harder.
4. **`testSecondTapInFocusedWeightPlacesCaret`** (LogFlowTests) sleeps 0.8s
   between two taps to stay clear of the double-tap interval. If it flakes,
   delete it — it covers a nicety (tap again to place the caret), not the
   feature. Do not paper over it with a longer sleep.
5. **`testRepsFillForwardToLaterSets`** waits on an `NSPredicate` expectation
   because the fill is debounced 400ms. If it times out, check the debounce
   fired at all before assuming the wiring is wrong.

## Tests added, and what each one is for

`PhaseTrainingTests/CoachDatabaseSearchTests.swift` (+17)
: Plural queries reach singular catalog names; `singularStem` units; the
  vocabulary layer (abbreviation rewrites, irregular plurals, symmetric
  synonyms); the partial tier's scoring and ranking; tier reporting; and two
  cases pinning how filter-broadening and the partial tier compose.

`PhaseTrainingTests/SetPropagationTests.swift` (new)
: The forward-fill rule, asserted for weight and reps together in every case so
  the two columns cannot drift. Fills blanks, overwrites unchanged rows, stops
  at a customized row, never rewrites a logged set, only moves forward, no-ops
  on the last set / a stale index / an empty list.

`PhaseTrainingTests/LogEffortScaleTests.swift` (new)
: The contract that drifted, not just the new list — the effort menu must cover
  every RPE `DemandScheme` can prescribe, and must reach the effort the easiest
  RIR option describes. A future scheme below RPE 5 fails here instead of
  shipping an unloggable target.

`PhaseTrainingUITests/LogFlowTests.swift` (+3)
: Select-on-focus (type 145 over a pre-filled 135, expect 145), the second-tap
  caret case, and reps filling forward end to end.

`PhaseTrainingUITests/TapBudgetTests.swift` (changed)
: `testTapBudget_editWeightMidWorkout` lost its double-tap-and-Cut workaround,
  whose comment said the decimal pad had no select-all reaching this field.
  It now types straight over the value. Counted taps unchanged at 2; its
  existing `== "60"` assertion is now direct coverage of select-on-focus.

Also note `testGoldenPathWorkout` types 140 into a pre-filled cell. It now
produces "140" rather than "135140". It asserts nothing about the value, so it
should still pass — but that is the one behavior change to an existing test.

## Judgement calls worth a second opinion

These are defensible but not obviously right, and a reviewer may disagree.

- **The partial tier is deliberately loose.** "banana press" returns all 47
  presses. It only ever runs when everything else returned nothing, so the
  alternative is an empty picker, but there is no UI signal saying "these are
  closest matches" — the fuzzy tier has shipped without one for a while, so this
  follows that precedent rather than adding a banner.
- **Reps forward-fill treats pyramids like weight does.** Changing set 2 from 12
  to 10 also pulls set 3 to 10 if set 3 was still showing an inherited 12. That
  is the weight behavior, and matching it was the request, but it is the case
  most likely to annoy someone doing drop sets.
- **`selectsAllOnFocusInNumberFields` is scoped by screen + keyboard type.**
  A sheet over the log (the plate calculator) does not disappear the log, so its
  decimal field gets the behavior too. That was judged wanted, not a leak.
- **The synonym list is short on purpose.** Four equivalence classes
  (shoulder/overhead/military, lateral/side, rear/reverse, walk/carry) and ten
  rewrites, every one grounded in a query that returned nothing against the real
  catalog. Adding synonyms that match no catalog row is dead weight; adding ones
  that are merely *related* ("tricep extension" for "Tricep Pushdown", different
  movements) makes the picker lie.

## Not done

- No PR opened.
- `db/source/*.json` and `coach.db` are untouched. No catalog rows were added
  or edited; all five fixes are code-side.
