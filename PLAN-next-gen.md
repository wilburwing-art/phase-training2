# Next-gen roadmap: getting all of Part B done

Written 2026-09-26, the day build 143 shipped. This is the plan to finish every
idea in `PLAN-predictive-recommendations.md` Part B. It is ordered by
dependency, each step is the smallest slice that produces a measurable result,
and every step that needs a decision from Wilbur says so. Dates are estimates
and are marked as such; the gates are firm.

Standing rules this plan is built under:

- Authored spines, never generate, never blend (direction note, 2026-07-08).
  Every "recommendation" below ranks authored sessions or adjusts a knob; none
  writes a workout.
- Readiness is silent and competency is self-reported
  (`phase-training-personalization-two-axes`).
- A multi-day signal never lands on Today (`phase-training-tab-time-horizon-rule`).
- Nothing leaves the device except the coach snapshot, and only with the coach
  on. Any step that changes that says "policy change" and waits for a decision.
- Smallest measured tranche first; downstream stages proven on fixtures before
  they touch live data.

## Where things stand

| Track | Shipped | Build |
|---|---|---|
| Foundations (A1 to A4) | affinities steer selection, DayOutcome per session, explore log, check-in suggestions | 143 |
| 1 Twin | B1a shadow model, frozen predictions, replay, NO-GO on the Fitbod export | 143 |
| 3 Context | calendar travel on tap | 144 (next) |
| 2, 4, 5, and the three small ideas | nothing | |

The twin's first result: last-value baseline 12.20 lb MAE, twin 12.36 with
defaults and 13.41 fitted, 39 holdout pairs, fitted parameters on a grid
corner. That is the number every twin step below has to beat.

## Decisions only Wilbur can make

**All five answered yes on 2026-09-26.** Every gate below is now a data gate or
a build-order gate, never a permission gate. The policy, usage-string and
privacy-label work each decision implies is part of the first step that uses
it, and ships in that step's build.

1. **Apple Health physiology reads** (HRV, resting heart rate, sleep). Usage
   string, privacy-policy line, App Store privacy-label update. Unlocks 1c.
2. **Location while using the app.** Policy line and label. Unlocks 3c.
3. **A second network destination** for weather and snow (WeatherKit, or a
   snow-almanac feed). Policy change: today the coach gateway is the only one.
   Unlocks 3d.
4. **A watchOS target.** Unlocks all of 4 and the live-HR half of 3.
5. **A backend, a data-collection posture, and licensing outreach.** The
   privacy label moves from "data not collected". Unlocks 5.

## Track 1: athlete digital twin

Goal: a model that predicts tomorrow's readiness and each lift's trajectory
better than "same as last time", then a ranking of authored sessions by
predicted adaptation before the next sport day.

- **1a-2. Diagnose the NO-GO before adding inputs.** About 2 days, on the
  existing Fitbod export, no decisions. Score by exercise and by rep range
  (Epley loses accuracy above ~10 reps, so a high-rep target may be the
  noise); restrict the holdout to stretches with 2+ sessions a week, since the
  model assumes continuous training and the export spans ten sparse years;
  try predicting the direction of change rather than the magnitude; use RPE
  and RIR where the source has them. Gate to 1b: the twin beats the baseline
  on at least 30 pairs in a dense stretch, or the review on 2026-10-24 does
  with in-app pairs. **Done 2026-09-26:** a tie on size over 811 pairs, real
  signal on direction (58.1% over 752, about 4.4 standard errors). A direction
  criterion was registered for the review before any in-app data exists; see
  `PLAN-predictive-recommendations.md`.
- **1b. Silent readiness from the twin.** About 1 week. Replace
  `ReadinessSignal`'s unweighted session count with per-pattern load, behind
  the existing silent path (`AthleteState.readinessScore`). No UI. Gate to
  1c: after four weeks live, the twin's error clusters on days a physiology
  signal would explain (short sleep, high resting HR the night before).
