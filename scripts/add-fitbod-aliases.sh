#!/usr/bin/env bash
# add-fitbod-aliases.sh — Phase 3.5 alias expansion for Fitbod CSV import.
#
# The Phase 3 v1 importer landed at a 24% name match rate against a real
# 5,140-row Fitbod export. The gap is naming-convention drift: Fitbod
# strips equipment qualifiers ("Front Squat" instead of "Front Squat
# (Barbell)"), uses different word order ("Barbell Decline Bench Press"
# vs "Decline Bench Press (Barbell)"), and prefers spaces over hyphens
# ("Sit Up" vs "Sit-Up"). The coach.db exercise list itself is correct;
# what was missing was alias coverage for these forms.
#
# Each INSERT OR IGNORE is idempotent against the unique
# (exercise_id, alias COLLATE NOCASE) index, so this script is safe to
# re-run. Source values match the schema CHECK constraint —
# 'common_name' for the everyday Fitbod gym shorthand, 'brand' for
# Hammer Strength references (a Life Fitness equipment brand).
#
# After running, regenerate the bundled coach.db blob and re-run
# FitbodRealCSVSmokeTests to measure the new match rate. Per the
# phase-training-coachdb-commit-vs-artifact-drift skill, commit BOTH
# this script AND the resulting coach.db together.

set -euo pipefail

DB="${1:-PhaseTraining/Resources/coach.db}"
if [ ! -f "$DB" ]; then
    echo "coach.db not found at $DB" >&2
    exit 1
fi

before=$(sqlite3 "$DB" "SELECT COUNT(*) FROM exercise_aliases")
echo "exercise_aliases before: $before"

sqlite3 "$DB" <<'SQL'
BEGIN;

-- Equipment-defaulted forms (Fitbod omits the equipment qualifier when
-- the user picked it once in-app; export only carries the bare name).
INSERT OR IGNORE INTO exercise_aliases (exercise_id, alias, source) VALUES
  (450,  'Front Squat',                'common_name'),
  (58,   'Romanian Deadlift',          'common_name'),
  (1062, 'Rack Pulls',                 'common_name'),
  (916,  'Sumo Squat',                 'common_name'),  -- mapped to Sumo Deadlift; closest semantic match
  (101,  'Hip Thrust',                 'common_name'),
  (1082, 'Skullcrusher',               'common_name'),
  (965,  'Dumbbell Fly',               'common_name'),
  (1088, 'Air Squats',                 'common_name'),
  (1051, 'Lunge',                      'common_name'),
  (1101, 'Dip',                        'common_name'),  -- Fitbod "Dip" defaults to triceps dip
  (1071, 'Barbell Shoulder Press',     'common_name'),  -- Seated Overhead Press (Barbell)
  (903,  'Floor Press',                'common_name'),
  (909,  'Arnold Dumbbell Press',      'common_name'),
  (1120, 'Cable Crossover Fly',        'common_name'),
  (24,   'Cable Face Pull',            'common_name'),
  (968,  'Crunches',                   'common_name'),
  (950,  'Hammer Curls',               'common_name'),
  (973,  'Ab Crunch Machine',          'common_name'),
  (983,  'Back Extensions',            'common_name'),
  (984,  'Seated Back Extension',      'common_name'),
  (112,  'Standing Barbell Calf Raise','common_name'),
  (934,  'Lying Hamstrings Curl',      'common_name'),
  (997,  'Calf Press',                 'common_name'),
  (997,  'Seated Machine Calf Press',  'common_name'),
  (1182, 'Standing Machine Calf Press','common_name');

