---
name: phase-training-coachdb-cleanup-by-cascade
description: Execute a bulk row-deletion against phase-training-family `coach.db` (phase-training, phase-training2, workout-plan) AFTER `catalog-messy-diagnose-before-cleanup` has run and the user has explicitly approved deletion. The schema's `ON DELETE CASCADE` chain means a single `DELETE FROM exercises WHERE modality IN (...)` auto-cleans every `exercise_*` join table plus `routine_exercises` — and a follow-up `DELETE FROM routines WHERE id NOT IN (SELECT routine_id FROM routine_exercises)` drops any routine that went empty. Trigger after the diagnose-skill has produced approval to actually delete, especially when the deletion targets a modality class (`prehab`/`mobility`/`recovery`/etc.) or any column with rich downstream relations. Skip for one-off single-row fixes (just write the SQL inline) or for renames-only (no FK impact, no cleanup needed).
when-to-use: User has approved bulk row deletion from phase-training-family `coach.db`. Diagnostic phase is done. You need to execute the actual delete without orphaning join-table rows or leaving empty routines.
---

# coach.db cleanup-by-cascade

## The schema's load-bearing property

All `exercise_*` join tables and `routine_exercises` declare `ON DELETE CASCADE`:

```
exercise_aliases, exercise_equipment, exercise_injury_relevance,
exercise_movement_patterns, exercise_muscles, exercise_phases,
exercise_sport_relevance, exercise_substitutions, routine_exercises
```

So `DELETE FROM exercises WHERE …` automatically drops every dependent row in those nine tables. You do NOT need to delete from them explicitly. The only post-step is sweeping routines that have zero remaining exercises.

## Recipe

Save as `scripts/cleanup-<descriptor>.sh` for reproducibility. Always backup, always log pre/post counts, always make it idempotent (re-run = no-op):

```bash
#!/usr/bin/env bash
set -euo pipefail
DB="PhaseTraining/Resources/coach.db"
ts="$(date +%Y%m%d-%H%M%S)"
cp "$DB" "${DB}.backup-${ts}"
echo "📦 Backup: ${DB}.backup-${ts}"

sqlite3 "$DB" "SELECT 'exercises',COUNT(*) FROM exercises UNION ALL SELECT 'routines',COUNT(*) FROM routines;"

sqlite3 "$DB" <<'SQL'
PRAGMA foreign_keys = ON;
-- Whatever your delete predicate is:
DELETE FROM exercises WHERE modality IN ('prehab','mobility','recovery',...);
-- Always follow with: drop routines that are now empty.
DELETE FROM routines WHERE id NOT IN (SELECT DISTINCT routine_id FROM routine_exercises);
SQL

sqlite3 "$DB" "SELECT 'exercises',COUNT(*) FROM exercises UNION ALL SELECT 'routines',COUNT(*) FROM routines;"
```

Also append `coach.db.backup-*` to `.gitignore`.

## Decouple from Swift cleanup with the empty-recipe stub

When the deletion strands a `WorkoutFocus` case (or any code path that queries the now-absent rows), don't try to rip the enum case + all 15+ switch sites in the same pass. Instead, make the recipe function return `[]` so the affected focus generates an empty workout. The UI still compiles, the DB matches, and the full enum removal can be a follow-up session.

```swift
case .mobility:
    // Recipe stubbed: underlying rows deleted. DayKind.mobility still
    // produces empty workouts pending full removal.
    return []
```

## Verify with the unit-test slice

After cleanup, run `test_sim` scoped to `PhaseTrainingTests` (the unit-test target). UI tests (`PhaseTrainingUITests`) are noisy and often fail for unrelated reasons (in-flight onboarding work, sim state) — don't gate cleanup-correctness on them.
