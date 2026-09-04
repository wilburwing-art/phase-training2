# 2026-09-04 critique suite, third pass (scoped)

Scope: `9c4a46f..cb7a798`, the seven commits landing the six decisions plus the
Today-wheel samples. Gate for running it was CI `test.yml` run `33921643920` on
`cb7a798`, **success**.

## Why five lenses and not thirteen

R2 ran all 13 the same morning against build 124. Only five lenses read a
surface that moved since:

| lens | what moved under it |
|---|---|
| 01 coaching quality | ~3,100 injury rows, 69 substitution pairs dropped, `upperStrength` + 4 ski movements, hangboard cap, 5 rewritten routines |
| 03 safety | the same injury rows, and the equipment filter now sharing the injury filter's path |
| 08 copy and voice | 6 new user-visible strings |
| 12 backlog re-verification | 7 landing claims written by the implementer an hour earlier |
| 13 test suite | 7 new tests, and a test-host crash that read as one failure |

The other eight (niche, coach red-team, funnel, lifecycle, accessibility,
paywall, App Review, competitors) would have re-read code neither pass touched.
02 and 10 have one closed item between them: the MTI exposure T3-2 named is
gone with the branded exercises, recorded under 12 rather than reopening two
lenses for it.

Method unchanged from the first pass: sequential, no agent fan-out, evidence by
`grep -n` / `sed -n` / sqlite against the shipped artifact, findings written to
disk as each lens closed. Report-only, no code edits.

## What it found

Three things that matter, all of them invisible to the test suite that was
green when the pass started:

1. **`upperStrength` realizes 0.00 in ski pre-season and in-season** despite
   carrying weight in both. The demand added yesterday is decoration for two
   thirds of the ski year. Mechanism measured against `allocateSlots`: an
   alphabetical remainder tie-break in one phase, a quantisation floor in the
   other. (01 F1)
2. **Three declarable injuries contraindicate every `fingerStrength` movement
   climbing has**, and the floor test written to cover exactly these new rows
   `continue`s past an empty workout, so it cannot see it. (03 F1, 03 F2, 13 F1)
3. **Three of seven landing claims written into the backlog an hour earlier are
   wrong**, each in the reassuring direction, each because the claim describes
   the change rather than the result. (12)

## Refuted

"42 routines carry fewer than 3 exercises and can be served as a day's
workout." True of the table, false of the app: `authoredRoutineIds` has carried
a `>= 3` clause since T1-9. Recorded so a fourth pass does not re-chase it.
(01 F2)

## Files

`01-coaching-quality.md`, `03-safety-contraindication.md`,
`08-copy-and-voice.md`, `12-backlog-reverification.md`,
`13-test-suite-critique.md`.
