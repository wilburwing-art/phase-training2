# R3 · 03 Safety and contraindication

Scope: the ~3,100 rules-generated rows 1b added to
`exercise_injury_relevance`. The question is not whether the rules are
clinically defensible one at a time; it is what the app does when they fire
together.

## F1 (high) — three injuries contraindicate every `fingerStrength` movement climbing has

The climbing pool holds 4 movements serving the signature demand: Max Hang,
Repeaters, Plate Pinch Hold, Fat-Grip Dead Hang. Contraindicated counts,
`role = 'contraindicated'` joined to `sport_movements`:

| injury | fingerStrength movements removed (of 4) |
|---|---|
| trigger-finger | **4** |
| de-quervains | **4** |
| carpal-tunnel | **4** |
| biceps-tendinopathy | 3 |
| finger-pulley | 2 |

A climber who declares carpal tunnel has no finger movement left in the pool.
`SportSeasonGenerator.signatureDemand` names `fingerStrength` as the one demand
climbing must always cover, and SeasonFidelity check 2 asserts it, but neither
runs against an injured athlete.

Whether these rules are right is a separate question from what they do. Each
was generated from the grip and wrist rule set, and for carpal tunnel and
trigger finger "no loaded gripping" is the standard advice, so the rows are
probably correct and the pool is simply too narrow to answer them. That makes
this a content gap, not a rule bug: the app needs finger work that is not a
hang (open-hand density, no-hang device at low load) or it needs to say the
quiet part, which is that this injury and this sport do not mix this month.

## F2 (high) — the floor test cannot see the worst outcome, because it skips it

`testInjuryFilterNeverLeavesASessionUnderTheMovementFloor` asserts a served
session holds at least 3 movements, and I extended it this session to 8
(sport, injury) pairs. It opens each case with:

    if w.exercises.isEmpty { continue }

So a workout that came back EMPTY passes. Every case in F1 is exactly that
shape: filter everything out, return nothing, skip the assertion. The test I
added to cover the 1b rows is structurally blind to the failure the 1b rows
make possible. The comment calls the empty case "a separate concern", which was
true when the only way to reach it was a nil primary sport; it is not true now.

Not confirmed dynamically this pass (report-only, and driving the generator
needs a test edit). It is the first thing to run next sitting: assert
`!w.exercises.isEmpty` for a plannable sport, or assert the honest empty-state
copy is what came back.

## F3 (medium) — four knee injuries each remove 46% of the ski pool

pfps, meniscus-tear, chondromalacia and bakers-cyst each contraindicate 22 of
the 47 alpine-skiing movements, and 4 of the 7 that serve `eccentricLeg`, the
ski signature demand. Three survive, so the engine still covers it; there is no
defect here today. It is the same narrowing as F1 one step less far along, and
the ski pool is the one that has room, so it is where a second eccentric option
that is not deep-knee would pay.

## F4 (info) — the substitution audit did not weaken the injury filter

`AuthoredRoutine.resolvedRows` excludes `profile.excludedExerciseIds` from the
substitute candidate set as well as from the authored rows, so a swap cannot
reintroduce a contraindicated movement. Confirmed by reading the filter
(`AuthoredRoutine.swift`, the `pick` predicate) and by
`testAuthoredPathNeverServesContraindicatedExercise` passing against the new
table.
