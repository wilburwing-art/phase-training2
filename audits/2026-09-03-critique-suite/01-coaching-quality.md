# 01. Coaching quality of generated programs

**Status:** closed 2026-09-03
**Lens:** output

## Question

Are the programs this app emits good training? Not "does the generator do what
the code says" (`docs/generator-audit.md` answered that) but "would a competent
coach sign their name to the output".

## Depth actually reached

Full, on real output. `SeasonFidelityTest` already renders every (sport, phase)
session to `/tmp/season-fidelity/report.md`; it was run this session
(18 tests, exit 0, iPhone 17 sim) and every finding below is read off that
dump or off the shipped `PhaseTraining/Resources/coach.db`. No new harness was
written. Two sports and five phases are covered because that is the entire
live surface of the season engine.

## The surface is much smaller than the app suggests

Established before grading anything, because it changes what "the generator"
means:

- `449bd8d` (2026-06-27) deleted the legacy demographic selection engine. The
  season engine is the only generator (`WorkoutGenerator.swift:81`).
- The season engine has exactly **two movement pools**: `alpine-skiing` 44 rows
  and `climbing` 25 rows. `sqlite3 coach.db "SELECT sport, COUNT(*) FROM
  sport_movements GROUP BY 1"` returns those two rows and nothing else.
- `SportCatalog.isPlannable` (`AuthoredRoutine.swift:109`) means a user can pick
  exactly ten primary sports: three ski slugs, `climbing`, and the six in
  `outdoorAuthoredSlugs`. The other 25 entries of `Sport.catalog` are filtered
  out of onboarding (`OnboardingSportsScreen.swift:31`) and the profile editor
  (`SportsEditorSheet.swift:24`).
- Authored routines are tried **before** the engine for every sport
  (`WorkoutGenerator.swift:61`), and climbing is the declared pilot
  (`AuthoredRoutine.swift:50`), so authored content is preferred for climbing
  even though the engine supports it.

So the engine grades out on ski. Climbing's 25-row pool is reachable only
through a phase gap, and climbing has authored routines in all four labels its
five phases map to (`base` 1, `build` 2, `maintenance` 8, `off_season` 2), so
in the shipped build **the climbing season pool never serves a user**. It is
still worth grading because the pilot flag is one line and the pool is the
fallback if authored serving is ever disabled (`authored_routines_enabled`,
`AuthoredRoutine.swift:19`).

## Findings

### F1 (critical, quality) Every session is four exercises, in every phase, in both sports

The dump has no exception. Off-season, pre-season, in-season, maintenance and
event prep all render `4 ex`, for skiing and for climbing.

**Corrected 2026-09-03 during critique 12.** This was first written up as a
pool shortfall. It is not: the shortfall backfill landed as T1-52 and works
(`SportSeasonGenerator.swift:84-98`). The real mechanism is arithmetic.

`targetMovementCount` (`SportSeasonGenerator.swift:238-253`) is:

```swift
let minutes = preferredMinutes.map {
    min(max($0, ruleMinutes.lowerBound), ruleMinutes.upperBound)
} ?? ruleMinutes.upperBound
return max(3, min(6, minutes / 11))
```

`TrainingMemory.sessionMinutes` defaults to **45** (`TrainingMemory.swift:51`,
and the decoder falls back to 45 at `:209`). `AthleteState.from` passes it
through as `preferredSessionMinutes` (`AthleteState.swift:95`). Ski off-season's
band is `50...75`, so 45 clamps **up** to 50, and `50 / 11` integer-divides to
**4**.

The same arithmetic lands on 4 for every phase in the dump. A default-profile
user cannot get a 5- or 6-movement session from any phase whose lower bound sits
between 44 and 54, which is most of them. Reaching 5 needs a declared 55
minutes; reaching the cap of 6 needs 66.

So the four-exercise session is not a bug in the allocator. It is the default
profile meeting an integer division, and it is the input to every finding below.

### F2 (critical, quality) The demand-weight table is the app's design centrepiece and it does almost nothing

