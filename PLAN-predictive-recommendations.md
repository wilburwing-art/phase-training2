# Predictive workout recommendations from user behavior

Written 2026-09-25. Two parts. Part A is what the app captures today and the
near-term work that consumes it. Part B is the full idea list under an
unlimited-resources framing, kept here so nothing is lost when Part A ships.

Iteration starts on A1: the app already captures most of the behavior signal,
and the generator reads none of it.

---

## Part A: grounded plan

### The controlling fact

`TrainingMemory.exerciseAffinities` is written by three surfaces: the
mid-workout swap (`LogScreen`), the template-editor swap
(`TodayScreen+TemplateEditor`), and the action sheet's recommend more / less
rows (`ExerciseActionSheet`). `GeneratorContext.from` zeroes it unless
`includeParkedSignals` is true, and no production caller passes true. The T2-11
comment at `GeneratorContext.swift:244` records this as the parked adaptive
layer. `recentSoreAreas` and `stagnantExercises` are parked the same way.

So the first recommendation costs no new capture. It is a switch plus the
pool-weighting mechanic in `phase-training-generator-bias-weight-pool-not-reorder`.

### Signal inventory, by strength

| Tier | Signal | Where it lives | Consumed by | What it predicts |
|---|---|---|---|---|
| Did | Completed sessions, sets, loads | `SavedSession` (SQLite) | priorBest, lastAttempt, coach | Which exercises and loads stick; PR and progression |
| Did | Abandoned workout + typed reason | `pt_abandoned_workouts`, 90-day window | coach only | Sessions too long, wrong equipment, pain avoidance |
| Did | Missed workout + resolution | `pt_missed_workouts`, `SkipStreakDetector` | planner softens rotation, coach | Weekdays that never work |
| Chose | Swap away from X into Y | `exerciseAffinities`, `swapAwayCounts` | nothing in production | Exercises the user rejects and what they substitute |
| Chose | Wheel or override switch to a saved or sample workout | `overrides.customRoutineByDate` | plan application only | Plan rejection for that slot |
| Chose | Hand-built routines | `pt_custom_routines` | wheel options only | The strongest statement of what the user wants |
| Looked | Search terms, browsing, detail opens, routine previews | nowhere (`query` and `previewingStock` are `@State`) | nothing | Intent that never converted |

The Looked tier is the weakest signal and the only one with zero capture. A
search for "pull ups" during a bench swap may be a library-existence check.
Explore behavior earns weight when it converts: search, then detail open, then
add to routine or start session. Log the funnel and weight conversion.

### Where recommendations land

The recorded direction is authored spines with the engine as a within-program
assist. That rules out generating a predicted workout. Three surfaces fit:

1. **Which authored routine or session next.** 118 routines, 441 sport links in
   coach.db. Rank by fit as `AuthoredRoutineSelector` does, then by behavior:
   high-adherence completions up, previewed-never-started down, routines
   containing negative-affinity exercises down.
2. **Which substitution first.** `SubstituteExerciseSheet` ranks 1,795 curated
   rows by context tag. Re-rank with the user's swap history so their past
   swap target sits on top.
3. **Which days and how long.** Skip streaks already soften rotation. An
   abandon reason of `timeOut` predicts `sessionMinutes` is too high for that
   weekday. The coach asks; the planner does not act on its own.

### Mechanics

No backend, no analytics SDK, SENSITIVE fields never logged (`MemoryStore.swift`
header). Everything is on-device. Per-user N is a few sessions a week, so the
learning artifact is counts and rules. Recency-weighted counters with a 28-day
half-life over a small typed event log. Elimination rules over scores: "never
offer an exercise swapped away three times" is learnable from three events.

### The densest label: planned versus actual

Every day has a planned session and sometimes a `SavedSession`. The diff (same
template, switched, exercises dropped, sets cut, load changed) arrives the same
day. `CoachContext+LoadBlocks.weekAdherenceSection` computes it as prose.
Persisting it per day as a structured record is the highest-value addition,
because it gives every other signal an outcome to be checked against.

### Traps (each already recorded in a skill)

- Bias the pool by multiplicity. `deterministicPick` is a uniform hash index,
  so a preferred-first sort does nothing.
- Keep behavior-derived preferences out of `planInputsHash`, or every swap
  rebuilds the current week.
- Wire both paths: `pickForSlot` and the accessory picker read the same
  `context` field.
