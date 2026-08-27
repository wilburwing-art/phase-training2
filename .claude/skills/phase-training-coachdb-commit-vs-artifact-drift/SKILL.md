---
name: phase-training-coachdb-commit-vs-artifact-drift
description: When auditing or trusting a phase-training-family (phase-training2, phase-training, workout-plan) catalog/cleanup/taxonomy commit, do NOT believe the commit message's row counts — query the bundled `coach.db` directly. The recurring trap (seen in commit 0405ef6): a `scripts/cleanup-niche-exercises.sh` gets committed AND the Swift layer gets rebuilt for the intended post-cleanup world (e.g. 7 soreness buckets, 361 exercises, mobility removed), but the regenerated `coach.db` blob is never landed — so the shipped artifact is still the pre-cleanup 551-exercise / 11-modality firehose while code + commit message describe 361/7. The cleanup becomes LATENT: it only activates if someone later runs the script. Trigger when auditing a phase-training catalog/cleanup/taxonomy commit, when a commit message says "551→361" or "removed X modality", when reconciling soreness-bucket / library-tile counts against the DB, or before reporting what a cleanup "did." Also covers the sibling gotcha: eval-rig "9/9" grades are human-produced with NO automated rubric-pass guard.
when-to-use: Auditing/summarizing a phase-training2 catalog-cleanup or taxonomy commit, or reconciling Swift bucket/tile counts against the bundled coach.db. Verify the artifact, not the commit message. ALSO covers the multi-copy case: when two coach.db files exist (db/coach.db build artifact vs PhaseTraining/Resources/coach.db shipped) and one looks "richer" — do NOT trust raw row-count deltas as a merge opportunity; resolve cross-DB by NAME first (the extra rows are usually orphans for pruned exercises = 0 coverage gain).
---

# phase-training coach.db: commit message lies, query the artifact

## The trap (commit 0405ef6, confirmed 2026-05-26)

Commit said "551→361 exercises, 11→7 soreness buckets, mobility removed end-to-end."
Reality of the shipped `PhaseTraining/Resources/coach.db`:

```bash
DB=PhaseTraining/Resources/coach.db
sqlite3 "$DB" "SELECT COUNT(*) FROM exercises;"   # 551, NOT 361
sqlite3 "$DB" "SELECT modality, COUNT(*) FROM exercises
  WHERE modality IN ('mobility','prehab','pt_rehab','warm_up','recovery',
  'flexibility','balance','coordination','breathing') GROUP BY modality;"
  # 190 rows still present (prehab 73, mobility 41, balance 27, ...)
```

`scripts/cleanup-niche-exercises.sh` was committed; its OUTPUT (the pruned DB) was not. The Swift layer (`MuscleBucket.sorenessPrimaryCases` cut to 7, `LibraryTile` taxonomy) was rebuilt for 361/7 anyway. **Two contradictory halves shipped together.** The library + generator still surface prehab/mobility/balance rows the commit claims are gone.

## Why this is easy to miss

- The 7-bucket soreness UI and tap-tile Library are real code changes that work regardless of DB row count — they make the app *look* cleaned up.
- Codable migrations (`DayKind.init(from:)` rewrites `"mobility"`→`.rest`) are clean, so nothing crashes.
- The commit message reads as fact; only `sqlite3` on the blob disproves it.

## Always do this when a cleanup commit claims DB changes

1. `git log --oneline -- scripts/cleanup-*.sh` — confirm the script exists.
2. Query the bundled `coach.db` for the counts the message claims. If they don't match, the cleanup is **latent, not applied** — report the contradiction, don't repeat the commit message.
3. Check whether running the script would activate downstream breakage (e.g. `exercise_injury_relevance` collapses, orphaned prehab pathways) before recommending it. See `phase-training-coachdb-cleanup-by-cascade` for the actual execution.

## Multi-copy divergence + the "richer DB" salvage mirage (confirmed 2026-05-31)