Every realized distribution in the report is `0.25 / 0.25 / 0.25 / 0.25`, with
every other demand at `0.00`. Ski off-season targets eight demands; four of them
(power 0.10, legEndurance 0.05, hipLateral 0.05, prehab 0.05) realize zero.
Climbing off-season targets seven; core 0.10 and prehab 0.05 realize zero.

With four slots the smallest expressible share is 0.25, so **any demand weighted
under a quarter is unreachable in a given session**, and the four that get
dropped are always the low-weight ones. `PhaseRule` hand-tunes roughly 80
weights across 2 sports x 5 phases. Most of them cannot change the output.

The damage is not random. The demands that round to zero are the corrective and
accessory work the objectives promise. Ski off-season's stated objective is
"Build max strength + muscle base, **fix imbalances**", and the two demands that
would fix an imbalance, `hipLateral` and `prehab`, are exactly the two at 0.00.

### F3 (critical, quality) A three-day week is the same workout three times

Ski off-season, verbatim from the dump:

```
Session 1: Barbell Back Squat, Pallof Press, Single-Leg RDL, Nordic Hamstring Curl
Session 2: Front Squat,        Pallof Press, Single-Leg RDL, Nordic Hamstring Curl
Session 3: Barbell Back Squat, Pallof Press, Single-Leg RDL, Nordic Hamstring Curl
```

Sessions 1 and 3 are identical. Session 2 differs in one slot. Event prep is
worse: sessions 2 and 3 are identical and session 1 differs in one slot. The
only varying axis is `recentMovementIDs` ordering, which moves the top slot and
leaves the tail fixed. A user paying for a training app gets the same four
movements every session of the week, and the week reads as a bug even when the
prescription is defensible.

### F4 (high, quality) Sessions run at roughly half the intended dose

| phase | fatigue cap | realized | minutes target | realized |
|---|---|---|---|---|
| ski off-season | 24 | 11 | 50-75 | ~33 |
| ski pre-season | 22 | 14 | 45-70 | ~44 |
| ski event prep | 14 | 9 | (see rule) | ~44 |
| climbing off-season | 18 | 8-10 | (see rule) | ~38 |

Off-season is the clearest: 46% of the fatigue ceiling and under the lower bound
of its own minutes band. The user asked for a 50 to 75 minute session and got 33
minutes. Nothing surfaces the gap. `enforceFatigueCap` never fired here (11 is well
under 24), and the backfill had nothing to backfill, because the allocator only
ever asked for four slots (F1). The second half of the gap is the heuristic
itself: `targetMovementCount` budgets "~11 min per movement", so it believes 4
movements fill 44 minutes, while `assemble` measures the same session at 33
(`SportSeasonGenerator.swift:358`). The estimator that sizes the session and the
estimator that reports it disagree by a third.

### F5 (high, quality) Ski off-season contains no upper-body work at all

Squat, Pallof Press, single-leg RDL, Nordic curl. No pull, no press, no vertical
or horizontal upper-body pattern, in the phase whose own objective says "muscle
base". Skiing is a lower-body sport and an off-season block is exactly where the
rest of the body gets trained. This follows from F2: with four slots the top
four ski demands are all lower-body or trunk.

### F6 (high, quality) The maintenance phase emits an eight-minute session and calls it a workout

```
Maintenance, cap 8 fp — 4 ex · ~8m · 6 fp
- Single-Leg RDL 1x8-12 · Single-Leg Glute Bridge 1x10-15
- Side Plank 1x10-15 · Lateral Lunge 1x10-15
```

Four single sets at RPE 5. As a deload prescription that is not unreasonable; as
a thing the app puts on a calendar day and asks the user to open, log, and
complete, it will read as broken. Worth checking against onboarding: if
`defaultSeason` lands a new user in maintenance, this is their first workout.

### F7 (medium, correctness) Prescription contradicts the stated objective in climbing off-season

