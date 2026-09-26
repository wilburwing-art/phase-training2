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
  with in-app pairs.
- **1b. Silent readiness from the twin.** About 1 week. Replace
  `ReadinessSignal`'s unweighted session count with per-pattern load, behind
  the existing silent path (`AthleteState.readinessScore`). No UI. Gate to
  1c: after four weeks live, the twin's error clusters on days a physiology
  signal would explain (short sleep, high resting HR the night before).
- **1c. Physiology inputs.** Decision 1. About 2 weeks. HRV, resting HR and
  sleep from HealthKit joined to the soreness check-ins the app already has.
  Gate to 1d: the error on those clustered days drops.
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
  under the kill rule above.
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
- **3c. Location.** Decision 2. About 2 weeks. Home gym learned from where
  sessions were logged, geofences for gym, crag, trailhead. A session started
  away from the home gym gets the equipment-swapped version offered, on the
  existing substitution path.
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

## Order of work

Each line is one build or one review. Dates are estimates.

1. **Now to 2026-10-03: build 144.** Calendar travel, embeddings, 1a-2
   diagnosis, 5a on-device aggregates.
2. **2026-10-24: review.** Twin re-ask on in-app pairs plus any new export;
   suggestion decisions; zero-result searches. Decides 1b, and whether the
   kill rule fires.
3. **November 2026: build 145.** 1b if GO, 3b session likelihood, 2a engine on
   fixtures, eval-rig fleet if the remote exists.
4. **December 2026 to January 2027.** 1c and 3c if decided, 2b on the Week tab.
5. **Q1 2027.** 1d adaptation ranking, 4a watch companion if decided, 3d and
   3e as their decisions allow.
6. **Q2 2027.** 4b accrual, 4d bar speed, then 4c classifier.
7. **H2 2027.** Track 5 only if the backend posture, licensing and user count
   all exist.

Total build time about 9 months of work if every decision is yes and every
gate passes. Calendar time runs longer than that, because the twin and the
classifier both wait on data that only accrues at the pace of real training.
