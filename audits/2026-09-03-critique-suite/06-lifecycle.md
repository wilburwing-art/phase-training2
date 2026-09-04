# 06. Lifecycle and recovery paths

**Status:** closed 2026-09-03
**Lens:** experience

## Question

What happens on day 8, day 30, after a missed week, mid-block injury, and after
a finished mesocycle? The screens have been critiqued; the sequences have not.

## Depth actually reached

Full code trace of all five sequences. **Not runtime-confirmed**: F1 below is a
chain of four verified facts about code that runs on a date boundary, and the
date boundary was not simulated. Every link is cited; the composition is
inference. Confirm it by setting the simulator clock forward eight days before
acting on it.

## Findings

### F1 (critical) The default-configuration user hits a dead Today screen on the Monday after their first week

Four verified links:

1. **Nothing regenerates a plan on a date change.** The three callers of
   `PlanStore.generate(from:)` are the Week tab's empty-state button
   (`WeekScreen.swift:86`), the end of onboarding (`OnboardingFlow.swift:172`),
   and a Combine subscription on `memoryStore.$memory`
   (`PlanStore.swift:385-394`). That subscription is gated on
   `needsRegeneration(for:)`, which is `plan.inputsHash != memory.planInputsHash`
   (`PlanStore.swift:634-637`) and has no date term. Unchanged profile means no
   regeneration, however old the plan is.
2. **Rollover snapshots the old plan without replacing it.**
   `captureRolloverIfNeeded` (`PlanStore.swift:333-346`) writes the past week
   into `pastPlans` and returns. `self.plan` still holds last week's days.
3. **The only thing that stages next week is the Weekly Check-In**, whose staged
   plan `promotePendingIfDue` installs (`PlanStore.swift:286`). The check-in is
   presented from exactly two places: a `#if DEBUG` UI-test launch argument
   (`PhaseTrainingApp.swift:430-437`) and the `plan-week` notification deep link
   (`PhaseTrainingApp.swift:498-500`). There is no date-driven in-app
   presentation.
4. **That notification is off by default.**
   `WeeklyReminderScheduler.isEnabled` is
   `UserDefaults.standard.bool(forKey: "pt_weekly_reminder_enabled")`
   (`WeeklyReminderScheduler.swift:35-36`), and `bool(forKey:)` returns false
   when unset. The user must find Profile, open Reminders, and turn on the
   Sunday 6pm reminder.

Composition: a user who completes onboarding and does not enable the reminder
reaches Monday with a plan whose dates are all in the past. `todayPlan` is
`planStore.plan?.today()` (`TodayScreen+Derived.swift:15`), which returns nil.
The upper-1 fallback that would rescue this is gated on `planStore.plan == nil`
(`TodayScreen+Derived.swift:52-54`), which is false, so `template` returns nil,
and `TodayScreen.swift:548` is `.disabled(template == nil)`.

The Start button is disabled, and nothing on the screen says why or offers to
generate. The recovery is to go to the Week tab, and the "Generate plan" button
there is inside an empty state that a non-nil plan should not render.

### F2 (high) The deload is a badge, not a program change

`MesocycleProgression` computes real cycle status: `deloadNextWeek`, `deload`,
`taper`, `peak`, with a 4-week meso off-season and pre-season, 6 in-season, and
maintenance explicitly off-cycle (`MesocycleProgression.swift:20-51`).

Its only non-test consumer is `Components/SeasonPhaseBadge.swift`. Grep for
`MesocycleProgression` across `PhaseTraining/` returns the type itself, the
badge, and three files where it appears only inside comments
(`PhaseRule.swift:11,101`, `AthleteState.swift:55`,
`SportSeason/SportSeasonModels.swift`).

`weekNumber` does reach the generator, through `AthleteState.weekNumber`, and
`SportSeasonGenerator` uses it in exactly one place: the deterministic seed
string, `"\(sportSlug)-\(season)-w\(weekNumber)-s\(sessionIndex)"`
(`SportSeasonGenerator.swift:45`). It changes which movements get picked. It
changes no set, no rep, no load and no volume cap.

