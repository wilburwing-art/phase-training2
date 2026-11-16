# Mission: sport-prep extraction

Distill the outdoor and cross-training sport prep programs in the owner's licensed archives into authored coach.db routines, one sport at a time, so every outdoor sport in the app has written content for each phase.

The repo CLAUDE.md (`../../CLAUDE.md`) also applies. Paths below are relative to the repo root.

## Sources (read-only)

- `~/repos/mtntactical-plans`: the 81 plans in the Mountain section of `INDEX.md`, one markdown file each in `plans/`.
- `~/repos/uphillathlete-archive`: plans and programs (library articles are background only).
- `~/repos/shralpinism`: the owner's splitboard program.

Never edit a source archive.

## Current state

- `missions/sport-prep/inventory.md` holds the sport x phase gap grid and the ranked gap list. Read it first. Update the grid cell when a sport lands.
- Already distilled: `scripts/db/distill_snowboard.py`, `distill_mtb_preseason.py`, `distill_inseason_outdoor.py`, `distill_easy_strength.py`. Use `distill_inseason_outdoor.py` as the template.

## Done, per sport

1. A new `scripts/db/distill_<sport>.py` that is idempotent by slug and checks every exercise id against its expected catalog name, so a stale id fails the run.
2. At least one servable full-session routine per phase the source covers.
3. `python3 scripts/db/build_db.py` run, and `scripts/db/verify_coachdb_sync.sh` green before and after.
4. `python3 -m unittest scripts/db/test_build_db.py` green, and the unit class `-only-testing:PhaseTrainingTests/AuthoredRoutineTests` green.
5. One commit to `main` with the script, the `db/source` JSON diff and both regenerated coach.db files.
6. The inventory grid updated.

## The one app change in scope: `SportProfile.table`

Owner decisions, 2026-11-15:
- Cycling, running, paddle-sports and sup get rows in `PhaseTraining/Data/SportSeason/SportProfile.swift` so users can pick them. Copy the `authoredOnly` pattern. Suggested complement-day choices: cycling like mountain-biking (no signature), running `legEndurance`, paddle-sports and sup `upperDominant` with `pullEndurance`. Name the choice in the commit message.
- Sports on the ski engine (ski-mountaineering, alpine-skiing, snow-sports) get `writtenFirst: true` the way snowboarding has it, once their written routines exist. Sport days are then served as written, and the engine fills only a season with no routine.
- A row or a `writtenFirst` flip lands in the same commit as that sport's routines. A row with no routines fails `FilterCompositionTests` (isPlannable needs coverage) and `AuthoredRoutineTests.testEveryServedSportHasAServableRoutineInEveryPhase`. Run both classes.

## Out of scope

- Every other Swift change, including `AuthoredRoutineSelector`, `SportSeasonGenerator.supports`, `pilotSports` and the serving gates. If a sport needs one of these, stop and ask the owner.
- Schema changes to `db/source/_schema.sql`.
- Moving any sport onto the season engine.

## Rules carried from main development

**Written programs first.** Each sport gets its own program's sessions. Tagging another sport's routines to fill a cell is a fallback that needs the owner's yes. Copy sets, reps, rest and effort from the source as written. Keep the source's exercise order and session shape. Put the source's RPE or effort note in each movement's `notes` as "Effort: ...". Credit the plan in `source_name` (for example "MTI Mountain Bike Pre-Season V2 (distilled)") with `source_type` = `coaching`.

**A routine must clear three gates to be served** (load `phase-training-authored-routine-serving` for detail):
1. The sport is authored-served. Ski, ski-mountaineering and snow-sports stay on the season engine, so routines tagged only to them are never served. Flag such gaps in the inventory and skip them.
2. Full session: `goal` outside prehab, mobility, warm_up, pt_rehab, recovery, and `duration_minutes` >= 25.
3. Phase vocabulary is `off_season`, `base`, `build`, `maintenance`. Map pre-season to `build` and in-season to `maintenance`. Tag via `routine_sports` to a `sport_categories` row that exists. A synthetic slug with no row (`general-fitness` was one) serves nothing.

**Catalog exercises first.** Map each source movement to an existing exercise by name. When none fits, add it through the four-file path in `phase-training-coachdb-add-exercise-source-pipeline` (clone a row of the same kind so the CHECK enums stay valid; `tags` is a JSON string). Report every movement you added or approximated in the commit message and to the owner. If the source is unclear, stop and report; never invent a prescription the source does not contain.

**No MTI signature movements (owner decision, 2026-11-15).** Never add MTI-named movements (Leg Blaster, Mini Leg Blaster, Kneeling Slasher, Scotty Bob, Standing Founder and the like) to the catalog. Write a compound as its parts in the catalog, or use the closest catalog movement, or drop it. Record each substitution or drop in the movement's or routine's notes.

**Source JSON is the only edit point.** Never edit `db/coach.db` or `PhaseTraining/Resources/coach.db` directly. Query the built db to confirm counts before you report them; a commit message is not evidence.

**One sport per tranche.** Land and verify one sport, then pick the next from the ranked list. Never batch sports into one commit.

**Model routing for subagents.** Sonnet distills a sport. Haiku runs `build_db.py`, the tests and the commit. Opus only if a schema question comes up, and that is out of scope here, so ask first.

**Verification.** Lightest tier that catches the error. Send the xcodebuild log to a file and grep it: `grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`. Pick a simulator from `xcrun simctl list devices available`. One test run at a time.

**Commits.** Straight to `main`. No attribution of any kind: no Co-Authored-By, no Claude-Session trailer, no tool credit.

**Questions to the owner.** One line, two or three named choices, recommendation first, and what each answer triggers.

**Writing.** No em dashes or en dashes, no "X, not Y" phrasing, no "silently", no "deliberately" as a flourish. Mark any number you estimated instead of counted.

## Skills to load

- `phase-training-authored-routine-serving` before writing any routine.
- `phase-training-coachdb-add-exercise-source-pipeline` before adding an exercise.
- `phase-training-coachdb-commit-vs-artifact-drift` before reporting counts.
- `phase-training-xcodebuild-test-failed-grep-full-log` before running xcodebuild.
