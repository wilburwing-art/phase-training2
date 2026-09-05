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

## F2 (high, corrected 2026-09-05) — the session fills, and lies about what it is

**This entry originally predicted an empty day and that was wrong.** Generating
it settles what actually happens. A carpal-tunnel climber (78 exercises
excluded) gets four movements in every pre-season session:

    'Climbing · Pre-season — Session 1'
    objective: "Max finger strength + power + lock-off + tension"
    summary:   4 movements · ~35 min
    - Medicine Ball Slam / Hollow Body Hold / Ab Wheel Rollout / Toes To Bar
    demands:   contactStrength/bodyTension/bodyTension/bodyTension

Zero finger work, three of four slots on one demand, under an objective still
promising max finger strength. A healthy climber's session 1 is Weighted
Pull-Up, Hollow Body Hold, **Hangboard Max Hang**, Prone Y-T-W-L.

`guaranteeSignature` declines to force a signature demand the pool cannot serve
(correct), and `applyInjuryRedistribution` sends the freed weight to whatever
is left, which is why the session fills with bodyTension. Neither is a bug. The
silence was.

So the fix that follows from the original wording, asserting non-empty, would
have caught nothing: these sessions are full and above the movement floor. What
was needed is for the session to report the gap, which it now does:

    summary: 4 movements · ~35 min · no finger work: your injuries rule out every option

**The lesson is the general one:** a filter count tells you what was removed,
never what the engine does with what remains. One `generateLift` call with the
injury set answers it, and it took one to overturn this finding's mechanism.
`testInjuryFilterNeverLeavesASessionUnderTheMovementFloor` still opens with
`if w.exercises.isEmpty { continue }`, which is still worth closing, but it is
a smaller item than this entry first claimed.

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
