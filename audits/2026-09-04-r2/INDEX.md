# 2026-09-04 critique suite, second pass

Re-run of all 13 lenses from `audits/2026-09-03-critique-suite/` against current
`main`, after 7 Tier 0 and 6 Tier 1 items landed.

## What a re-run is for

Three questions per lens, in this order:

1. **Did the fixes land?** Not "is the commit there" but "does the behaviour the
   finding described still happen". The first pass's own critique 12 exists
   because a checked box is not evidence.
2. **Did the fixes break something?** Every Tier 0/1 change is a candidate
   regression, and the ones that changed generator output (T1-2) or a selector
   query (T1-9) move numbers the first pass measured.
3. **What did the first pass miss?** A second look at a surface someone has
   just edited finds different things than a first look at a surface nobody had.

Where nothing changed and nothing new turned up, the entry says so in a line
rather than restating the first pass. The first pass is the reference; this is
the delta.

## Ground rules carried forward

- Every finding cites `file:line` read this session.
- An absence claim needs the failed grep, quoted.
- Refuted claims stay visible. The first pass refuted three of its own findings
  (01 F1 mechanism, 01 F10, 11 F4); assume this one is wrong somewhere too.
- Re-measure rather than recall. Counts from 2026-09-03 are stale by
  construction: T1-2 changed movement counts and T1-9 changed which routines
  are selectable.

## Output

All 13 in **`R2-REPORT.md`**, one section each. Written as a single document
rather than 13 files because most of a second pass is delta: nine lenses have a
paragraph, and the two that moved (01 coaching quality, 03 safety) have the
space they need.

Four new findings: R2-01 (injury filter under the movement floor), R2-02
(primary-demand match vs recency), R2-03 (Health grant discoverability, raised
by Wilbur), R2-04 (simulator-collapse failure signature).

## After the second pass (same day)

Tier 1 closed at 10 of 11 (T1-5's mapping table left for a human on purpose;
its safe half, telling the user an injury has no filter, landed). Tier 2 at 8
of 10 done, T2-2 partial, T2-7 refuted. R2-01 and R2-02 fixed; R2-03 fixed;
R2-05 recorded with numbers and left as a product decision. The whole-scheme
gate on the final state is in `scratchpad/final2.log`.

## Shipped

Build 124 tagged `v1.1.0-build124` at `9c4a46f` on 2026-09-04 and handed to
`release.yml`. Gate for the tag was CI's `test.yml` on that exact commit
(run `33898540321`, **success** — the first green run on `main` since at least
2026-08-29). The local whole-scheme run against the same commit finished the
unit target at 1,071/0 and then wedged for 3.3 hours at UI test 12 on
"Wait for com.phasetraining.app to idle"; it was killed and CI used as the
gate instead, which is the gate this repo actually ships on.

## Status

| # | Lens | Second-pass state |
|---|---|---|
| 01 | Coaching quality | see R2-REPORT.md |
| 02 | Niche teardown | see R2-REPORT.md |
| 03 | Safety | see R2-REPORT.md |
| 04 | Coach red-team | see R2-REPORT.md |
| 05 | Cold-install funnel | see R2-REPORT.md |
| 06 | Lifecycle | see R2-REPORT.md |
| 07 | Accessibility | see R2-REPORT.md |
| 08 | Copy and voice | see R2-REPORT.md |
| 09 | Paywall | see R2-REPORT.md |
| 10 | Competitors | see R2-REPORT.md |
| 11 | App Review and privacy | see R2-REPORT.md |
| 12 | Backlog re-verification | see R2-REPORT.md |
| 13 | Test suite | see R2-REPORT.md |