- Never derive `experience` from behavior. Competency and readiness stay
  separate axes (`phase-training-personalization-two-axes`).
- Sample sessions on the wheel are demos. A switch onto one counts as plan
  rejection and never as preference for the sample's contents.
- Flipping `includeParkedSignals` costs regen time: `buildStagnantExercises`
  walks four weeks of sessions computing Epley 1RMs per regenerate. Measure
  before flipping; consider computing affinities alone.

### Order of work

- **A1. DONE 2026-09-25.** Affinities reach the season engine through
  `AthleteState.exerciseAffinities` (no parked flag needed). Comparator: a
  liked movement wins ties inside its recency tier; affinity <= -2 sinks below
  recent movements but never drops a demand it alone serves. The swap picker
  lists past choices first when the search box is empty. The substitute sheet
  was skipped: only the coach screen reaches it. Authored routines are
  untouched. The old consume tests had been skipping on an empty day and
  asserted nothing; replaced.
- **A2. DONE 2026-09-25.** `DayOutcome` is frozen at every session save
  (`SessionStore.onSessionSaved`, fired once per save) and kept on PlanStore
  under `pt_day_outcomes`, 90-day window, in backups. Classes: asPlanned,
  modified, switched, unplanned, abandoned, with swap pairs, drops, additions,
  and planned versus completed working sets. Frozen at save because both
  read-time sources decay: the week snapshot is replaced on every capture and
  the displaced original is cleared every Monday. Missed days stay in the
  missed log. No reader yet.
- **A3. DONE 2026-09-26.** One `ExploreSession` per visit to a browse surface
  (swap/add picker, Library, muscle list, workout category, override sheet),
  written on disappear only when the visit showed intent. Holds the last query
  (normalised, 60 chars), result count and search tier, opens and conversions
  each stamped with the query in force. `UserDatabase` table
  `explore_sessions` (migration v2), pruned to 90 days on open, wiped by
  `wipeAll`, not in backups, never leaves the device. Every picker caller
  states its conversion kind. Verified in the simulator: a Library search plus
  detail open and a Today swap each wrote one correct row. No reader yet.
- **A4. DONE 2026-09-26.** The coach asks; the planner never acts alone.
  `PatternEngine` (pure) turns 28 days of behavior into at most three
  suggestions for a new uncounted weekly-check-in pre-step, `.patterns`:
  sessions overrunning or stopped for time (accept plans shorter sessions),
  a planned exercise dropped 3+ times (accept sinks its affinity, reversible),
  a bundled routine opened on 3+ visits (accept saves it to the user's
  workouts). Decisions persist in `TrainingMemory.suggestionDecisions`; a
  dismissal is quiet for 8 weeks, an accept returns only if the evidence
  rebuilds from newer events. The coach drawer gets a PATTERNS block of
  outcome counts, top drops and swaps, and open suggestions, leaving browse
  data and search text out (not on the privacy policy). The insight pass is
  deliberately not fed, matching how it skips the missed and abandoned
  blocks. Verified in the simulator: seeded sessions produced both cards,
  accept set 30 minutes, dismiss recorded, and neither card returned.

---

## Part B: next-gen ideas, unlimited resources

### Roadmap and gates (2026-09-26)

What each idea needs that the app lacks today:

| Idea | Lacks | Owner decision |
|---|---|---|
| 1 digital twin | HRV, sleep, resting HR (HealthKit reads only workouts and body composition) | Only for the physiology step (B1c) |
| 2 counterfactuals | A twin that predicts | None |
| 3 context | Location, calendar, a route for snow-almanac data into the app | New permissions |
| 4 sensors | A watchOS target, Core ML models, labeled reps | Add a target |
| 5 cross-user | A backend, a new privacy posture, licensing | Backend and posture |

Order: B1a shadow twin (no decisions), B1b calibrated readiness only if B1a
beats the last-value baseline, B1c physiology inputs only if B1b's errors
cluster where physiology would explain them, then 2, 3, 4, 5.

### B1a result: NO-GO (2026-09-26)

Built: `TrainingLoadModel` (Banister fitness and fatigue per movement pattern
from working sets), a `TwinPrediction` frozen on every `DayOutcome`, a
`TwinScorecard`, a walk-forward `TwinReplay`, and a DEBUG-only scorecard in
Profile. Nothing user-facing.

Replay over the owner's Fitbod history (`workout-plan/data/fitbod-history.csv`,
5,013 loaded sets, 252 training days), fit on the 16 weeks before the final 8,
scored on the final 8 predicting each day from earlier data only:

