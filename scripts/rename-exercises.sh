#!/usr/bin/env bash
#
# rename-exercises.sh — apply approved name simplifications to coach.db.
#
# Three classes, 39 total:
#   Class 1 (11)  Unilateral qualifier dropped when no bilateral sibling exists
#   Class 2 (7)   Droppable parentheticals (synonym/equipment/grip notes)
#   Class 3 (21)  Verbose / sport-context strip (sport_relevance covers context)
#
# Idempotent: re-running on already-renamed rows updates them to the same
# value (no-op). Backs up coach.db first.

set -euo pipefail

DB="PhaseTraining/Resources/coach.db"
[[ -f "$DB" ]] || { echo "❌ $DB not found — run from repo root." >&2; exit 1; }

ts="$(date +%Y%m%d-%H%M%S)"
backup="${DB}.backup-${ts}"
cp "$DB" "$backup"
echo "📦 Backup: $backup"

sqlite3 "$DB" <<'SQL'
PRAGMA foreign_keys = ON;

-- Class 1: unilateral qualifier dropped (no bilateral sibling)
UPDATE exercises SET name = 'Dumbbell Row'                  WHERE id = 10;
UPDATE exercises SET name = 'Glute Bridge'                  WHERE id = 103;
UPDATE exercises SET name = 'Romanian Deadlift'             WHERE id = 108;
UPDATE exercises SET name = 'Squat to Box'                  WHERE id = 128;
UPDATE exercises SET name = 'Hip Thrust'                    WHERE id = 305;
UPDATE exercises SET name = 'Kettlebell Clean'              WHERE id = 306;
UPDATE exercises SET name = 'Cable Paddle Pull'             WHERE id = 370;
UPDATE exercises SET name = 'Hip Thrust on Bench'           WHERE id = 415;
UPDATE exercises SET name = 'Landmine Row'                  WHERE id = 458;
UPDATE exercises SET name = 'Skater Squat'                  WHERE id = 601;
UPDATE exercises SET name = 'Push-Up on Stability Ball'     WHERE id = 654;

-- Class 2: droppable parentheticals
UPDATE exercises SET name = 'Hangboard Max Hang'            WHERE id = 2;
UPDATE exercises SET name = 'Front Lever Progression'       WHERE id = 6;
UPDATE exercises SET name = 'Neck Bridge'                   WHERE id = 121;
UPDATE exercises SET name = 'Arch Body Hold'                WHERE id = 487;
UPDATE exercises SET name = 'Ring Dip'                      WHERE id = 491;
UPDATE exercises SET name = 'Body Row'                      WHERE id = 499;
UPDATE exercises SET name = 'Skull Crusher'                 WHERE id = 544;

-- Class 3: verbose / sport-context strip
UPDATE exercises SET name = 'Back Squat (Eccentric)'        WHERE id = 129;
UPDATE exercises SET name = 'Agility Ladder Shuffle'        WHERE id = 228;
UPDATE exercises SET name = 'Calf Raise (Eccentric)'        WHERE id = 242;
UPDATE exercises SET name = 'Rotational Cable Punch'        WHERE id = 311;
UPDATE exercises SET name = 'Pallof Press'                  WHERE id = 375;
UPDATE exercises SET name = 'Rear-Foot-Elevated Split Squat' WHERE id = 393;
UPDATE exercises SET name = 'Plyo Push-Up'                  WHERE id = 478;
UPDATE exercises SET name = 'Wall Sit with Adduction'       WHERE id = 551;
UPDATE exercises SET name = 'Double-Under'                  WHERE id = 609;
UPDATE exercises SET name = 'Pogo Hops'                     WHERE id = 613;
UPDATE exercises SET name = 'Box Jump'                      WHERE id = 616;
UPDATE exercises SET name = 'Calf Raise (High-Rep)'         WHERE id = 636;
UPDATE exercises SET name = 'Ice Tool Swing'                WHERE id = 640;
UPDATE exercises SET name = 'Ice Tool Hang'                 WHERE id = 641;
UPDATE exercises SET name = 'Flutter Kick (Weighted)'       WHERE id = 652;
UPDATE exercises SET name = 'Water Polo Shot Simulation'    WHERE id = 666;
UPDATE exercises SET name = 'Harness Walk'                  WHERE id = 688;
UPDATE exercises SET name = 'Switch Lunge'                  WHERE id = 725;
UPDATE exercises SET name = 'Edge Alignment Drill'          WHERE id = 729;
UPDATE exercises SET name = 'Kettlebell Swing'              WHERE id = 761;
UPDATE exercises SET name = 'Sandbag Flip'                  WHERE id = 790;
SQL

echo ""
echo "── Sample of renamed rows ──"
sqlite3 "$DB" "SELECT id, name FROM exercises WHERE id IN (10, 305, 544, 666, 790) ORDER BY id;"

echo ""
echo "✅ 39 renames applied. Backup retained at $backup"
