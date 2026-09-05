# 2026-09-05 fourth pass: safety and content, scoped to today's data changes

Two lenses only, run before tagging build 125. Everything since R3 (`cb7a798`)
is either content or the injury table: `exercise_injury_relevance` was edited
three times today (the de Quervain's narrowing, a 17-row drop, a 14-row
restore), and seven content rows nothing judges for quality were added (3
exercises, 4 routines). A wider pass would re-read code R3 already read.

| lens | what it read | outcome |
|---|---|---|
| 03 safety | the injury table after three edits; the four new routines under five common injuries | 1 high (fixed), 1 high (13 injuries, 1 fixed + 12 filed), 2 low |
| 01 coaching quality | 7 new content rows; rotation and duration | 1 medium (fixed), 3 low |

Method as always: sequential, evidence against the shipped `coach.db`, every
count re-run rather than recalled. Fixes that were clearly right landed in the
same commit as this report; judgment calls are filed.

## The finding that mattered

`5419aee` earlier today restored 14 of 17 contraindications that `802e51a`
had dropped. That was caught by asking the question this pass exists to ask,
before the pass ran, and it is written up in 03 F1 because the mechanism
generalises: an enum whose values do not all mean the same kind of thing
(`prehab` prevents, `rehab_late` is progressed to, only `rehab_early` is done
now) cannot be treated as one bucket when resolving a conflict.

The second finding (03 F2) is the one the pass itself produced: the 1b rule
pass generated zero rows for 13 injuries, every one an injury that already had
a handful of curated rows. So "55 of 56 mapped" was true and hid that ACL,
lumbar disc herniation, rotator cuff, tennis and golfer's elbow and eight
others were sitting on one to ten hand rows with no rule coverage. ACL had six
rows and did not contraindicate a single jump; a snowboarder who declared an
ACL injury was served Pogo Hops and Lateral Bounds. Fixed for ACL (+65 rows
over the impact, cutting, deceleration, pivot and catch patterns), filed for
the other twelve.

## Shipped

Build 125 tagged `v1.1.0-build125` at `a281bf2` on 2026-09-05 02:36 and
uploaded by `release.yml` run `33955721044` (**success**, 02:40). Gate was
`test.yml` on `cd9257e` (run `33954583727`, success), the last commit that
touched app code; the tag sits two commits above it, over a concurrent
session's test-only `f7369a3` and the one-line build bump.

What is in it since 124: the six decisions (injury table, equipment fallback,
hangboard cap, ski upper body, first-principles routines, sample workouts on
the wheel), the R3 fixes (upperStrength weights, signature-gone message, copy),
the finger content for injured climbers, the last-resort floor, four bodyweight
routines, the ACL rule, and the injury-role corrections in both directions.
Declared-empty days in the filter-composition grid: 315 at 124's content, 15
now.
