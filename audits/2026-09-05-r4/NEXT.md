# Next work, scaffolded 2026-09-05 after build 125

Ordered by what a user would hit first. Each item states the problem, what
done means, what is out of scope, and whether it is a fan-out or a single
sitting. Numbers are from the shipped `coach.db` at `cd9257e` and the 1,081
test unit target; re-measure before starting any of them.

## 1. R3-11 · twelve injuries with no rule-generated contraindications (high)

**Problem.** The 1b pass skipped every injury that already had a curated row,
so lumbar-disc-herniation (10 rows), rotator-cuff-injury (4), wrist-sprain
(3), patellar-tendinopathy (2), shoulder-impingement (2) and seven single-row
injuries (slap-tear, hip-flexor-strain, hip-labral-tear, tennis-elbow,
golfers-elbow, whiplash, stinger-burner) have no pattern coverage. ACL was the
thirteenth and is done (+65 rows). A mountain athlete declaring a disc
herniation is filtered on 10 hand rows and nothing else.

**Done means.** Every one of the twelve has a pattern rule written from its
own aggravating-movement literature, applied as generated `contraindicated`
rows with a note ending "Sourced, unreviewed.", and:
- zero `contraindicated` + `rehab_early` clashes (`test_noExerciseIsBoth...`),
- `FilterCompositionTests` extended to include the twelve, still at or above
  the movement floor or a declared empty for every plannable sport,
- the predicate no wider than the cited mechanism (the de Quervain's lesson).

**Out of scope.** Injury stage. The app reads a declared injury as symptomatic
now; `rehab_late` stays paired with `contraindicated`.

**Shape.** Fan-out, one agent per region so the literature is coherent:
knee (patellar-tendinopathy), shoulder (rotator-cuff, impingement, slap-tear),
elbow and wrist (tennis, golfers, wrist-sprain), hip (flexor strain, labral
tear), spine and neck (lumbar-disc, whiplash, stinger). Contract as in the
bodyweight-routine scaffold: each agent writes rows to its own JSON, cites
verbatim, never touches `db/source/`; the merge, the enum-semantics check,
the self-join for clashes and the rebuild stay with the lead. Add
`resolve-letter-coded-decisions...` rules: no number in a row that was not on
a fetched page.

## 2. General-fitness bodyweight base, and the last 15 empty days (medium)

**Problem.** `general-fitness`, the last-resort routine every sport falls
through to, has no bodyweight-viable routine, so a future sport with no
content of its own gets the declared empty for bodyweight users. Separately,
15 of 1,800 composition days are still empty: exactly one (sport, injury,
equipment) combination, one of `mountain-biking/pfps/bodyweight`,
`mountain-biking/achilles/bodyweight`, `trail-running/achilles/bodyweight`,
`trail-running/achilles/dumbbells` (static analysis ignores substitution, so
name it by instrumenting the test, not by guessing).

**Done means.** One `general-fitness` routine that keeps 3 movements for a
bodyweight user under each of the five test injuries; the 15 become 0 or are
written down as the honest floor with the reason (an achilles case may be).

**Out of scope.** Rewriting Easy Strength.

**Shape.** Single sitting. Sixty minutes.

## 3. R3-8 · five funded demands that buy no slot (medium, owner calls)

`alpine-skiing/maintenance` `legEndurance` and `power`; `climbing/pre_season`
`prehab` and `core`; `climbing/in_season` `prehab`, all at 0.05 and all inert
for the reasons in `phase-training-season-generator-engine-pitfalls` 8.
Each is a weight change and a question of which demand gives up a slot, the
same call as the ski pre-season pull. `knownInertWeights` is asserted exactly,
so each fix also deletes its allowlist line. Present the five with the
realized table for each phase and take the answers in one message.

## 4. Catalog gaps the safety pass found (medium)

R4 03 F4: no `rehab_early` rows exist for lateral or medial epicondylitis,
patellar tendinopathy, shoulder impingement or plantar fasciitis, and the
catalog has no Clamshell, Side-Lying Hip Abduction, Bird Dog or Spanish
Squat, which are first-line for PFPS, IT band and low back. Add the four
exercises (sourced) and the `rehab_early` rows, and the no-hang-pull style
honest label where a movement is a treatment. Pairs naturally with item 1.

## 5. Test coverage for the thin sports (medium)

thru-hiking, mountaineering and trail-running appear in 2 to 3 test
assertions each against climbing's 70. `FilterCompositionTests` now walks all
eight sports, which is the floor; what is missing is a week-shape test per
sport (what a healthy full-gym user gets across phases) so a content
regression in those sports fails something other than a composition count.

## 6. Sample workouts on the wheel: assert they differ (low)

`test_sampleIsDeterministicPerSeason` pins determinism and nothing pins that
the off-season and in-season samples are different workouts. One assertion:
across the four samples for a sport, the exercise-id sets are not identical
and the titles are distinct.

## 7. R3-9 · the engine overrides a movement's cited protocol (low)

The no-hang pull is a 3 s overcoming isometric in its instructions and the
engine serves it as `5x8s hold` from the `fingerStrength` scheme. A
per-movement override on `SportMovement` (sets, reps, rest) that the scheme
respects when present, or an explicit note in the exercise text that the
engine's prescription is a scheme default. Decide which; the first is the
real fix.

## 8. Small items, one sitting together (low)

R3-12 estimator ignores duration rows (3 of 400); R3-13 routine 70 "Pre-Season
Ski Prep Block" in the snowboard rotation; R3-14 PFPS rule reaching an
unloaded squat; the 2026-08-23 backlog header says 12 where 14 are checked.

## 9. T3-1 · niche research toward mountain athletes (owner agreed 5a, no task yet)

All ten acquisition briefs target gym-strength communities; all ten plannable
sports are mountain sports. Redo the briefs for the communities the app
actually serves. Fan-out candidate, one brief per plannable sport, same
verbatim-or-NOT-ON-PAGE research rule. Not started because the app is not
ready for public release (5c), so this is the right time to draft and the
wrong time to act on it.

## Deferred by decision, do not pick up

5c pricing, 5d the gate flip, 6 gateway token rotation and the account-id
literal beside it.