- **1c. Physiology inputs.** Decision 1. About 2 weeks. HRV, resting HR and
  sleep from HealthKit joined to the soreness check-ins the app already has.
  Gate to 1d: the error on those clustered days drops.
  **Physiology capture: built 2026-09-26, for build 145.** Capture and store
  only. "Capture recovery data" in Health & Imports is the only place the
  HRV / resting HR / sleep grant is asked, separate from workouts and body
  metrics. `PhysiologySummariser` (pure) keeps one `PhysiologyNight` per wake
  day: mean SDNN from 18:00 the evening before to 12:00, the day's resting HR,
  and minutes asleep as the union of core, deep, REM and unspecified (in bed
  and awake excluded, overlapping sources counted once), with sample counts.
  30 nights on the first read, then incremental on foreground at most hourly,
  never prompting; stored under `pt_physiology_nights` (365-day window), in
  the backup, swept by the erase. Not in the coach snapshot; the privacy
  policy says so, and the App Store label is unchanged because nothing leaves
  the device (`docs/store/LISTING.md`). The Signals sheet shows nights and
  days with each signal. The reader waits for 6+ weeks of nights.
- **1d. Overreach risk and the adaptation ranking.** About 2 weeks. A per-week
  risk flag and a ranking of the authored sessions that fit the slot by
  predicted adaptation recoverable before the next sport day. Surfaces in the
  weekly check-in and the Week tab. Never on Today.

Kill rule: if 60+ in-app pairs still do not beat last-value after 1a-2, the
twin is shelved in writing and Track 2 runs on the existing `ReadinessSignal`
instead.

Build time about 5 to 7 weeks. Calendar time 4 to 6 months, because each gate
waits on live data.

## Track 2: counterfactual planner

Goal: "skip today and Saturday's readiness drops from 0.71 to 0.63", shown
where a seven-day consequence belongs.

- **2a. The engine, on fixtures.** About 1 week, no decisions, can start
  before 1b lands. `Planner.generate` is deterministic, so a pure function
  runs each planned day under skip, move, shorter, and a saved routine, and
  reports the readiness delta on the next sport day. Tested against synthetic
  weeks. It reads whichever readiness source is live, so it is useful even
  under the kill rule above. **2a: built 2026-09-26.** `Counterfactual`
  (pure) takes the week plan and the same events the live score is built
  from (`GeneratorContext.buildReadinessEvents`, now internal), projects each
  planned lift day before the next sport day, and scores the sport day under
  skip, move to each open rest day, half length, and each saved routine.
  It edits the plan's days rather than calling `Planner.generate`: the
  signal reads only timing, and a regen would reshuffle the week around the
  one change. On `ReadinessSignal` shorter and saved routine are honestly 0,
  since it ignores duration and content; the twin can fill them in. Tested on
  synthetic weeks; the DEBUG Signals sheet shows the largest-impact line.
- **2b. The surface.** About 2 weeks. Week tab first: each day carries its
  alternatives and the delta. The Today wheel showing "Saturday drops to
  0.63" is a seven-day consequence on a one-day screen, so it is a separate
  owner call after the Week tab version exists.

Gate: 1b GO, or the kill rule invoked with the fallback readiness.

## Track 3: context-aware pre-adaptation

Goal: know whether today's session will happen and pre-swap it.

