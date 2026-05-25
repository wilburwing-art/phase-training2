#!/usr/bin/env bash
#
# cleanup-niche-exercises.sh — delete the 9 niche-modality exercises
# (prehab / mobility / recovery / warm_up / flexibility / pt_rehab / balance /
# coordination / breathing) from coach.db along with any routine that goes
# empty as a result. Warmups are now ramp sets of the working exercise instead.
#
# Idempotent: re-running on an already-cleaned DB is a no-op (DELETE matches
# zero rows). Backs up to coach.db.backup-<timestamp> before mutating.

set -euo pipefail

DB="PhaseTraining/Resources/coach.db"
if [[ ! -f "$DB" ]]; then
    echo "❌ $DB not found — run from repo root." >&2
    exit 1
fi

ts="$(date +%Y%m%d-%H%M%S)"
backup="${DB}.backup-${ts}"
cp "$DB" "$backup"
echo "📦 Backup: $backup"

echo ""
echo "── Pre-cleanup counts ──"
sqlite3 "$DB" "SELECT 'exercises', COUNT(*) FROM exercises UNION ALL SELECT 'routines', COUNT(*) FROM routines;"

sqlite3 "$DB" <<'SQL'
PRAGMA foreign_keys = ON;

-- Niche modalities. ON DELETE CASCADE in exercise_* and routine_exercises
-- means every join-table row pointing at these exercises drops automatically.
DELETE FROM exercises
WHERE modality IN (
    'prehab','mobility','recovery','warm_up','flexibility',
    'pt_rehab','balance','coordination','breathing'
);

-- Any routine that's now empty (zero remaining exercises) — usually a
-- pre/post-session warmup or cooldown routine. Drop it.
DELETE FROM routines
WHERE id NOT IN (SELECT DISTINCT routine_id FROM routine_exercises);
SQL

echo ""
echo "── Post-cleanup counts ──"
sqlite3 "$DB" "SELECT 'exercises', COUNT(*) FROM exercises UNION ALL SELECT 'routines', COUNT(*) FROM routines;"

echo ""
echo "✅ Cleanup complete. Backup retained at $backup"