Objective: "Pulling + finger base, **hypertrophy**, structural prep". Delivered:
`Dumbbell Single-Arm Row 4x4-6 @ RPE 7-8`, `Weighted Pull-Up 4x4-6`. Four to six
reps at RPE 7-8 is a max-strength prescription. Nothing in the session is in a
hypertrophy rep range except the antagonist slot at 2x10-15. Either the
objective string or the `DemandScheme` for `pullStrength` is wrong, and the
objective is the thing the user reads.

### F8 (medium, quality) Hangboard max hangs three sessions a week, all year

`Hangboard Max Hang (20mm Edge) 5x8s` appears in all three off-season climbing
sessions and again in pre-season. Finger tendon and pulley tissue adapts on a
slower timeline than muscle, and the standard protocols put max hangs at two
sessions a week with 48 to 72 hours between. Three a week in an off-season block
labelled "structural prep" is the prescription most likely to injure a user.
See critique 03 for the safety framing and 02 for how a climbing audience reads
it.

### F9 (medium, dead content) Four of 44 ski movements can never be selected

`aerobicUphill` carries four movements in the ski pool and appears in no
`PhaseRule` base weight table. It enters only through variant overrides for
backcountry and skimo (`PhaseRule.swift:201,203`). The generator always calls
`SportSeasonGenerator.defaultVariant(forSport:)`, which returns `.inbounds` for
every ski slug (`SportSeasonGenerator.swift:233`; the three call sites are
`Planner.swift:106,836` and `WorkoutGenerator.swift:92`), and no screen sets the
generator's variant. So 9% of the ski pool is unreachable in the shipped app.

### F10 (medium, consistency) The user can pick a climbing variant that the generator ignores

`SupportPatternEditor.swift:18` offers `.sportRoute`, `.boulder`, `.tradAlpine`.
The generator ignores the choice and builds `.sportRoute` sessions regardless,
because it resolves the variant from `defaultVariant(forSport:)` rather than
from the user's setting. A boulderer sets "boulder" and receives route training.

### F11 (medium, wiring) Readiness, soreness and the Coach's build_workout tool do not reach the live generator

`WorkoutGenerator.generateLift` accepts `context: GeneratorContext` and
`strategy: GeneratorStrategy` and the comment at `WorkoutGenerator.swift:76`
says both are "parked" and unconsumed by the season engine. The app collects
soreness (`SorenessCheckInSheet`), readiness (`ReadinessSignal`) and post-workout
feedback, and the only live generator does not read them. Flagged as a known
parked state rather than a surprise, but it belongs in this critique because it
is the difference between "adaptive coaching" and a static table, and the app's
surfaces promise the former.

## Refuted

- **"An outdoor authored sport with a phase gap falls through to the empty
  'Rest / No supported sport set' workout."** It does not.
  `AuthoredRoutineSelector.select` (`AuthoredRoutine.swift:67`) broadens to
  `allPhaseLabels` for any sport the engine does not support, then falls back to
  the `general-fitness` Easy Strength pool for the six `outdoorAuthoredSlugs`.
  The chain is guarded and commented. The empty-workout branch stays unreachable
  through this path.
- **"Only 6 of 128 sports with authored routines are exposed, so 90% of the
  authored content is dead."** The gate is real (`outdoorAuthoredSlugs`) but
  calling it dead content assumes the other sports are in scope. They are not:
  the app is positioned as a mountain-athlete tool and `isPlannable` is the
  deliberate expression of that. Carried to critique 10 as a positioning
  question, not recorded here as a defect.

## What would change the grade

F1 through F5 are one root cause with four faces, and F1 is now the cheapest
place to attack it: a default profile asks for four slots, and a four-slot
session cannot carry an eight-demand rule. Raising the movement count (round
rather than truncate, lower the 11-minute divisor to match the 33-minute
reality, or default `sessionMinutes` above the clamp) widens every session
immediately and costs one line.

That alone does not fix F3. Distinct sessions across a week need either more
movements per pool or an allocator that distributes demands across the week
rather than per session, so a demand weighted 0.10 appears in one session out of
three instead of never.
