# Handoff: Phase 6 program research, v2 pass

Research input for Phase 6 of `docs/PLAN-gap-backlog-2026-11e.md` (inherit or own program for the 81 sports without one). Written 2026-11-28 for whoever resumes the run or turns its output into `distill_*.py` rows.

## Where things are

| what | path |
|---|---|
| v2 spec (schema, gate, inherit rule, work order, appendices) | `~/Downloads/program_research_prompt_v2.md` |
| v1 spec and v1 output (all 81 sports) | `~/Downloads/program_research_prompt.md`, `~/Downloads/program_research_output.md` |
| v2 output so far, one JSON object per sport | `docs/research/phase6-v2-tierA.jsonl` (20 lines) |
| Hermes skill driving the run | `~/.hermes/skills/training-program-research/SKILL.md` |
| Hermes session holding the raw replies | `~/.hermes/state.db`, session `20261127_225551_f953d4`, assistant messages 9809 to 9866 |

The JSONL was pulled from the session database with a stream decoder, so each object is what Hermes sent. Hermes wrote no batch files to disk during the run, despite its own skill saying to.

## State

- Tier A (v2 orders 1 to 20) is done: 20 of 20 objects returned.
- Next: tier B, orders 21 to 23: `archery-shooting`, `soccer-recreational`, `alpine-downhill`. Then 24 to 31, then tier C (32 to 81).
- To resume in Hermes: say "continue" in the same session, or start a new one pointed at the v2 spec and say "start at order 21". Ask it to append each batch to `docs/research/phase6-v2-tierB.jsonl` as it goes.

## Tier A results

| slug | result | rec | parent | routines (qualifying) | qualifying phases |
|---|---|---|---|---|---|
| tennis-singles | found | inherit | tennis | 2 (2) | off_season, build |
| pickleball-doubles | found_weak | inherit | pickleball | 2 (2) | base, build |
| pickleball-singles | found_weak | inherit | pickleball | 2 (2) | base, build |
| skating-wheeled | found_weak | inherit | (family root) | 1 (1) | base |
| fly-fishing | found_weak | inherit | fishing-hunting | 2 (0) | none |
| bmx | found_weak | inherit | cycling | 1 (1) | off_season |
| snowshoeing | found_weak | inherit | snow-sports | 1 (1) | base |
| racquetball | found_weak | inherit | racquet-sports | 2 (2) | base, build |
| ice-climbing | found_weak | inherit | climbing | 2 (0) | none |
| sport-lead | found | inherit | sport-climbing | 2 (2, see below) | build |
| disc-golf | found_weak | inherit | golf | 1 (1) | build |
| ballroom-latin | found_weak | inherit | dance-fitness | 2 (2) | base |
| swim-butterfly | found_weak | inherit | lap-swimming | 2 (2) | base |
| ski-mountaineering | found_weak | inherit | mountaineering | 2 (2) | off_season, build |
| dodgeball-kickball | found_weak | inherit | team-rec-sports | 1 (1) | base |
| beach-tennis | found_weak | inherit | racquet-sports | 0 | none |
| wing-foiling | found_weak | inherit | surf-wave-sports | 1 (1) | base |
| highland-games | found_weak | inherit | strength-fitness-sports | 1 (1) | build |
| keelboat-racing | found | **own** | sailing-air-sports | 1 (1) | build |
| comp-lead | found | inherit | comp-climbing | 2 (2, see below) | build |

Counts: 19 inherit, 1 own. 4 `found`, 16 `found_weak`. Zero `maintenance` routines across all 20, the same gap v1 had and the spec's stated coverage priority.

## Read before using any of it

Checked 2026-11-28 against the session's tool log and the spec's section 8.1 rules.

