---
name: phase-training-coachdb-add-exercise-source-pipeline
description: How to ADD or edit an exercise in phase-training2's bundled coach.db — the canonical path is the source JSON, NOT the shipped artifact. coach.db is BUILT from db/source/*.json by scripts/db/build_db.py (pure stdlib), which regenerates db/coach.db AND copies it to PhaseTraining/Resources/coach.db. To add an exercise you append to FOUR JSON files: exercises.json (the 50-field row), exercise_movement_patterns.json ({exercise_id, movement_pattern_id}), exercise_muscles.json ({exercise_id, muscle_group_id, role:'primary'|'secondary'|'stabilizer'}), exercise_equipment.json ({exercise_id, equipment_id, is_required:0|1}); then run `python3 scripts/db/build_db.py` and commit BOTH the JSON diff and the regenerated coach.db. Trigger when adding/editing/renaming exercises in phase-training2, filling a catalog gap (e.g. bodyweight pull movements), when you're about to edit Resources/coach.db directly (DON'T — edit source + rebuild), or wiring a new movement_pattern/equipment/muscle. Skip for non-catalog coach.db work, for the drift HAZARD itself (phase-training-coachdb-commit-vs-artifact-drift), for deletions-by-cascade (phase-training-coachdb-cleanup-by-cascade), or sister repos that track coach.db without a JSON source.
---

# Adding an exercise to coach.db (phase-training2)

`Resources/coach.db` is a BUILD ARTIFACT. Never edit it (or `db/coach.db`)
directly — edit `db/source/*.json` and rebuild. `scripts/db/build_db.py`
docstring: "Edit the JSON in db/source/, run this script, commit both the JSON
diff AND the regenerated coach.db." It copies `db/coach.db` → `Resources/coach.db`.

## DRIFT RESOLVED (verified 2026-06-07) — but still run the sync check first
The 2026-06-04 trap below is FIXED: source was reconciled to the shipped
artifact (both 572 exercises) and CI now hard-fails on divergence via
`scripts/db/verify_coachdb_sync.sh` (rebuilds from source, compares a SHA-256
over `iterdump()` logical content — raw byte compare is unreliable across
libsqlite versions). So the clean path is live again: edit source → rebuild →
commit both; run the sync script before AND after to prove it. To reconcile a
future binary-only edit: `scripts/db/extract_to_source.py`. Historical trap
kept below in case drift recurs:

## ⚠ The historical trap (cost a bad commit 2026-06-04)
`build_db.py` rebuilds the WHOLE DB from `db/source` — it does NOT incrementally
add your rows. The shipped `Resources/coach.db` was a **deliberately PRUNED
artifact** (564 exercises), while `db/source` was **stale pre-prune** source (755).
The prune (`scripts/cleanup-niche-exercises.sh`, ~191 prehab/mobility/balance/
recovery rows) was applied to the BINARY and never reflected back into source. So
a blind `build_db.py` **silently UNDID the prune** — re-shipping the niche
firehose — even when you only meant to add 2 rows. Verify first:
```bash
git show HEAD:PhaseTraining/Resources/coach.db > /tmp/h.db
sqlite3 /tmp/h.db 'SELECT count(*) FROM exercises;'          # 564 (pruned, shipped)
python3 -c 'import json;print(len(json.load(open("db/source/exercises.json"))))'  # 755 (stale)
```
If they differ, do NOT blind-rebuild. Options: (a) **surgically INSERT** just your
new ids into the shipped DB (`ATTACH` the build output, copy rows 1184+); or
(b) get an explicit decision to re-ship the pruned set; or (c) reconcile source↔
artifact first. See `phase-training-coachdb-commit-vs-artifact-drift` (it says this
outright: "a rebuild from db/source would silently undo the prune + aliases").

## Steps
1. **Next id**: `max(id) + 1` across `exercises.json` (was 1183 → 1184…).
2. **Clone an existing row** of the same kind as your template (e.g. "Body Row
   (Rings or Bar)" for a row, "Scapular Retraction Hold" for bodyweight back).
   The exercises table has CHECK constraints (difficulty ∈ beginner/intermediate/
   advanced/elite; modality; movement_plane ∈ sagittal/frontal/transverse/
   multi_plane; energy_system; contraction_type; environment ∈ gym/home/outdoor/
   sport_facility/travel/anywhere; …). Cloning guarantees valid enums — then
   override id, name, slug, description, instructions, cues, is_compound,
   difficulty, default_reps. Keep ALL 50 keys.
3. **JSON-array gotcha** (`build_db.py` JSON_ARRAY_COLUMNS re-encodes on insert):
   `cues` is a NATIVE LIST in source; but `fatigue_type` and `tags` are stored as
   ESCAPED JSON STRINGS (`"[\"lats\",\"biceps\"]"`). Match the template per field
   or you double-encode.
4. **Link tables** — append rows keyed by the new id:
   - `exercise_movement_patterns.json`: pattern ids — horizontal-pull=14,
     vertical-pull=15, scapular-retraction=16 (see movement_patterns.json).
   - `exercise_muscles.json`: muscle_group_id + role. Back ids: lats=26, traps=27,
     mid-traps=29, lower-traps=30, rhomboids=31, delt-posterior=18, biceps=36.
   - `exercise_equipment.json`: equipment_id + is_required. bodyweight=1, table=100,
     chair=98, wall=99, yoga-mat=43.
5. **Build + verify**: `python3 scripts/db/build_db.py` (no args), then re-query
   `Resources/coach.db` to confirm the row + links landed.

## Equipment reality for bodyweight users
A bodyweight user's allowed slugs = `{bodyweight, chair, wall, table}`
(`TrainingMemory.bodyweightAlwaysAvailable` + `.bodyweight` adds nothing). An
exercise passes the filter iff its required equipment ⊆ that set. The catalog has
ZERO apparatus-free vertical/horizontal pulls (physically accurate) — adding
table/towel rows + prone raises is the fix, tagged equipment bodyweight(1) or
table(100). New exercises need no alias (aliases are for RENAMES only).
