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

**How to run the fleet.** The contract is eval-rig's `fleet/CONTRACT.md`; the replay lives
in `PhaseTrainingTests/Fleet/` (test target only, nothing ships).

1. In eval-rig: `npm run eval -- fleet simulate --personas 50 --weeks 26 --seed 42`. It
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