-- Hyphen / word-order / form-variation drift (same exercise, different label).
INSERT OR IGNORE INTO exercise_aliases (exercise_id, alias, source) VALUES
  (7,    'Ab Rollout',                            'common_name'),
  (14,   'Alternating Dumbbell Bench Press',      'common_name'),
  (57,   'Back Squat',                            'common_name'),
  (1010, 'Barbell Decline Bench Press',           'common_name'),
  (901,  'Barbell Incline Bench Press',           'common_name'),
  (1050, 'Barbell Lunge',                         'common_name'),
  (1168, 'Barbell Step Up',                       'common_name'),
  (8,    'Bent Over Barbell Row',                 'common_name'),
  (9,    'Cable Row',                             'common_name'),
  (953,  'Cable Tricep Pushdown',                 'common_name'),
  (955,  'Cable Rope Overhead Triceps Extension', 'common_name'),
  (955,  'Cable Rope Tricep Extension',           'common_name'),
  (1133, 'Cable Rope Hammer Curls',               'common_name'),
  (938,  'Cable Pull Through',                    'common_name'),
  (937,  'Cable Hip Adduction',                   'common_name'),
  (923,  'Chin Up',                               'common_name'),
  (922,  'Pull Up',                               'common_name'),
  (13,   'Push Up',                               'common_name'),
  (1122, 'Dumbbell Bent Over Row',                'common_name'),
  (1122, 'Dumbbell Row',                          'common_name'),
  (344,  'Dumbbell Bent Over Reverse Fly',        'common_name'),
  (344,  'Dumbbell Rear Delt Raise',              'common_name'),
  (948,  'Dumbbell Bicep Curl',                   'common_name'),
  (948,  'Seated Dumbbell Curl',                  'common_name'),
  (1011, 'Dumbbell Decline Bench Press',          'common_name'),
  (907,  'Dumbbell Incline Bench Press',          'common_name'),
  (966,  'Dumbbell Incline Fly',                  'common_name'),
  (1052, 'Dumbbell Lunge',                        'common_name'),
  (1075, 'Dumbbell Shoulder Press',               'common_name'),  -- Shoulder Press (Machine) — closest
  (1083, 'Dumbbell Skullcrusher',                 'common_name'),
  (1089, 'Dumbbell Squat',                        'common_name'),
  (1016, 'Elliptical',                            'common_name'),
  (921,  'Good Morning',                          'common_name'),
  (921,  'Stiff-Legged Barbell Good Morning',     'common_name'),
  (1025, 'Machine Hip Adductor',                  'common_name'),
  (936,  'Standing Hip Abduction',                'common_name'),
  (937,  'Standing Hip Adduction',                'common_name'),
  (1031, 'Jackknife Sit-Up',                      'common_name'),
  (1046, 'Lat Pulldown',                          'common_name'),
  (925,  'Wide Grip Lat Pulldown',                'common_name'),
  (1047, 'Single Arm Lat Pulldown',               'common_name'),
  (933,  'Single Leg Leg Extension',              'common_name'),
  (103,  'Single Leg Glute Bridge',               'common_name'),
  (305,  'Single Leg Hip Thrust',                 'common_name'),
  (108,  'Single Leg Romanian Deadlift',          'common_name'),
  (993,  'Machine Bicep Curl',                    'common_name'),
  (931,  'Machine Leg Press',                     'common_name'),
  (1075, 'Machine Shoulder Press',                'common_name'),
  (1090, 'Machine Squat',                         'common_name'),
  (1064, 'Reverse Barbell Curl',                  'common_name'),
  (969,  'Sit Up',                                'common_name'),
  (924,  'Neutral Grip Pull Up',                  'common_name'),
  (1123, 'Smith Machine Bent Over Row',           'common_name'),
  (1116, 'Smith Machine Close-Grip Bench Press',  'common_name'),
  (1114, 'Smith Machine Incline Bench Press',     'common_name'),
  (1117, 'Smith Machine Overhead Shoulder Press', 'common_name'),
  (1091, 'Smith Machine Squat',                   'common_name'),
  (1173, 'Smith Machine Stiff-Legged Deadlift',   'common_name'),
  (132,  'TRX Side Plank',                        'common_name'),
  (1153, 'Upright Row',                           'common_name'),
  (18,   'Tricep Push Up',                        'common_name');

-- Brand-named variants (Hammer Strength = Life Fitness brand).
INSERT OR IGNORE INTO exercise_aliases (exercise_id, alias, source) VALUES
  (1004, 'Hammerstrength Chest Press',           'brand'),
  (1004, 'Hammerstrength Decline Chest Press',   'brand'),
  (1027, 'Hammerstrength Incline Chest Press',   'brand'),
  (1030, 'Hammerstrength Iso Row',               'brand'),
  (1030, 'Hammerstrength High Row',              'brand');

COMMIT;
SQL

after=$(sqlite3 "$DB" "SELECT COUNT(*) FROM exercise_aliases")
echo "exercise_aliases after:  $after"
echo "added: $((after - before))"