So week 4 of an off-season block shows a DELOAD pill above a session carrying
the same prescription as week 1. The comments at `PhaseRule.swift:101` ("volume
cap dropped hard, progression holds — MesocycleProgression peaks it") describe a
wiring that does not exist.

### F3 (high) Nothing brings a lapsed user back

Three notification types exist and none of them is a re-engagement mechanism:

| trigger | purpose | default |
|---|---|---|
| `RestTimerState.swift:75-86` | rest timer expiry | in-session |
| `InactivityReminderScheduler.swift:24` | 30 minutes idle mid-session, "forgot to mark finish" | in-session |
| `WeeklyReminderScheduler.swift` | Sunday 6pm, walks next week's plan | **off** |

There is no "you have not trained in ten days", no streak, and no re-entry
prompt. The one weekly touch is opt-in and, per F1, is also the only thing
keeping the plan alive.

### F4 (medium) A mid-week injury does regenerate the plan, and that is a mixed blessing

Adding an injury changes `memory.planInputsHash`, so the Combine subscription
fires and calls `generate(from:)`, which rewrites the **entire week**
(`PlanStore.swift:392-393`). The debounce is 500ms and there is a guard against
regenerating during an active session (`:391`).

Two consequences worth naming. The good one: injuries reach the season pool
immediately, so the filter in critique 03 F1 applies from the next render.
The awkward one: a user who adds an injury on Thursday loses Friday and
Saturday's plan as they had arranged it, including manual moves, unless those
days are `protected`. The targeted entry points (`regenerateToday`,
`consolidateWeek`) exist for finer-grained cases and this path does not use
them.

### F5 (medium) Missed-workout handling is well built and lives behind a flow most users will not reach

`MissedWorkoutAutopilot` is careful work: a drop rule that declines to reshuffle
when the week has four or more lift days (`:84-88`), a budget, an escalation to
a consolidation offer (`:155`), and a fix for the case where a sport day was
logged through `SportLogSheet` and still read as missed (`:49-53`).

Its only callers are inside `Screens/WeeklyCheckIn/CheckInMissedScreen.swift`.
Given F1 and F3, the weekly check-in is reached by notification deep link only,
and the notification is off by default. The best-engineered recovery path in the
app sits behind the switch that is least likely to be on.

### F6 (medium) Four of the seven red CI tests are end-of-session failures

From main's CI roster (run `33837141294`), beyond the two onboarding tests
attributed in critique 05:

```
test_completeScreen_presentsWithKettle    — "finishing should present the complete screen"
testTapBudget_discardWorkout              — "Finish should auto-save and show the summary"
testBuildAndStartWorkoutRoutesIntoLiveLog — "Starting a built workout should route into the live log"
testTapBudget_buildAndStartWorkout        — same assertion
testTapBudget_startSavedWorkout
```

These are a different cluster from the onboarding pair and are **not** explained
by the T0-5 consent gate, because they launch with `--ui-test-onboarded` seeds.
Two distinct sequences are implicated: starting a built workout, and finishing
one. Both are the core loop. This critique does not have a root cause for them;
it establishes that they fail persistently (three retries each) and that they
are about the session lifecycle rather than a rig flake. Carried to critique 13
as the top open item.

## Refuted

- **"MissedWorkoutAutopilot acts on the plan unprompted."** It does not. Both
  entry points are proposal-shaped, and the accept happens in the check-in UI.
- **"Week rollover loses the old plan."** It does not.
  `captureRolloverIfNeeded` is idempotent, checks `pastPlans` for an existing
  snapshot, and runs before `promotePendingIfDue` so the outgoing week is
  captured before a staged plan replaces it (`PlanStore.swift:262-286`). The
  ordering comment says why, and the ordering is right.
- **"A stale plan falls back to the hardcoded upper-1 template."** It does not,
  and that is the problem. The fallback is gated on `plan == nil`, so it covers
  the pre-onboarding case and not the stale case.

## Ordering

F1 first, and the fix is small: make `needsRegeneration` consider whether the
plan's week is the current week, or present the check-in on a date condition
rather than only from a notification. Either one closes the dead-end and takes
F5's recovery machinery with it. F2 second, since a deload that does not deload
is the periodization claim failing at the one moment a user would check it.
