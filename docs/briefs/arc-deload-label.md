# Brief: label the automatic deload and let the lifter decline it (slot A)

## Backlog item

`docs/PLAN-gap-backlog-2026-11b.md`, Phase 7: "Show the arc deload and let the lifter decline it". Read that section first; its "Done when" list is the acceptance test.

## Problem

After three build weeks in a row `PlanStore.generate` passes `deloadWeek: true` to `Planner.generate`, which cuts sets by 0.7 and (with 3 or more lift days) turns one lift day into a "Recovery" rest day. No screen says so and the lifter cannot refuse it.

Tracing the code on 2026-11-13 found three faults in how the deload week is recorded. All three are fixed by the storage change below, and each gets a test.

1. **A deload week does not survive a second generate in the same week.** `generate` writes `lastDeloadWeekKey` with `today`. The next `generate` that week (tone picker, a day edit, a swap, any memory change) reads that marker, `PlanArc.signal` computes `weeksSince == 0`, the cooldown guard returns `.none`, and the week is rebuilt at full volume.
2. **A lifter with 2 lift days gets a deload every week with no end.** `demoteForDeload` needs 3 lift days, so no "Recovery" day appears, `isDeloadPlan` is false, the marker is never written, the cooldown never starts, and the deload week itself counts as a build week.
3. **`isDeloadPlan` matches on a rest day titled "Recovery"**, which `CNSBudgetEngine.swift:84` also writes.

## Design (fixed, do not redesign)

### 1. The per-week fact lives on `WeekOverrides`

`PhaseTraining/Data/WeekOverrides.swift`:

```swift
/// What the lifter's week does with the arc deload (PlanArc).
/// Raw-string cases: never remove one without a migration.
enum ArcDeloadChoice: String, Codable, Hashable {
    case applied   // the arc fired for this week and the week is lighter
    case declined  // the lifter tapped "Train normally"
}
```

New field on `WeekOverrides`: `var arcDeload: ArcDeloadChoice?`. It MUST be Optional (the `weekTone` pattern, see the comments on the neighbouring fields). nil means the arc has not fired for this week. `WeekOverrides` is replaced at the week rollover, which is the reset this needs. It is week-level, so `clearDate(_:)` does not touch it.

No field is added to `WeekPlan` or `DayPlan`. No `Planner.version` bump. No migration of a week that is already in a deload when the build lands.

### 2. One pure resolver in `PlanArc.swift`

```swift
struct ArcWeek: Equatable {
    /// Pass `deloadWeek: true` to Planner.generate.
    var deloadWeek: Bool
    /// This week counts as the deload for the four-week cooldown.
    var startsCooldown: Bool
}

static func resolve(choice: ArcDeloadChoice?, tone: WeekTone?) -> ArcWeek
```

Truth table (tone nil is Typical):

| choice | tone | deloadWeek | startsCooldown |
|---|---|---|---|
| nil | any | false | false |
| declined | any | false | false |
| applied | nil, typical, busy | true | true |
| applied | recovery | false | true |
| applied | build | false | false |

Reasons, for the code comment:
- Recovery tone already cuts sets by 0.7. Today the arc stacks a second 0.7 on top (about 0.49). The lifter's Recovery week is the deload, so the arc adds nothing and the cooldown starts.
- Build tone is the lifter saying the week is hard. The arc stands down while the tone is Build and the cooldown does not start. Picking another tone later in the week brings the deload back, because `applied` is still stored.

### 3. `PlanStore.generate` (`PlanStore+Generation.swift`)

Replace the arc lines with this order:

1. `weekStart = today.startOfTrainingWeek()`.
2. If `overrides.arcDeload == nil` and `planArcSignal(today:) == .deload`: set `overrides.arcDeload = .applied` and `saveOverrides()`. A stored `applied` or `declined` is never re-evaluated.
3. `let arc = PlanArc.resolve(choice: overrides.arcDeload, tone: overrides.weekTone)`.
4. Pass `deloadWeek: arc.deloadWeek` to `Planner.generate`.
5. Marker, after the plan is saved:
   - `arc.startsCooldown`: `defaults.set(weekStart.timeIntervalSince1970, forKey: Self.lastDeloadWeekKey)` (the week start, where the old code stored `today`).
   - otherwise, if the stored marker falls in the current training week: remove the key. This is what a decline and a switch to Build tone need. Removing is equivalent to restoring the earlier value: the arc could only fire because the earlier marker was absent or at least four weeks old.

Delete `isDeloadPlan`. Nothing else calls it.

`planArcSignal(today:)` stays as it is. With `applied` stored, step 2 never reaches it again that week, which is what fixes fault 1.

