# R4 · 03 Safety

## F1 (high, fixed before this pass ran) — 14 of the 17 "contradiction" fixes were a regression

`802e51a` found 17 (exercise, injury) pairs carrying both `contraindicated`
and a curated `prehab` / `rehab_early` / `rehab_late` row, and dropped every
generated contraindication on the reasoning that the curated row is the more
specific claim. True of the row, false of the conclusion. The three roles mean
different things and only one of them contradicts "avoid this":

| role | meaning | conflicts with contraindicated? |
|---|---|---|
| `rehab_early` | do this now, while symptomatic | yes |
| `rehab_late` | progress to this | no |
| `prehab` | this prevents the injury | no |

A Nordic hamstring curl prevents hamstring strains and is exactly wrong during
one. The app has no notion of injury stage, so a declared injury has to be read
as symptomatic now. `5419aee` restored the 14 (both step-downs and single-leg
squat to box for PFPS; Nordic curl, single-leg RDL, tuck jump and lateral
deceleration for hamstring strain; both adductor movements for groin pull; both
landing drills for lateral ankle sprain; releve calf raise for turf toe; neck
harness for cervical strain; cossack squat for trochanteric bursitis) and kept
the three real ones (Alfredson heel drop and loaded eccentric calf raise for
achilles tendinopathy, split-stance isometric for PFPS). The invariant now
checks `contraindicated` against `rehab_early` only. Zero clashes at HEAD.

## F2 (high) — the 1b rule pass skipped every injury that already had a curated row

`SELECT ci.slug, COUNT(*), SUM(notes LIKE '%unreviewed%') ... HAVING generated = 0`
returns 13 injuries with zero generated rows, all of them injuries that came
into 1b with one to ten hand-written rows:

| injury | rows | generated |
|---|---|---|
| lumbar-disc-herniation | 10 | 0 |
| acl-injury | 6 | 0 |
| rotator-cuff-injury | 4 | 0 |
| wrist-sprain | 3 | 0 |
| patellar-tendinopathy | 2 | 0 |
| shoulder-impingement | 2 | 0 |
| slap-tear, hip-flexor-strain, hip-labral-tear, tennis-elbow, golfers-elbow, whiplash, stinger-burner | 1 each | 0 |

So the claim "55 of 56 injuries mapped" was accurate and hid the shape of the
coverage: the thinnest injuries stayed thinnest, because the pass treated any
existing row as "already handled". **ACL is the one that mattered for this
app.** Six rows, none of them a jump: only 3 of 29 `jumping-landing` exercises
were contraindicated, and a snowboarder declaring an ACL injury was served Pogo
Hops and Lateral Bound to Stick.

Fixed in this commit for ACL: +65 contraindications over the impact, cutting,
deceleration, sprawl, skating, rotational-strike and Olympic-derivative
patterns, skipping the 6 exercises that already carried an ACL row. Squat and
single-leg-squat patterns were left alone on purpose: deep loaded flexion is
out acutely but pain-free-range bodyweight squatting is standard ACL rehab, and
a pattern rule cannot see depth. ACL now removes Pogo Hops from the snowboard
routine and 10 movements from the ski pool; `eccentricLeg` keeps 4 of 7.

The other twelve are filed as R3-11 with the list above. Each needs the same
sourced treatment ACL got and none is blocking the four sports this build
ships for.

## F3 (fixed, low) — the no-hang pull was labelled `rehab_late` for trigger finger

By F1's own semantics that means "progress to", and it was being served (not
contraindicated). The cited study is on trigger-finger patients, so it is a
treatment: relabelled `rehab_early`, which is also what makes it legitimately
servable.

## F4 (pass) — the Alfredson class has no other instance hiding without a curated row

Probed the standard rehab exercise for lateral and medial epicondylitis
(reverse and standard wrist curls), patellar tendinopathy, shoulder
impingement and rotator cuff (external rotation), plantar fasciitis (heel
drops, calf raises), lumbar (side plank). None is contraindicated. Two gaps
rather than defects: none carries a `rehab_early` row either, and the catalog
has no Clamshell, Side-Lying Hip Abduction, Bird Dog or Spanish Squat, which
are the standard first-line movements for PFPS, IT band and low back.

## F5 (low, filed) — the PFPS rule reaches an unloaded squat

The rule text reads "avoid knee flexion beyond ~90 degrees under load", and it
removes `Squat (Bodyweight)` from the hiking routine. Conservative rather than
unsafe, and a pattern rule cannot see load or depth, so left as is and noted.

## F6 (pass) — the substitution pass cannot reintroduce a contraindicated movement

`resolvedRows` filters substitutes on `excluded` as well as the authored rows.
Re-read, and `FilterCompositionTests` asserts it across 1,800 days.