Two coach.db copies exist: `db/coach.db` (untracked build artifact, May 25) and `PhaseTraining/Resources/coach.db` (git-tracked, hand-edited, shipped). `db/` is the build dir — `db/source/*.json` (755-exercise pre-prune source) + `general_strength.sql` + `db/source/media/`. Resources is canonical: the prune (755→564) and "+91 aliases" commits edit the **binary directly**, never reflected back into `db/source`. So `db/source` JSON is stale at 755 — **a rebuild from it would silently undo the prune + aliases.** That, not db/coach.db, is the live drift hazard.

The trap: db/coach.db showed 989 substitutions vs shipped 537 — looks like a richer source to "merge in" and fix the 30% substitute coverage (stagnation swap no-ops ~70%). It is NOT. Resolve cross-DB by NAME before believing any delta:

```bash
sqlite3 PhaseTraining/Resources/coach.db "
ATTACH 'db/coach.db' AS src;
-- name overlap (only 361 of ~564 overlapped — divergent catalogs, not super/subset)
SELECT COUNT(*) FROM exercises a JOIN src.exercises b ON lower(a.name)=lower(b.name);
-- src subs whose BOTH endpoints exist in shipped AND shipped lacks today => NET-NEW coverage
SELECT COUNT(*) FROM src.exercise_substitutions s
  JOIN src.exercises se ON se.id=s.exercise_id JOIN src.exercises te ON te.id=s.substitute_id
  WHERE lower(se.name) IN (SELECT lower(name) FROM exercises)
    AND lower(te.name) IN (SELECT lower(name) FROM exercises)
    AND lower(se.name) NOT IN (SELECT lower(e.name) FROM exercises e JOIN exercise_substitutions x ON x.exercise_id=e.id);
"
```

Result: 537 of 989 name-resolvable (== exactly the 537 shipped already has); the other 452 reference pruned/absent exercises; **net-new coverage = 0.** Merging is worthless. Raising coverage requires AUTHORING new subs for the current catalog (same movement_pattern + overlapping primary muscles), not a merge. Substitutes join `exercise_substitutions` (note the `-ions` suffix; code queries it correctly) ordered by `similarity_score DESC`.

## Sibling gotcha (same "verify, don't trust" theme)

eval-rig "9/9" grades come from a human readline loop (`grade.ts`), NOT CI. The phase-training2 `EvalRigExportSmokeTest` asserts only `XCTAssertFalse(exercises.isEmpty)` — no score/gate/rest/RPE assertion. A generator change can silently regress a rubric score with zero test failure. The rubric (rest 180/120/90, RPE-7 cap, 5/5/3 warm-up) is hardcoded in `WorkoutGenerator.swift` but the rubric itself is editable data in `eval-rig/rubric/` — no link, drifts silently. Don't report a score as "passing" without confirming it was freshly graded.

## Reconcile (the FIX — confirmed 2026-06-04)

The drift's root: `db/source` is stale at 755 (pre-prune superset) while the
shipped binary is the curated 564, AND `build_db.py` rebuilds the WHOLE DB from
source. So a naive `build_db.py` UNDOES the prune (re-ships the 191
prehab/mobility/balance firehose). Two operations, opposite directions:

- **Add a few exercises, prune in place:** do NOT `build_db.py`. Surgically
  `INSERT` your new ids into the shipped binary from a donor build (`ATTACH
  donor.db; INSERT OR IGNORE INTO exercises SELECT * FROM donor.exercises WHERE
  id IN (...)` across exercises + exercise_{equipment,muscles,movement_patterns,
  phases}). Keeps the prune; ships exactly your rows.
- **Permanently fix the drift (make build_db idempotent):** regenerate source
  FROM the canonical binary — `python3 scripts/db/extract_to_source.py` dumps the
  shipped `coach.db` back into `db/source/*.json` deterministically. Then
  `python3 scripts/db/build_db.py` and verify the rebuild equals the prior
  artifact (every table's row count + the full exercise-id set; expect 0/0
  divergence). Now source builds exactly what ships; the firehose is gone from
  source; the artifact compacts (free pages from un-VACUUMed prune DELETEs drop,
  ~2.29→1.70MB). Commit the regenerated source + rebuilt binary together.

Direction matters: `extract_to_source` = DB→source (use to reconcile);
`build_db` = source→DB (idempotent only AFTER reconciling). Never run `build_db`
to "resync" while source is the stale superset — that's the footgun.