Add to `PlanStore` (same file):

```swift
/// True when the arc deload is what makes this week lighter.
var isArcDeloadWeek: Bool {
    PlanArc.resolve(choice: overrides.arcDeload, tone: overrides.weekTone).deloadWeek
}

/// "Train normally this week": regenerate without the arc deload.
func declineArcDeload(memory: TrainingMemory, today: Date = Date()) {
    updateOverrides(memory: memory, today: today) { $0.arcDeload = .declined }
}
```

`Planner.generate`, `demoteForDeload` and `scaleForDeload` are not edited. `WeeklyCheckInFlow` is not edited (see Out of scope).

Check every place that builds or rewrites the current week's `WeekOverrides` in place (`adoptLastWeekShape`, `replanAfterMove`, `swap`, the Week day edit sheet) and confirm each mutates the existing value through `updateOverrides`, so `arcDeload` carries over. Report what you found. Fix only a site that drops the field.

### 4. Today eyebrow (`PhaseTraining/Screens/TodayScreen+Derived.swift`, `phaseEyebrow`)

Append " · DELOAD" when `planStore.overrides.weekTone == .recovery || planStore.isArcDeloadWeek`. Rewrite the doc comment above it: DELOAD shows for a Recovery-tone week and for a week the arc made lighter.

Move the string logic into something a unit test can call with no view: a static function taking season label, sport short name and a `showsDeload` Bool (put it wherever fits the file's existing structure), and have `phaseEyebrow` call it.

### 5. Week tab notice (`PhaseTraining/Screens/WeekScreen.swift`)

A new `private struct ArcDeloadBanner` beside `MoveBanner`, with the same chrome (surface background, 0.5 line stroke, radius 8, padding 10 by 8). It sits in `content(plan:)` after the `MoveBanner` block and before the `GeometryReader`, with `.padding(.horizontal, 16).padding(.bottom, 8)`, shown when `planStore.isArcDeloadWeek`.

- Left: `Text("Three hard weeks in a row, so this week is lighter")`, `.styled(.monoXS)`, `Color.ink`, `lineLimit(2)`, `fixedSize(horizontal: false, vertical: true)`, leading aligned, `accessibilityIdentifier("arc-deload-notice")`.
- Right: a button titled "Train normally", styled like `MoveBanner`'s "Re-plan week" button, `accessibilityLabel("Train normally this week")`, `accessibilityIdentifier("arc-deload-decline")`. It calls `planStore.declineArcDeload(memory: memory.memory)`.
- No identifier on the container (same reason as `MoveBanner`).
- It does not dismiss itself. It stays while the week is an arc deload and goes when the lifter declines.
- No confirm dialog and no undo. A lifter who wants the light week back picks the Recovery tone.

The short button title is the lead's call: the full sentence and "Train normally this week" do not fit one row at `monoXS`, and a second row takes height from the seven day rows.

### 6. Stale docs in the same change

- `PhaseTraining/Data/PlanArc.swift` header comment: drop "invisible to the user" and say the week is labelled on Today and Week and can be declined (decided 2026-11-13).
- `.claude/skills/phase-training-periodization-model-no-auto-deload/SKILL.md`: the "landmine" section says no auto-scheduled deload exists. Correct it: `PlanArc` applies a deload after three build weeks with a four-week cooldown, stored per week as `WeekOverrides.arcDeload`, shown as DELOAD on Today and a notice on Week. There is still no "week N of M" counter. Keep the rest of the skill. Do not rename the skill folder.
- No em or en dashes in any string, comment or doc you write.

## Skills to load

`phase-training-overrides-persist-intent-not-output`, `phase-training-planstore-mutation-seams-and-week-caps`, `phase-training-xcodebuild-test-failed-grep-full-log`, `phase-training2-gitignored-pbxproj`.

## Files to touch

Edited: `PhaseTraining/Data/PlanArc.swift`, `PhaseTraining/Data/WeekOverrides.swift`, `PhaseTraining/Data/PlanStore+Generation.swift`, `PhaseTraining/Screens/TodayScreen+Derived.swift`, `PhaseTraining/Screens/WeekScreen.swift`, `.claude/skills/phase-training-periodization-model-no-auto-deload/SKILL.md`, `PhaseTrainingTests/PlanArcTests.swift`, `PhaseTrainingTests/WeekOverridesClearTests.swift`.

New: `PhaseTrainingTests/ArcDeloadWeekTests.swift`.

Do not touch `docs/`, the backlog, `Project.yml`'s build number or `Planner.swift`.

## Tests

`PlanArcTests` (add):
- `test_resolve_truthTable`: every row of the table in section 2.

`WeekOverridesClearTests` (add):
- `test_decodesLegacyPayloadWithoutArcDeloadKey`: encode, strip the key through `JSONSerialization`, decode, the other fields survive. Copy `test_decodesLegacyPayloadWithoutKeptLiftIndexKey`.

`ArcDeloadWeekTests` (new). Store-level, on a `PlanStore` with its own `UserDefaults` suite and a `SessionStore`, seeded with three past build weeks so `planArcSignal` returns `.deload` (the snapshot and session helpers in `PlanArcTests` show the shape; `PlanStoreSeamsTests` shows the store setup). These are unit fixtures. Use a profile with 4 lift days unless the test says otherwise.
- `test_arcFires_marksWeekAppliedAndShowsDeload`: after `generate`, `overrides.arcDeload == .applied`, `isArcDeloadWeek`, the marker equals the week start, and the eyebrow function returns a string ending in "DELOAD".
- `test_deloadSurvivesSecondGenerateInSameWeek`: generate twice; the second plan is still a deload (total lift sets equal the first deload plan's, and lower than a plan generated with `arcDeload = .declined`). Fault 1.
- `test_twoLiftDays_cooldownStarts`: a 2-lift-day profile; the marker is written, and a `generate` for the following week does not deload. Fault 2.
- `test_decline_regeneratesWithoutDeload`: `declineArcDeload`; `overrides.arcDeload == .declined`, `isArcDeloadWeek` false, no rest day titled "Recovery" that the arc put there, total lift sets higher than the deload plan's.
- `test_decline_survivesLaterRegens`: decline, then `updateOverrides` with a tone change to Busy and back to nil, then a plain `generate`; still declined and not a deload.
- `test_decline_doesNotStartCooldown`: after a decline the marker key is absent, and `planArcSignal` for the following week (with that week also a build week in the seeded history) returns `.deload`.
- `test_recoveryTone_doesNotStackAndStartsCooldown`: arc fires with tone Recovery; `Planner.generate` got no arc deload (total lift sets equal a Recovery-tone plan generated with no arc), `isArcDeloadWeek` false, marker written.
- `test_buildTone_suspendsArc_andTypicalBringsItBack`: arc fires, tone set to Build: not a deload, marker absent. Tone set back to nil: deload again, marker written.
- `test_eyebrow_deloadForRecoveryToneAndForArc`: the static eyebrow function, three cases (neither, tone, arc).

If seeding a real `.deload` signal through the store turns out to need a hook the store does not have, write `overrides.arcDeload = .applied` directly for the tests that only need the applied state, keep at least `test_arcFires_marksWeekAppliedAndShowsDeload` and `test_decline_doesNotStartCooldown` on the real signal, and say which tests used which route.

## Build and test

Slot A only. Never use another simulator or DerivedData path.

- Simulator: iPhone 17 Pro, UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`
- `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`
- Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'` and that `-derivedDataPath`.

Steps:

1. `xcodegen generate` after adding the test file.
2. One `xcodebuild test` call, full log to a file in your scratchpad, grepped as the skill says, with:
   - `-only-testing:PhaseTrainingTests/ArcDeloadWeekTests`
   - `-only-testing:PhaseTrainingTests/PlanArcTests`
   - `-only-testing:PhaseTrainingTests/WeekOverridesClearTests`
   - `-only-testing:PhaseTrainingTests/WeeklyCoachIntentTests`
   - `-only-testing:PhaseTrainingTests/PlanStoreSeamsTests`
   - `-only-testing:PhaseTrainingTests/BackupPlanStateTests`
   - `-only-testing:PhaseTrainingTests/SportProfileTests`

Do not run the UI test target or the full unit suite. Do not walk the simulator; the lead does that. Do not commit.

## Done looks like

- All seven classes pass, with the new tests counted in the report.
- `grep -rn "isDeloadPlan" PhaseTraining PhaseTrainingTests` returns nothing.
- No new compiler warnings in the files you touched.
- `Planner.swift` has no diff.

## Out of scope

A "week N of M" counter. The three-week rule and the cooldown length. Readiness or RPE as triggers. A week planned through the weekly check-in (`WeeklyCheckInFlow` calls `Planner.generate` with no arc and stages the result); list what you see there, do not change it. Undo for a decline. The `SeasonPhaseBadge` DELOAD word, which comes from the season engine's own mesocycle.

## Report

One final report, no interim messages: files changed, each test class with pass and fail counts, which tests used the real signal and which wrote `applied` directly, what you found at the override-rewrite sites in section 3, decisions made on anything this brief left open, and anything you noticed outside its scope (list it, do not fix it). If something here conflicts with the code you find, take the conservative option, record it, and keep going.