- **3a. Calendar travel.** Done, ships in 144.
- **3b. Will today happen?** About 1 week, no decisions. A likelihood from
  the missed log, DayOutcome history, weekday skip streaks, calendar travel,
  and time of day. Feeds the coach block and the check-in. Nothing
  auto-moves.
  **3b: built 2026-09-26, for build 145.** `SessionLikelihoodEngine` (pure):
  a 90-day pooled rate of planned lift and sport days that happened
  (DayOutcome) versus were missed (missed log), Beta(3, 1) prior so no history
  reads 75%; the weekday's rate shrunk toward it by 4 pseudo-days; then x0.85
  for a weekday skip streak, x0.7 for a `.outOfTown` travel day, and, today
  only, a loss of 12% per hour past the usual start (median of the last 90
  days' session starts, 5+ needed) after a 1-hour grace, floored at 25%. Each
  step adds a plain reason. Feeds a TODAY'S SESSION LIKELIHOOD block in the
  coach drawer (context only, not quoted unprompted) and a quiet per-day
  percent in the check-in preview once 6+ planned days exist. Not on Today.
  The Debug Signals sheet shows today's estimate, its reasons and sample
  count. The constants are priors, to be checked against the eval-rig fleet.
- **3c. Location.** Decision 2. About 2 weeks. Home gym learned from where
  sessions were logged, geofences for gym, crag, trailhead. A session started
  away from the home gym gets the equipment-swapped version offered, on the
  existing substitution path.
  **Location capture: built 2026-09-26, ships in 145.** When a new session starts,
  `SessionLocationCapture` asks for one fix at `kCLLocationAccuracyHundredMeters`
  (`requestLocation`, 20 s timeout, never blocks the start). "While using" is asked at
  the first session start only; declined means nothing is captured and nothing is asked
  again. Each point (session id, time, lat/lon rounded to 3 decimals, accuracy) lands in
  `pt_session_places` on PlanStore, 365-day window, in the backup and swept by the wipe,
  never in the coach snapshot. `PlaceClusterer` (pure) groups points within 150 m into
  places with centroid, visit count and first/last seen; fixes vaguer than 1 km are
  skipped. The Signals sheet shows points, places and the top place's visits. Usage
  string and a Location section in the privacy policy; not declared in the privacy
  manifest because nothing leaves the device. The reader (home gym, swaps) waits for
  places to accrue.
- **3d. Weather and snow.** Decision 3. About 1 week after the route exists.
  A powder day at the user's resort offers mobility; a storm day at the crag
  offers the gym session.
- **3e. Live watch HR.** After 4a.

Build time about 4 to 5 weeks across the four slices.

## Track 4: zero-friction logging from sensors

Goal: the "did" tier ten times denser.

- **4a. Watch companion that mirrors logging.** Decision 4. About 4 weeks. A
  watchOS target that starts and ends sets, runs the rest timer, and writes
  the workout to HealthKit, which the app already imports. No ML yet. This
  alone removes most logging friction.
- **4b. Labeled motion, collected by the app itself.** About 2 weeks of build,
  then months of accrual. While a set is active on the watch the app knows
  the exercise, so every logged rep is a labeled sample. Stored on device.
- **4c. Motion classifier.** About 4 weeks once 4b has enough samples for the
  owner's top 20 exercises. Core ML on the watch, counts sets and reps,
  proposes the log entry for confirmation.
- **4d. Camera bar speed.** About 4 weeks, phone only, independent of the
  watch. Vision-framework barbell tracking from a propped phone, velocity per
  rep, and the load suggestion updates mid-set through the existing
  autoregulation path.

Build time about 3.5 months. Calendar time longer, because 4c waits on 4b.

## Track 5: cross-user learning over a licensed spine library

Goal: a new user gets ranked spines from their cohort on day one.

- **5a. Aggregates on device first.** About 1 week, no decisions. Which
  spines complete, where sessions abandon, which substitutions are accepted,
  computed from DayOutcome and the explore log for one user. This is the
  exact schema an upload would carry, proven before anything is uploaded.
- **5b. Licensing outreach.** Decision 5. Calendar time unknown. The 277
  MTN Tactical and Uphill Athlete sessions in the archive are personal-use
  reference material and cannot ship; a deal, or a different library, comes
  first.
- **5c. Backend and consented upload.** Decision 5. About 4 weeks. Opt-in,
  aggregates only, no free text, no session detail. Cloudflare already hosts
  the coach gateway and is the natural home.
- **5d. Cohort ranking.** About 3 weeks. Meaningless below roughly 50 active
  users per cohort; the gate is user count, not build time.

## The three smaller ideas

- **Embeddings for "more like this."** About 2 days, no decisions. Apple's
  on-device sentence embeddings over exercise descriptions; feeds the detail
  sheet and the substitution ranking. Can go in the next build after 144.
- **Sport-outcome optimisation.** About 2 weeks once the outcome fields exist.
  HealthKit ski workouts carry elevation; sends and rides need fields on the
  sport log (Strava would be decision 3's class of change). Correlates
  blocks with the following season.
- **Synthetic-athlete fleet on eval-rig.** About 1 week after eval-rig has a
  remote, which Wilbur has to create himself (`gh repo create` is blocked for
  the agent). The fleet drives `PatternEngine`, the twin and 2a as pure
  functions.

## Order of work (re-sequenced 2026-09-26: capture first)

The first version of this order put every capture step behind its owner decision. All
five decisions are now yes, so the order follows a different rule: **start every data
clock now, build the readers once the data has accrued.** The slow parts of this roadmap
are not build time. The twin needs in-app pairs, the physiology step needs weeks of sleep
and HRV beside sessions, the classifier needs thousands of labeled reps, and place
learning needs sessions logged at known places. None of those clocks starts until its
collector ships.

1. **Build 144 (shipped 2026-09-26).** Calendar travel, "more like this", twin diagnosis,
   on-device spine aggregates, and the validated fixes.
2. **Build 145, target 2026-10-17: start the data clocks.** Each item captures and stores
   only; the Debug Signals sheet gets a row per clock.
   - Physiology capture: nightly HRV, resting heart rate and sleep from Apple Health, a
     separate skippable grant, with the policy lines and privacy label.
   - Location capture: a coarse (~100 m) point at session start only, "while using"
     permission asked at the first session start, clustered offline into places.
   - 3b "will today happen?" likelihood, feeding the coach block and the check-in.
   - 2a counterfactual engine on fixtures, on `ReadinessSignal` until the twin earns it.
   - The eval-rig fleet (eval-rig now has a remote), driving `PatternEngine`, the twin, 3b
     and 2a on thousands of simulated weeks.
   About 4 weeks of work, so it may land after the review; the review then runs on 144.
3. **2026-10-24 review.** Criteria unchanged (size, and direction on 100+ in-app pairs).
   Physiology is not judged yet; its clock will have run under two weeks.
4. **Build 146, target mid-November: the watch.** 4a watch companion and 4b labeled motion
   capture in the same build, so the rep-labeling clock starts with the watch.
5. **Then, as data allows.** 1b per the review; the 1c reader after 6+ weeks of physiology;
   the 3c reader once places cluster; 3d weather via WeatherKit, then snow-almanac; 2b on the
   Week tab; 4d bar speed on the phone camera; 4c once the top 20 exercises each have enough
   labeled reps.
6. **Track 5 on calendar time, starting now.** 5b licensing drafts land in the repo for
   Wilbur to send (nothing is sent without his go). 5c backend waits for an answer to 5b and
   for user count.

Housekeeping to fold into 145: check the possible duplicate "Squat (Barbell)" beside
"Barbell Back Squat" and merge through the pipeline with an alias; add antagonist exercises
for SUP (0 against a floor of 5).

Calendar time runs longer than build time throughout, because the twin, the physiology
reader and the classifier all wait on data that accrues at the pace of real training.

## Next work after build 145 (written 2026-09-26)

Build 145 state: 3b, 2a, physiology capture, location capture and the housekeeping
(squat merge with alias, 6 SUP antagonists) are on `claude/elegant-brahmagupta-7ecbou`,
written without a local Swift toolchain. The privacy-label reasoning (on-device data is
not "collected") was confirmed by Wilbur on 2026-09-26. The eval-rig fleet is the one 145
item not started.

### 1. Land 145 (about 1 day)

- CI green on the branch (first compile of all four Swift slices).
- Simulator pass on the two new prompts, which no one has seen yet: the recovery-data grant
  from Health & Imports, and "while using" location at the first session start (decline
  path included: no second ask, nothing captured).
- Merge to main, bump the build number, tag. The Signals sheet should show five clocks.

### 2. Synthetic-athlete fleet (about 1 week, the last 145 item)

The contract stays JSON on disk, as both repos already require. The old adapter
(`EvalRigExporter` and its smoke test) is gone from phase-training2, so eval-rig's
ROADMAP "adapter: built" is stale; this replaces it.

- **eval-rig, personas.** `personas/*.json`, each with planted truths: per-weekday
  attendance rates, travel weeks, an overrun habit, one exercise that always gets dropped,
  a strength trajectory with noise, and clean control personas with no habits.
- **eval-rig, simulator.** `eval fleet simulate --personas N --weeks 26 --seed S` writes one
  JSON per athlete: planned weeks, saved sessions, DayOutcomes, the missed log and travel
  events, in the app's own Codable shapes. A shared JSON Schema plus a contract test on each
  side pins the shapes so Swift and TypeScript cannot drift silently.
- **phase-training2, replay.** `FleetReplayTest` (XCTest, reads the run directory from an
  environment variable, skips when unset so CI is unaffected) walks each athlete week by week
  through `PatternEngine`, the twin, `SessionLikelihood` and `Counterfactual`, and writes
  `predictions.json`.
- **eval-rig, scoring.** `eval fleet score <run>` reports: 3b Brier score and calibration by
  decile against the planted rates; PatternEngine recall on planted habits and its false
  suggestion rate on the clean personas; twin MAE and direction accuracy against
  last-value; 2a sign agreement with the simulator's own readiness rule.
- **Payoff.** Tune the 3b priors (75% start, streak 15%, travel 30%, 12% an hour late, the
  6-day check-in floor) from the calibration table, and set PatternEngine thresholds from
  false-positive rates instead of guesses.
- **Readiness truth: fitness-fatigue (Wilbur, 2026-09-26).** The simulator's
  `true_readiness` is a fitness-fatigue model, so a lighter few days before a sport day (a
  taper) raises it. The app's `ReadinessSignal` counts recency and density only, so a skip
  always lowers or holds it. The fleet treats fitness-fatigue as correct: 2a's
  disagreement on skip rows is scored as a real `ReadinessSignal` flaw, not tolerated as a
  model difference. Consequence: that disagreement rate is the first number 1b (per-pattern
  load in the silent readiness path) has to bring down, which argues for starting 1b before
  the 2026-10-24 review rather than after it.

**How to run the fleet.** The contract is eval-rig's `fleet/CONTRACT.md`; the replay lives
in `PhaseTrainingTests/Fleet/` (test target only, nothing ships).

1. In eval-rig: `npm run eval -- fleet simulate --athletes 50 --weeks 26 --seed 42`. It
   writes `fleet/runs/<run-id>/manifest.json` and `athletes/*.json`.
2. In phase-training2 (`xcodegen generate` first if the project is stale), with the run
   directory as an absolute path:
   ```
   TEST_RUNNER_FLEET_RUN_DIR=/abs/path/to/eval-rig/fleet/runs/<run-id> \
     xcodebuild test -project PhaseTraining.xcodeproj -scheme PhaseTraining \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     -only-testing:PhaseTrainingTests/FleetReplayTests/testReplayRunDirectory \
     CODE_SIGNING_ALLOWED=NO
   ```
   xcodebuild strips the `TEST_RUNNER_` prefix, so the test sees `FLEET_RUN_DIR`; without
   it the test skips, which is why CI is unaffected. It writes `predictions/<id>.json`
   (engine_build "145") next to `athletes/`.
3. In eval-rig: `npm run eval -- fleet score <run-id>`, which writes `report.md`.

### 3. Review on 2026-10-24 (unchanged)

Size and direction on 100+ in-app pairs. Physiology is not judged; its clock has run under
four weeks.

### 4. Build 146, the watch (target mid-November)

4a and 4b together, as ordered above. One item to decide before it starts: 4a writes the
workout to HealthKit, and today the app is read-only, with a usage string and policy that
say it never writes. That needs a new `NSHealthUpdateUsageDescription`, a policy edit and a
write grant. It is the same class of change as decision 1, so it is flagged rather than
assumed.

### 5. Small follow-ups found during 145

- `validate_coverage.py` still flags rowing and paddle-sports at 0 antagonists, and several
  sports under the floor of 5. Same fix as SUP, one pass through the pipeline.
- `ReadinessEventsTests.swift` header still calls `buildReadinessEvents` private (2a made it
  internal).
- `scripts/db/draft_variant_additions.py` uses the merged exercise 1087 as a template id.
- The 2a summary test assumes English weekday names; pin the calendar's locale in the test.
- Track 5b: licensing outreach drafts in the repo for Wilbur to send. Nothing drafted yet.

## Next work after build 145 shipped (written 2026-09-26, second pass)

Build 145 is phase-training2#62 (merged 2026-09-26) plus eval-rig#1: the four data clocks, the housekeeping,
the fleet (contract, simulator, scorer, app replay), and the CI split. Every Swift slice
passed CI on its first compile; one real bug surfaced on the PR (the squat merge put Core and Hamstrings at equal volume on the muscle-balance card's last row, and a volume-only sort picked the survivor by dictionary order) and is fixed with a slug tie-break. The fleet's readiness truth is fitness-fatigue (Wilbur,
2026-09-26). Status of the list above: items 1 and 2 are done except the prompt check and
the first scored run, which lead the list below.

### 1. Close out 145 (1 to 2 days)

- **Prompt check before external TestFlight.** The recovery-data grant (Health & Imports)
  and "while using" location at the first session start, including decline (no second ask,
  nothing captured). Neither is covered by a test. A UI test can drive both with the
  simulator's privacy reset (`simctl privacy <udid> reset all`), so the next time it is
  not a manual step.
- **Merge eval-rig#1.**

**Done 2026-09-27.** Wilbur checked both prompts on build 145, decline included, and they
look right. eval-rig#1 merged as `c539877`, so `fleet.yml`'s default `eval_rig_ref: main`
now has the fleet code. The UI test for the prompts is still unwritten.

### 2. First scored fleet run (about 2 days)

- **Where the replay runs.** It needs Xcode. Two options: Wilbur runs the three commands in
  the fleet section on his Mac, or a manual `fleet.yml` workflow checks out both repos,
  simulates, replays, scores, and uploads `report.md`. The workflow needs read access to
  the private eval-rig from phase-training2's Actions, which means a fine-grained token
  stored as a secret (`EVAL_RIG_READ_TOKEN`, contents: read, eval-rig only). **Decision
  for Wilbur:** add the secret, or keep the run on the Mac.
- **Read the report** at 50 athletes × 26 weeks, seed 42, and record the baseline numbers
  in this file: 3b Brier against the running-attendance baseline, PatternEngine recall and
  false suggestions per athlete-month, twin MAE and direction, 2a skip and move agreement.

### Fleet baseline (2026-09-26, run 36281511936)

Items 1 (merge 145) and 2 are done; the prompt check and eval-rig#1 are still open. The run
went to CI (Wilbur, 2026-09-26): `fleet.yml`, manual, eval-rig read through the read-only
deploy key `EVAL_RIG_DEPLOY_KEY` rather than the fine-grained token proposed above.
50 athletes × 26 weeks, seed 42, engine build 145, eval-rig at
`claude/elegant-brahmagupta-7ecbou` since eval-rig#1 is unmerged. All 50 athletes replayed.

- **3b.** Brier 0.131 against 0.135 for running attendance, over 5,772 planned days. It
  wins on traveler (0.145 vs 0.162) and weekday-skipper (0.137 vs 0.184), where the travel
  and weekday terms carry signal, and loses by 0.001 to 0.024 on the other five personas.
  Miscalibrated at both ends: the 0.9-1.0 bucket predicts 0.947 and observes 0.900, and
  the 0.2-0.4 buckets predict about 0.30 and observe about 0.465. Too confident near the
  top, too pessimistic in the low buckets.
- **PatternEngine.** 100% recall on both planted habits (172 and 151 detectable weeks), zero
  false suggestions on steady and grinder. Nothing to tune from this: the planted habits are
  far from every threshold. Tuning `dropsNeeded` and the rest needs personas that sit near
  the thresholds (a habit shown twice in 28 days, noise on the controls).
- **Twin.** MAE 5.64 lb against 5.30 for last value, direction 56.8% over 7,818 moved rows.
  Loses on every persona, consistent with the Fitbod NO-GO.
- **2a.** 0.0% sign agreement on all 14,082 scorable rows. The scorer is correct; a
  cross-tab of app sign against simulator sign shows why. `move` and `shorter` return
  exactly the baseline on every row (10,712 rows, app sign 0), while the simulator moves
  readiness on all of them. `skip` scores at or below baseline on 3,370 of 3,370, while
  fitness-fatigue says a skip before a sport day raises readiness on every one. This is the
  `ReadinessSignal` flaw the fitness-fatigue decision predicted, plus a second one: the app's
  counterfactual cannot see a moved or shortened lift at all. Both are 1b's targets.

### 3. Tune from the report (about 3 days)

- **3b priors.** Replace the 75% start, the 15% streak and 30% travel cuts, the 12% an hour
  late decay and the 6-day check-in floor with values fitted on the fleet. Hold out a
  second seed to confirm the gain is not fitted noise. Gate: Brier beats the
  running-attendance baseline on the holdout seed.
- **PatternEngine thresholds.** Set `dropsNeeded`, `overrunSessionsNeeded` and the rest
  from the false-suggestion rate on steady and grinder. Gate: under 1 false suggestion per
  athlete per quarter, recall not lower than today.

**3b tuned 2026-09-26.** `FleetLikelihoodSweepTests` does coordinate descent on Brier
over seed 42 and reports seed 7 as the holdout, with knobs passed through
`SessionLikelihoodEngine.Params`. Shipped values:

| knob | was | now |
|---|---:|---:|
| prior (happened : missed) | 3 : 1, 75% with no history | 8 : 1.5, 84% |
| weekday shrinkage | 4 pseudo-days | 12 |
| skip-streak multiplier | 0.85 | removed (fitted 1.0; the weekday rate already carries those misses, and the streak is still listed as a reason) |
| travel multiplier | 0.7 | 0.7, not fitted |

Travel was frozen on purpose. Every simulated persona has the same planted travel
attendance, 0.2, so the sweep's 0.3 would copy the simulator's invented constant into
the app. It stays a guess until in-app travel days exist. The time-of-day terms cannot
be fitted either, since the fleet estimates each day from its start.

Scored by eval-rig on the replayed predictions, Brier against running attendance:
seed 42 **0.126** (was 0.131) vs 0.135; holdout seed 7 **0.127** vs 0.138. The gate
passes. Mean prediction 0.821 against 0.821 observed on seed 42. The model now wins on six of
seven personas and still loses on sporadic (0.266 vs 0.250 on seed 42, 0.259 vs 0.253 on
seed 7). Twin and 2a unchanged. The prior and the shrinkage are still fitted to a
simulator's variance, so the 2026-10-24 review re-checks 3b on in-app outcomes.

The 6-day check-in floor sits in the check-in suggestion path, not 3b, and the fleet has
no check-in truth; it waits.

### 4. Track 1b, pulled forward (about 1 week)

The fitness-fatigue decision makes 2a's skip disagreement a flaw in `ReadinessSignal`, and
1b is the fix: per-pattern load with a fitness and a fatigue term, behind the existing
silent path (`AthleteState.readinessScore`). No UI. Built on fixtures and the fleet first.
- **Gate to ship:** on the fleet, 2a skip and move agreement rises to at least 80%, and
  3b and the twin do not get worse. The live readiness changes silently for every user,
  so it ships only with the fleet numbers written here, and the 2026-10-24 review still
  judges the twin on in-app pairs.

**Built 2026-09-26 as a split, not a replacement (Wilbur's call).** `ReadinessSignal`
measures training state and sizes sets (`lerp(0.6, 1.0, score)`) and the RPE cap; form
sits near 0.5 for a steady lifter and high after a layoff. So replacing one with the other
would have cut a consistent user's sets by about a fifth and raised volume after a layoff
(estimated from the formulas, not measured), and the gate above would not have seen it,
since 3b and the twin do not read readiness. What landed instead:
- `FormModel` (pure): fitness-fatigue form, 42/7-day terms, gain 3, 120-day window,
  starting at half an hour a day. Nothing in the generator reads it.
- `GeneratorContext.buildLoadEvents`: one event per day carrying minutes. Hard sport days
  count. On each day it takes the largest of in-app, Health and sport-log totals, so a
  workout seen by two sources is not counted twice. `buildReadinessEvents` also dropped
  every duration, so live load had no minutes at all until this builder existed.
- `Counterfactual` scores with form. `liveScore` and its test are gone, since the 2a
  baseline no longer equals the generator's score.
- Not built: per-pattern load. The fleet has no per-pattern truth to score it against.

Fleet, same 50 athletes × 26 weeks, seed 42, replayed locally: **2a sign agreement 100%
on skip (3,370), move (7,332) and shorter (3,380)**, up from 0%. The 3b and twin sections
of the report are byte-identical to the baseline. The 100% is by construction, because
form uses the fleet truth's own constants, so it proves the implementation and says
nothing about whether 42/7 fits real lifters. The in-app review is where that gets
judged.

### 5. Review on 2026-10-24 (unchanged)

Size and direction on 100+ in-app pairs. Physiology is not judged; its clock has run under
four weeks. Add the fleet numbers from 2 and 4 as context.

### 6. Build 146, the watch (target mid-November)

**Plan: `PLAN-watch.md` (2026-09-27).** Health writes approved 2026-09-26 on the condition of
no duplicates; the plan covers that, three open decisions, and the portal work.

4a watch companion plus 4b labeled motion capture. **Decision for Wilbur before it
starts (answered yes 2026-09-26):** 4a writes workouts to Apple Health, and the app is read-only today (usage
string and policy say it never writes). Yes means a new usage string, a write grant, and
policy and label updates in 146.

### 7. Readers that wait on data (no build time until the data exists)

- 1c physiology reader: after 6+ weeks of nights for the owner.
- 3c place-aware swaps: once places cluster (3+ visits at 2+ places).
- 3d weather and snow: WeatherKit route, decision 3 already yes; about 1 week, can start
  any time after 146.
- 4c classifier: once the top 20 exercises each have enough labeled reps from 4b.

### 8. Small follow-ups (fold into whichever build is next)

- Rowing and paddle-sports: done 2026-09-26, six antagonists each (the SUP set: push-up,
  DB bench, DB overhead press, landmine press, scapular push-up, external rotation).
  **The other 27 sports done 2026-09-27**, 142 rows: each sport's antagonists are the
  patterns its own relevance rows lack (cuff external rotation and retraction for the
  overhead and striking sports, hamstring and hip-abduction for the quad and cutting
  sports, rows for the push-heavy practices, extension for the flexion-heavy ones). Where
  a pair already existed as prehab it was left as prehab and a different exercise added.
  `general-fitness` stays flagged: it has no dominant movement, so "antagonist" has no
  meaning there and the base pool is untagged foundation lifts by design.
- Done 2026-09-26: the `ReadinessEventsTests.swift` header, the drafting script's merged
  squat template (1087 -> 57), and the 2a summary test's calendar locale.
- Track 5b: **permission granted by both MTI and Uphill Athlete (Wilbur, 2026-09-27).** The
  terms (which sessions, attribution, fee or share, term length) are not in the repo yet.
  Write them into `docs/outreach/` before any licensed session ships, since the app and
  store copy have to match what was agreed.