1. **Almost nothing was read in full text.** The whole tier A run made 34 `web_search` calls and one `web_extract` call, which fetched two pages: PMC11412636 (tennis companion paper) and the Capital Strength pickleball PDF. Every other dose, rest, credential and year came from search snippets. Spec rule 8.1.5 ("every number appears in a source you read") does not hold for 18 of 20 sports. Treat each routine as a lead until its page is opened.
2. **Tennis doses cite a page that was never fetched.** The week-by-week arrays are attributed to S1, PMC10137064, which no tool call opened. The fetched page, PMC11412636, is S2 and its own `standard_notes` say "doses in S1". Open PMC10137064 Table 2 before trusting any tennis number.
3. **Search budget not met.** 34 searches over 20 sports is about 1.7 per sport against the 4 to 6 the spec asks for. The `searches_run` lists reach 4 to 6 only because they include other sports' queries from the same batch and v1 queries tagged "(v1)". Same failure as v1 item 6.
4. **Gate failures marked `qualifies: true`.** sport-lead's two routines and comp-lead's two routines have 1 exercise each (hangboard protocols). The gate needs 3, so all four should be `qualifies: false` with a gate note. Hermes flagged comp-lead itself. With that fix, both sports drop to 0 qualifying.
5. **keelboat-racing "own" rests on a routine Hermes assembled.** Its notes say "Exercises chosen from the printed leg/arm/core lists": the Swiss Sailing PDF prints a circuit method (60 reps or 120 s, 15 s between, 2 to 3 series) and exercise menus, and Hermes picked the 10. That is writing a program, which the skill's first hard rule forbids. Both Swiss Sailing sources and the Laser hiking paper are also dinghy or Olympic-class sailing; nothing in the record is keelboat-specific. Recheck before accepting "own".
6. **Schema slips.**
   - comp-lead `block` uses the key `sessions_per_word` (should be `sessions_per_week`), and the raw reply had a stray `]` after the last object.
   - ballroom-latin Workout A puts "wk5: ..." swaps in four exercises' `notes`, which rule 8.1.2 forbids.
   - sport-lead `sets_by_week` is `[3,4,5,5,3,4,5,5]` while its notes say "3-3-4-4-5-5-4-5". One of them is wrong.
7. **Estimates written as printed values.**
   - racquetball `duration_minutes: 50` from a printed "45-60 min".
   - wing-foiling `45` from "under 45 min".
   - Low ends of printed ranges used as `sets` (skating-wheeled "2-3", dodgeball "3-5", keelboat "2-3", bmx "2-3 rounds").
   - Each should carry the range as printed, or the choice should be stated as ours, the way the 4.x distill notes do.
8. **Catalog matches to fix.**

   | sport | printed exercise | matched to | why it is wrong |
   |---|---|---|---|
   | tennis | BP compound row | Chest Press (Band) | a row matched to a press; the substitute is a row |
   | fly-fishing | internal rotation | External Rotation | opposite movement |
   | racquetball | Clean and Press | Clean and Jerk (Barbell) | different lift |
   | snowshoeing | stork stand | Single-Leg Glute Bridge | a balance hold matched to a bridge |
   | highland-games | machine seated calf raise | Dumbbell Seated Calf Raise | wrong equipment |

9. **Model.** Hermes alternated between `baidu/ernie-5.5-flash-preview:free` and `z-ai/glm-5.3-flash` on OpenRouter rate limits mid-run. Both are free flash tiers.

## Facts to verify by hand

These are credentials and citations that decide `found` versus `found_weak`:

- bmx: Cowell, McGuigan, Cronin, Strength Cond J 2012 34(1). Check that the AUT affiliations and "BA, MS" are printed.
- sport-lead: authors and year of PMC6458579, plus the MaxHangs 3 min rest.
- comp-lead: "Cameron Hörst (coach, 5.15 climber)" as the Climbing.com author. The series is usually Eric Hörst's.
- keelboat-racing: the Swiss Sailing PDFs' 2015 date and Neunstöcklin's title. The hiking bench test claim ("longer duration associated with better finishing position") is attributed to a periodization PDF and needs its own source.
- highland-games: `block` cites S3 (the taper paper) for 14 weeks and 5 sessions, which come from McKim (S2).

## How this feeds Phase 6

Phase 6 done criteria are in the plan.

- **Inherit:** the tracker line becomes D with one sentence, and the slug becomes a row in `scripts/db/tag_family_children.py`.
- **Own:** the tracker line becomes C with a source at the Phase 0 #4 standard, the sport reaches 2 qualifying routines, and `DB` plus `T(SportPickerCatalogTests)` pass.

Against those criteria:

- 19 of 20 tier A sports recommend inherit. Each object's `rationale` is the D sentence once points 1 to 3 above are settled.
- No tier A sport is ready for "own" as returned. keelboat-racing has 1 qualifying routine (needs 2), and that routine has the problem in point 5.
- The `found_weak` routines are extracted so the owner can judge them (spec section 0.1). None meets the standard as recorded, so none should become a `distill_*.py` row until its source is read and accepted.
- The `conditioning` blocks and the `demands` and `outcome_tests` fields are useful even on inherit rows. Spec section 4 lets a sport inherit gym routines and still carry its own conditioning.

## Next action

Open PMC10137064, check Table 2 against `tennis-singles` in `docs/research/phase6-v2-tierA.jsonl`, and decide whether tier B runs as-is or with a rule that every routine's source page must be fetched with `web_extract` first.
