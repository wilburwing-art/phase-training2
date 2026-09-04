# R3 · 01 Coaching quality of generated programs

Scope: `9c4a46f..cb7a798` (build 124 to CI-green `cb7a798`). Delta only; R2's
entries stand where nothing moved. Evidence is `/tmp/season-fidelity/report.md`
regenerated this session from `SeasonFidelityTest` (24 passed), plus sqlite
against the shipped `PhaseTraining/Resources/coach.db`.

## F1 (high) — `upperStrength` is allocated weight it can never realize in two of three ski phases

4b added the demand, four movements, and a weight in all three ski phases. The
realized week says it lands in one:

| ski phase | target | realized | week slots |
|---|---|---|---|
| off-season | 0.10 | 0.07 | 12 |
| pre-season | 0.05 | **0.00** | 12 |
| in-season | 0.05 | **0.00** | 8 |

`report.md:16,56,89`. Every other non-zero demand in those two phases realizes,
including the three that share pre-season's 0.05.

Mechanism, reproduced against `allocateSlots`
(`SportSeasonGenerator.swift:305-323`) at the slot budgets the report shows:

- **Pre-season** ties four demands at 0.05 with three remainder slots to give.
  The tie-break is `demand.rawValue <` — alphabetical — so `core`,
  `hipLateral` and `kneeStability` take them and `upperStrength` sorts last,
  every week, deterministically.
- **In-season** has no peer at 0.05. 0.05 x 8 = 0.4, floors to 0, and its
  remainder loses the ranking outright.

So the weight is decoration in both. A skier gets upper-body work in the
off-season and none from opening day onward, which is the half of the year 4b
was argued for. The commit message for `897e307` claims "through the off-season
and pre-season"; the pre-season half is not true as shipped.

Fix is a weight, not a code change: 0.10 in pre-season clears the tie, and
in-season either goes to 0.10 or honestly to 0.00 (2 sessions under a
`sessionVolumeCap` of 10 is a defensible place to spend nothing on pressing).
Whichever, `PhaseRule` should not carry a weight the allocator cannot pay.

**This generalizes past `upperStrength`.** Any demand added at the bottom of a
phase's weight table inherits both traps: it needs a weight that clears
`1/weekSlots`, and at a tie it needs a rawValue that sorts early. Neither is
checked anywhere. A fidelity assertion of the form "every demand with a
non-zero target realizes at least one slot in the week" would have caught this
before the commit.

## F2 (refuted) — "42 routines carry fewer than 3 exercises and can be served as a day"

Measured 42 such routines, 15 of them clearing `duration_minutes >= 25`. The
finding does not survive the consumer's own filter: `authoredRoutineIds`
(`CoachDatabase.swift`) already carries
`AND (SELECT COUNT(*) FROM routine_exercises re WHERE re.routine_id = r.id) >= 3`
from T1-9. 54 routines are servable and all clear the floor. Recorded so the
next pass does not re-chase it.

## F3 (low) — the hangboard cap works, and exposes unused variety inside `fingerStrength`

3a lands as specified. Climbing off-season, 3 sessions: Max Hang, Max Hang,
Plate Pinch Hold (`report.md:164-194`). The cap is live, not a no-op: `used` is
per session (`SportSeasonGenerator.swift:83`), so without it a third max hang
was reachable.

Two observations that are not the cap's fault:

- `Hangboard Repeaters (7/3 Protocol)` (id 3) appears in no realized climbing
  week at all. The pool holds 4 `fingerStrength` movements and the sort keeps
  picking the same two.
- The two Max Hang sessions are identical prescriptions (5x8s hold, RPE 7).
  Real protocols vary edge or load between the week's two sessions. Out of
  scope here, listed because R2's variety finding did not cover within-demand
  repetition.

## F4 (info) — the rewritten routines read as coherent sessions

295 (splitboard pre-season A): back squat 3x5, eccentric step-down 3x6/side,
Bulgarian split squat 3x8/side, landmine rotation 3x8/side, side plank, nordic
curl 3x4-6. Squat pattern, eccentric quad, unilateral, anti-rotation,
posterior chain: no gap and no duplication. 299 (MTB leg endurance and trunk)
is a 6-movement circuit; walking lunge at 4x20/side is 160 reps, high but
consistent with the leg-endurance intent the routine names.

No routine lost a movement to the ten retirements: all five rewritten routines
hold 5 to 7 exercises.
