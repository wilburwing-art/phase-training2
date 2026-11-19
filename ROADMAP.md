# Roadmap — phase-training2

Forward-looking items beyond the current phase plans (`PLAN.md`, `PLAN-routines.md`, `PLAN-coach-prereqs.md`, `PLAN-coach.md`). Entries here are not yet specced; they're load-bearing context for future plan files.

---

## Next-gen recommendations (specced)

Specced in `PLAN-next-gen.md` (2026-09-26): the twin, counterfactual planner,
context pre-adaptation, sensor logging, and cross-user learning, ordered by
dependency with gates and the owner decisions each one waits on. Status of the
shipped foundations is in `PLAN-predictive-recommendations.md`.

---

## Premium tier: a full model of the user (not specced)

Added 2026-11-14 from a product discussion. Nothing here is specced or
scheduled. Where an item overlaps `PLAN-next-gen.md` the track is named and
that file stays the source of truth for the build steps.

### The pricing thesis

- Software-only fitness apps sit around $10 to $20 a month (Fitbod is roughly
  $16, from memory). The $100 to $200 tier exists (Future, Trainwell, Caliber,
  prices from memory) and each of those has a human coach in it.
- People pay $100 a month for three things: accountability (someone notices a
  skipped session), a high-stakes goal (a Denali trip, a ski season, a race),
  and trust in the plan's author (Uphill Athlete and MTI sell on the coach's
  name).
- Two tiers to consider. About $15: the app with the adaptive engine. About
  $100: the same app plus a human coach who reviews the plan monthly and sends
  a short check-in. One coach carrying 100+ clients is an unverified estimate.
- A pure-AI $100 tier needs the predicted versus actual scorecard below before
  it can be sold. The user model is what produces that scorecard.
- Niche: mountain and multi-sport athletes, where the season engine has an
  edge and buyers already pay for coaching.
- Validation before any build: sell the $100 tier by hand to 5 people, with
  Wilbur as the coach using the app, at about 2 hours per client per month. If
  5 will not pay, stop.

### Five product directions

1. **Closed-loop adaptation.** The plan reads sleep, HRV, logged RPE and missed
   sessions, changes tomorrow's workout, and gives the reason in one sentence.
   Overlaps Track 1 (1b to 1d) and Track 3.
2. **Whole-season planning across sports.** Lifting, skiing, climbing, travel
   and injuries in one plan that peaks for a date. The season engine and the
   written-programs-first rule already point here.
3. **Camera and watch as sensors.** On-device pose estimation for rep counting,
   bar speed and technique cues. Velocity loss as a fatigue signal alongside
   self-reported RPE. Overlaps Track 4 (4b to 4d); technique cues are new.
4. **A coach that starts the conversation.** Remembers history, reviews the
   week on Sunday, messages after two skips. Depends on the coach shipping at
   all (`DECISION-coach-at-launch.md`: not in the first store release).
5. **Proof of results.** Scheduled test weeks, predicted versus actual numbers,
   and a projection such as "on track for a 2x bodyweight deadlift by March".

### The user model: four layers

A set of numbers per person that the app keeps refining and can run forward in
time.

1. **Physiology.** A fitness-fatigue model per quality: max strength, aerobic
   base, power, and tissue tolerance for knees, fingers and lower back. Each
   has its own build-up and decay rate, learned for this body. Extends the
   Track 1 twin from per-lift to per-quality.
