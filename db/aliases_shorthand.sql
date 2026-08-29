-- aliases_shorthand.sql — display shorthand -> canonical exercise.
--
-- The UI shows short names ("Bench Press") because a Today screen reads
-- calmer that way; coach.db stays specific ("Barbell Bench Press") because
-- the generator, substitutions and muscle mapping need the precision. These
-- rows are the join between the two, read by
-- CoachDatabase.exerciseId(forImportName:) and through it by
-- ExerciseLookupCache, which is what puts the exercise photo on the row.
--
-- Every target was chosen by hand. An alias pointing at the wrong variant is
-- invisible in the UI (a plausible photo looks correct), so do not generate
-- these by fuzzy match.
--
-- Applied to PhaseTraining/Resources/coach.db, which is a hand-edited tracked
-- binary (see .claude/skills/phase-training-coachdb-commit-vs-artifact-drift).
-- This file exists so the edit is reviewable and repeatable; the binary diff
-- is not. Re-run with:
--   sqlite3 PhaseTraining/Resources/coach.db < db/aliases_shorthand.sql

INSERT OR IGNORE INTO exercise_aliases (exercise_id, alias, source, notes) VALUES
  (900,  'Bench Press',      'common_name', 'UI shorthand; canonical is Barbell Bench Press'),
  (922,  'Pull Up',          'common_name', 'UI shorthand; canonical spells it Pull-Up'),
  (904,  'Overhead Press',   'common_name', 'UI shorthand; canonical is Barbell Overhead Press (Strict)'),
  (1028, 'Incline Row',      'common_name', 'UI shorthand; canonical is Incline Row (Dumbbell). No bundled photo for 1028'),
  (544,  'Skullcrusher',     'common_name', 'UI shorthand; canonical is Skull Crusher (Lying Triceps Extension)'),
  (24,   'Face Pull',        'common_name', 'UI shorthand; canonical is Face Pull (Cable or Band)'),
  (907,  'Incline DB Press', 'common_name', 'UI shorthand; canonical is Incline Dumbbell Bench Press'),
  (546,  'Lateral Raise',    'common_name', 'UI shorthand; dumbbell is the unqualified gym default');