| Predictor | Mean abs. error, top-set e1RM (lb) |
|---|---|
| Last value | 12.20 |
| Twin, default parameters | 12.36 |
| Twin, fitted | 13.41 |

Holdout pairs: 39. The fit chose (τF 28, τG 4, w 3, k 0.08), a corner of the
grid, which reads as fitting noise. By the rule written before the run, B1b
does not start. The frozen predictions keep accruing on real sessions, so the
question can be re-asked with in-app data; re-run the replay when a new
export exists rather than re-tuning against this one.

### Next: ship, accrue, review on 2026-10-24

Everything above reaches no data until a build carrying it is on the phone.
Build 143 ships A1 to B1a plus a DEBUG "Signals & shadow twin" readout in
Profile. Review four weeks after install, from a backup export:

- **Twin re-ask:** score `DayOutcome.twin` pairs (plus a fresh Fitbod export
  if one exists). GO needs the twin to beat last-value on at least 30 pairs;
  otherwise B1 is shelved here in writing.
- **Suggestions:** read `suggestionDecisions`. Cards fired, share applied. None
  fired in four weeks means the thresholds are too strict for one person's
  volume.
- **Explore:** zero-result queries are the catalog-gap list for the coachdb
  source pipeline.

Build 143 (`v1.1.0-build143`, 2026-09-26) carries A1 to B1a and the Signals
readout.

**B3 calendar slice: built 2026-09-26, after build 143** (owner approved the
calendar permission). The check-in's events step has "Find travel in my
calendar": on tap only, it reads next week on device, and hotel or rental
stays across a night, 2+ day all-day events with a location, 20+ hour timed
events across a night, and flights become `.outOfTown` days titled "Travel",
which the Planner already turns into a bodyweight session. Calendar text is
never stored or sent; the privacy policy has a Calendar section. Ships in the
build after 143.

Still parked: B1c behind B1b, B4 and B5 until single-user value is shown.

### Original idea list

Ranked. 2, 3 and 5 run on top of 1.

1. **Athlete digital twin.** A per-user fitness-fatigue model fitted per
   movement pattern to logged sets, HealthKit HRV, sleep, resting HR, and
   soreness check-ins. Predicts tomorrow's readiness, per-lift 1RM trajectory,
   overreach risk. Recommendation becomes the session with the best predicted
   adaptation recoverable by the next sport day. Needs the existing HealthKit
   import plus a fitting service. Estimate: 6 weeks to a calibrated first
   version.
2. **Counterfactual planner.** Run every planned day under its alternatives
   (skip, move, swap routine, cut to 30 minutes) through the twin and show the
   delta on the next sport day's readiness. The wheel becomes a comparison of
   futures. Needs 1. Estimate: 3 weeks after it.
3. **Context-aware pre-adaptation.** Location (gym, crag, hotel, trailhead),
   calendar travel, weather and snow at the user's resort via snow-almanac,
   live watch HR. Predict whether today's session happens at all and pre-swap
   it: hotel gym gets the equipment-swapped version, a powder day gets
   mobility. Needs a small on-device context engine. Estimate: 4 weeks,
   independent of 1.
4. **Zero-friction logging from sensors.** Watch motion classifies exercise
   and counts sets; camera reads bar speed for velocity-based autoregulation
   so load updates mid-set. Makes the Did tier ten times denser. Needs Core ML
   models and labeled reps. Estimate: 3 months.
5. **Cross-user learning over a licensed spine library.** Never generate, never
   blend. License hundreds of real coaches' programs (the MTN Tactical and
   Uphill Athlete archive already holds 277 sessions) and aggregate across
   users with privacy preserved: which spines similar athletes complete, where
   they abandon, which substitutions they accept. New users get ranked spines
   from their cohort on day one. Needs a backend and licensing. Estimate: a
   quarter, mostly deals.

Lower priority, kept:

- **Sport-outcome optimization.** Optimize for ski vertical, sends, Strava
  rides rather than gym numbers; correlate blocks with the following season.
- **Synthetic-athlete fleet.** Run recommender policies against simulated
  users on eval-rig before shipping.
- **Catalog embeddings.** Semantic search and "more like this" over exercises
  and routines.
- **Coach-mediated intent.** Repeated searches or previews become a question
  the coach asks ("you looked at hangboard protocols three times, want a
  climbing block?") rather than a change the planner makes.