2. **Behavior.** Likelihood of showing up by day, time, session length and
   type ("skips 70-minute sessions on Tuesdays", "adherence collapses in week
   3 of every block"). `SessionLikelihoodEngine` (3b) is the starting point.
3. **Life context.** Work calendar, trips, the ski season, a seasonal job that
   eats November. Phases of life as well as single events. Calendar travel
   (3a) and location capture (3c) are the first inputs.
4. **Goals and values.** What wins when two goals collide. A skier who will
   give up 10 pounds on the squat for fresh legs on opening day plans
   differently from one who will not. Nothing in the app captures this today.

### Projections

Run the plan forward hundreds of times and show a range:

- "At your current adherence there is a 64% chance you hit a 2x bodyweight
  deadlift by March 1. Protect the Thursday session and it goes to 81%."
- "This trip lands in your peak week. Moving the test forward 9 days costs
  about 2% of predicted strength and saves the peak."
- "Your legs project to be freshest on December 12. Opening day is December 5.
  Shift the taper?"

Extends Track 2 (`Counterfactual`) from a seven-day readiness delta to a
season-length outcome with a probability.

### How the model learns

- **Population first, then personal.** Day one uses averages for a similar
  age, training history and sport. Every logged set, RPE, HRV night and skipped
  session pulls the numbers toward the person. Personal data outweighing the
  averages after 8 to 12 weeks is a reasoned estimate with no measurement
  behind it.
- **Test weeks calibrate.** Each scheduled test checks the forecast. Predicted
  405, pulled 385: the app says so and adjusts.
- **Visible and editable.** A "what I believe about you" page: recovery speed,
  weak links, the days adherence fades. The user can correct it ("that week
  was a stomach bug").
- **The scorecard is the product.** At renewal the app shows it called the
  numbers within a few percent across three test weeks.

### Hard parts

- **Cold start.** The model is weakest in the first six weeks, when churn is
  highest. Needs a short calibration test in week 1 and behavioral insights
  before the physiological ones are ready.
- **False precision.** "64%" with a real uncertainty of 25 points loses trust
  on the first miss. Show ranges, and show them narrowing.
- **Data quality.** RPE logged at 9 PM is noise. Bar speed from the camera and
  watch HR during intervals are the fix, which is why direction 3 matters.
- **Privacy.** A model of when adherence breaks down is intimate. Keep it on
  device, with export and delete.

### Smallest real version

1. A Banister-style fitness-fatigue model per quality (strength, aerobic,
   tissue load), with rates learned per user.
2. An estimated 1RM trend per main lift, with a forecast band.
3. An adherence model learned from logged versus skipped sessions.

All three feed the planner so the week is scheduled around how the person
behaves.

### Conflicts with standing rules, to settle before a spec

- **The twin has not beaten last-value on magnitude.** B1a was a NO-GO and
  1a-2 found signal on direction only. The review was run 2026-11-15 on a
  phone backup: 6 scored in-app pairs, short of both thresholds, and the twin
  lost on them. B1 is shelved per the written rule
  (`PLAN-predictive-recommendations.md`). A forecast band on 1RM (item 2
  above) needs a different model, so it stays unspecced.
- **"Visible and editable" versus "readiness is silent"**
  (`phase-training-personalization-two-axes`). The belief page shows what the
  silent path currently hides. Decided 2026-11-15 (owner): the readiness model
  is visible to the user, on its own page under Progress. Today does not
  change. The skill's "readiness is silent" rule is retired for the premium
  track.
- **"Changes tomorrow's workout" versus written programs first.** Settled by
  the standing rule: the engine adjusts authored sessions for a short list of
  reasons and never writes a workout. Adaptation here means ranking, moving
  and scaling authored sessions.
- **A human coach tier or population priors need a backend** and move the
  privacy label off "data not collected". Settled: decision 5 in
  `PLAN-next-gen.md` was answered yes on 2026-09-26.

### Next step

A one-page spec of the user model: each parameter, where its data comes from,
and how often it updates, in the same handoff format as the other specs.

---

## Voice mode (specced)

Specced in `docs/PLAN-voice.md` (2026-11-18); build steps in `docs/PLAN-backlog-2026-11-voice.md`.

---

## Showcase routines (swipeable, not specced)

Added 2026-11-17. Nothing here is specced or scheduled.

**Goal.** A set of swipeable routines whose quality shows what the programs can do. Each one is an authored, finished routine a new user can swipe through and start.

**Starting set.**
- Abs
- Hang training (hangboard / dead-hang work)
- Upper body
- Legs
- More to be chosen, same bar: each routine is one a coach would sign off on.

**Open questions before a spec.**
- Where the swipe surface lives (Today, Routines tab, or onboarding) and how it relates to the existing routine catalog (`PLAN-routines.md`).
- Whether these are new authored routines in `db/source/*.json` or curated picks from the existing catalog.
- Which routines count as "showing off" the programs: single sessions, or a short progression across weeks.
