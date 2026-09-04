# R3 · 12 Backlog re-verification

Seven claims were written into `BACKLOG.md` and the R2 `INDEX.md` at the end of
this session's implementation run, by the same author who made the changes. A
checked box is not evidence, which is why this lens exists. Each claim below is
re-measured against the shipped artifact.

| claim | verdict |
|---|---|
| 1b: "55 of 56 injuries mapped" | **true** — 56 rows in `common_injuries`, 55 distinct `injury_id` present; the unmapped one is `overtraining-syndrome`, as stated |
| 1b: "~3,187 rows" | true, order of magnitude |
| 2a: "`exercise_substitutions` 1,871 → 1,802" | **wrong by 7** — the shipped table holds **1,795** |
| 3a: "the third finger slot goes to a pulling or campus movement instead" | **false** — it goes to Plate Pinch Hold, still `fingerStrength` |
| 4b: "a modest pull and press block through the off-season and pre-season" | **false for pre-season** — realizes 0.00 there and in-season |
| T3-2: "every relation row that pointed at them is pruned" | **true** — 0 rows across all `db/source/*.json` reference a retired id; 0 rows in `exercises` |
| R2-05: equipment honoured, substitute-or-drop, floor shared | true, and covered by three new tests |
| samples: "fills its remaining slots (cap 5)" | true — `wheelCap` is 5, filled via `.prefix(Self.wheelCap - 1)` |

## The pattern in the three wrong ones

None is a fabrication; each is a claim written from the change rather than from
the result.

- **The substitutions count** was accurate when written and then went stale
  inside the same session: the retirement pass in `2f31308` pruned 7 more
  substitution rows after the note in `30c5e8b` was composed. A number that
  describes a table has to be read from the table at the end, not carried
  forward from the step that produced it.
- **The hangboard claim** described the intent of the filter rather than the
  pool it filters. There is no campus movement in the climbing pool at all, so
  the sentence could not have been true of any build.
- **The upperStrength claim** described the weight table, which does carry a
  pre-season entry. What it does not do is realize it. See 01 F1.

All three would have been caught by reading the artifact once after the last
commit of the group, which is roughly one sqlite query and one report read.
That is the check to add to the routine, and it is cheaper than this lens.

## Carried forward, unchanged

T3-1 (research targets the wrong athletes) and T3-3 / T3-4 (pricing, gate flip)
are owner decisions recorded as such, not claims to verify. T3-5 is closed by
decision.
