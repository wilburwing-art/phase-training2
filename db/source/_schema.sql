CREATE TABLE common_injuries (
  id                       INTEGER PRIMARY KEY,
  name                     TEXT NOT NULL UNIQUE,
  slug                     TEXT NOT NULL UNIQUE,
  body_region              TEXT,
  description              TEXT,
  mechanism                TEXT,
  typical_recovery         TEXT,
  created_at               TEXT DEFAULT (datetime('now'))
);

CREATE TABLE equipment (
  id                       INTEGER PRIMARY KEY,
  name                     TEXT NOT NULL UNIQUE,
  slug                     TEXT NOT NULL UNIQUE,
  category                 TEXT,
  portability              TEXT CHECK (portability IN ('portable','gym_only','outdoor_only','any')),
  estimated_cost           TEXT CHECK (estimated_cost IN ('low','medium','high')),
  home_gym_friendly        INTEGER DEFAULT 0 CHECK (home_gym_friendly IN (0,1)),
  created_at               TEXT DEFAULT (datetime('now'))
);

CREATE TABLE exercise_aliases (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  exercise_id   INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  alias         TEXT NOT NULL,
  source        TEXT CHECK (source IN (
                  'common_name',    -- everyday gym name ("RDL", "DL")
                  'sport_name',     -- discipline-specific ("crimp grip", "front lever")
                  'brand',          -- equipment-brand name ("ViPR shovel", "Bulgarian bag")
                  'historical',     -- older name still in literature
                  'misspelling',    -- common typo we want to forgive
                  'translation'     -- non-English label
                )),
  notes         TEXT,
  created_at    TEXT DEFAULT (datetime('now'))
);

CREATE TABLE exercise_equipment (
  exercise_id     INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  equipment_id    INTEGER NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
  is_required     INTEGER DEFAULT 1 CHECK (is_required IN (0,1)),
  PRIMARY KEY (exercise_id, equipment_id)
);

CREATE TABLE exercise_injury_relevance (
  exercise_id     INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  injury_id       INTEGER NOT NULL REFERENCES common_injuries(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('prehab','rehab_early','rehab_late','contraindicated')),
  notes           TEXT,
  PRIMARY KEY (exercise_id, injury_id, role)
);

CREATE TABLE exercise_movement_patterns (
  exercise_id         INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  movement_pattern_id INTEGER NOT NULL REFERENCES movement_patterns(id) ON DELETE CASCADE,
  PRIMARY KEY (exercise_id, movement_pattern_id)
);

CREATE TABLE exercise_muscles (
  exercise_id     INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  muscle_group_id INTEGER NOT NULL REFERENCES muscle_groups(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('primary','secondary','stabilizer')),
  PRIMARY KEY (exercise_id, muscle_group_id)
);

CREATE TABLE exercise_phases (
  exercise_id     INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  phase           TEXT NOT NULL CHECK (phase IN ('off_season','base','build','peak','race','recovery','maintenance')),
  priority        TEXT CHECK (priority IN ('primary','supplementary','optional')),
  volume_guidance TEXT,
  PRIMARY KEY (exercise_id, phase)
);

CREATE TABLE exercise_sport_relevance (
  exercise_id                INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  sport_id                   INTEGER NOT NULL REFERENCES sport_categories(id) ON DELETE CASCADE,
  relevance_score            REAL NOT NULL DEFAULT 0.5 CHECK (relevance_score BETWEEN 0.0 AND 1.0),
  specificity                TEXT CHECK (specificity IN ('general','related','highly_specific')),
  support_role               TEXT NOT NULL CHECK (support_role IN (
                               'direct_strength','antagonist','prehab','mobility',
                               'power','conditioning','general_foundation','recovery')),
  season_emphasis            TEXT,  -- JSON array: any of pre_season, in_season, off_season, all
  in_season_volume_modifier  REAL DEFAULT 1.0,
  off_season_volume_modifier REAL DEFAULT 1.0,
  notes                      TEXT,
  PRIMARY KEY (exercise_id, sport_id, support_role)
);

CREATE TABLE exercise_substitutions (
  exercise_id         INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  substitute_id       INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  context             TEXT NOT NULL CHECK (context IN (
                        'lower_intensity','lower_recovery','home_friendly',
                        'pre_event_safe','low_energy','equipment_swap',
                        'age_friendly','time_efficient')),
  similarity_score    REAL DEFAULT 0.5 CHECK (similarity_score BETWEEN 0.0 AND 1.0),
  notes               TEXT,
  PRIMARY KEY (exercise_id, substitute_id, context),
  CHECK (exercise_id != substitute_id)
);

CREATE TABLE exercises (
  id                       INTEGER PRIMARY KEY,
  name                     TEXT NOT NULL,
  slug                     TEXT NOT NULL UNIQUE,
  description              TEXT NOT NULL,
  instructions             TEXT NOT NULL,
  cues                     TEXT,   -- JSON array
  difficulty               TEXT NOT NULL CHECK (difficulty IN ('beginner','intermediate','advanced','elite')),
  modality                 TEXT NOT NULL CHECK (modality IN (
                             'strength','power','endurance','flexibility','mobility',
                             'balance','coordination','agility','speed','plyometric',
                             'sport_drill','pt_rehab','prehab','breathing','recovery',
                             'warm_up','cool_down')),
  movement_plane           TEXT CHECK (movement_plane IN ('sagittal','frontal','transverse','multi_plane')),
  energy_system            TEXT CHECK (energy_system IN ('phosphagen','glycolytic','oxidative','mixed')),
  contraction_type         TEXT CHECK (contraction_type IN ('concentric','eccentric','isometric','plyometric','ballistic')),
  is_unilateral            INTEGER DEFAULT 0 CHECK (is_unilateral IN (0,1)),
  is_compound              INTEGER DEFAULT 1 CHECK (is_compound IN (0,1)),
  environment              TEXT DEFAULT 'gym' CHECK (environment IN ('gym','home','outdoor','sport_facility','travel','anywhere')),

  default_sets             INTEGER,
  default_reps             TEXT,
  default_rest             TEXT,
  default_tempo            TEXT,
  default_duration         TEXT,

  time_efficient_variation TEXT,
  home_variation           TEXT,
  age_considerations       TEXT,
  desk_worker_notes        TEXT,

  recovery_demand          INTEGER CHECK (recovery_demand BETWEEN 1 AND 10),
  cns_load                 INTEGER CHECK (cns_load BETWEEN 1 AND 10),
  intensity_category       TEXT CHECK (intensity_category IN ('low','moderate','high','max')),
  fatigue_type             TEXT,   -- JSON array
  swap_group               TEXT,
  low_energy_suitable      INTEGER DEFAULT 0 CHECK (low_energy_suitable IN (0,1)),
  pre_event_safe           INTEGER DEFAULT 1 CHECK (pre_event_safe IN (0,1)),
  warmup_compatible        INTEGER DEFAULT 0 CHECK (warmup_compatible IN (0,1)),

  injury_prevention_notes  TEXT,
  contraindications        TEXT,   -- JSON array
  pt_rehab_relevance       TEXT,
  common_compensations     TEXT,   -- JSON array
  regression               TEXT,
  progression              TEXT,

  video_url                TEXT,
  image_url                TEXT,
  thumbnail_url            TEXT,
  source_video_attribution TEXT,
  image_source             TEXT,   -- free-exercise-db | wger | wikimedia | youtube | other
  image_license            TEXT,   -- MIT | Unlicense | CC-BY-SA-4 | CC-BY-4 | PUBLIC-DOMAIN | CC0 | YouTube ToS
  image_attribution        TEXT,   -- human-readable attribution string

  source_name              TEXT,
  source_url               TEXT,
  source_type              TEXT CHECK (source_type IN ('peer_reviewed','clinical','governing_body','coaching','expert_consensus')),
  source_year              INTEGER,

  tags                     TEXT,   -- JSON array

  created_at               TEXT DEFAULT (datetime('now')),
  updated_at               TEXT DEFAULT (datetime('now'))
);

CREATE TABLE injury_sport_prevalence (
  injury_id       INTEGER NOT NULL REFERENCES common_injuries(id) ON DELETE CASCADE,
  sport_id        INTEGER NOT NULL REFERENCES sport_categories(id) ON DELETE CASCADE,
  prevalence      TEXT CHECK (prevalence IN ('common','occasional','rare')),
  notes           TEXT,
  PRIMARY KEY (injury_id, sport_id)
);

CREATE TABLE movement_patterns (
  id                       INTEGER PRIMARY KEY,
  name                     TEXT NOT NULL UNIQUE,
  slug                     TEXT NOT NULL UNIQUE,
  description              TEXT,
  body_region              TEXT
);

CREATE TABLE muscle_groups (
  id                       INTEGER PRIMARY KEY,
  name                     TEXT NOT NULL UNIQUE,
  slug                     TEXT NOT NULL UNIQUE,
  parent_id                INTEGER REFERENCES muscle_groups(id),
  body_region              TEXT CHECK (body_region IN ('upper_body','lower_body','core','full_body','neck')),
  created_at               TEXT DEFAULT (datetime('now'))
);

CREATE TABLE routine_exercises (
  id                       INTEGER PRIMARY KEY AUTOINCREMENT,
  routine_id               INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  exercise_id              INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  position                 INTEGER NOT NULL,
  superset_group           INTEGER,
  sets                     INTEGER,
  reps                     TEXT,
  rest                     TEXT,
  tempo                    TEXT,
  duration                 TEXT,
  notes                    TEXT,
  UNIQUE (routine_id, position)
);

CREATE TABLE routine_sports (
  routine_id               INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  sport_id                 INTEGER NOT NULL REFERENCES sport_categories(id) ON DELETE CASCADE,
  PRIMARY KEY (routine_id, sport_id)
);

CREATE TABLE routines (
  id                       INTEGER PRIMARY KEY,
  name                     TEXT NOT NULL,
  slug                     TEXT NOT NULL UNIQUE,
  description              TEXT,
  goal                     TEXT,
  difficulty               TEXT CHECK (difficulty IN ('beginner','intermediate','advanced','elite')),
  phase                    TEXT CHECK (phase IN ('off_season','base','build','peak','race','recovery','maintenance')),
  duration_minutes         INTEGER,
  frequency                TEXT,
  environment              TEXT CHECK (environment IN ('gym','home','outdoor','sport_facility','travel','anywhere')),
  time_commitment          TEXT,
  ideal_schedule           TEXT,
  notes                    TEXT,
  source_name              TEXT,
  source_url               TEXT,
  tags                     TEXT,   -- JSON array
  created_at               TEXT DEFAULT (datetime('now')),
  updated_at               TEXT DEFAULT (datetime('now'))
);

CREATE TABLE sport_categories (
  id                       INTEGER PRIMARY KEY,
  name                     TEXT NOT NULL UNIQUE,
  slug                     TEXT NOT NULL UNIQUE,
  description              TEXT,
  parent_id                INTEGER REFERENCES sport_categories(id),
  depth                    INTEGER NOT NULL DEFAULT 0,
  sort_order               INTEGER DEFAULT 0,
  typical_session_minutes  INTEGER,
  common_training_days     TEXT,
  peak_season              TEXT,
  common_injuries          TEXT,   -- JSON array of strings
  governing_body           TEXT,
  -- Phase 1.2 sport-coverage floor. When a depth<=1 sport is intentionally
  -- out of scope for training-plan generation, populate this with a short
  -- rationale (e.g. "No general-strength transfer; niche audience"). NULL =
  -- in scope. See scripts/validate_coverage.sql.
  unsupported_reason       TEXT,
  created_at               TEXT DEFAULT (datetime('now')),
  updated_at               TEXT DEFAULT (datetime('now'))
);

CREATE TABLE sport_recovery_profiles (
  sport_id                 INTEGER PRIMARY KEY REFERENCES sport_categories(id) ON DELETE CASCADE,
  typical_recovery_hours   INTEGER,
  primary_fatigue_type     TEXT,   -- JSON array
  muscles_loaded           TEXT,   -- JSON array
  avoid_before_session     TEXT,   -- JSON array
  ideal_supplement_timing  TEXT,
  notes                    TEXT
);

CREATE INDEX idx_ee_equipment                  ON exercise_equipment(equipment_id);

CREATE INDEX idx_em_muscle                     ON exercise_muscles(muscle_group_id);

CREATE INDEX idx_esr_sport_id                  ON exercise_sport_relevance(sport_id);

CREATE INDEX idx_esr_sport_role                ON exercise_sport_relevance(sport_id, support_role);

CREATE INDEX idx_esr_support_role              ON exercise_sport_relevance(support_role);

CREATE INDEX idx_exercise_aliases_alias    ON exercise_aliases(alias COLLATE NOCASE);

CREATE INDEX idx_exercise_aliases_exercise ON exercise_aliases(exercise_id);

CREATE UNIQUE INDEX idx_exercise_aliases_unique
  ON exercise_aliases(exercise_id, alias COLLATE NOCASE);

CREATE INDEX idx_exercises_difficulty          ON exercises(difficulty);

CREATE INDEX idx_exercises_environment         ON exercises(environment);

CREATE INDEX idx_exercises_low_energy          ON exercises(low_energy_suitable);

CREATE INDEX idx_exercises_modality            ON exercises(modality);

CREATE INDEX idx_exercises_pre_event_safe      ON exercises(pre_event_safe);

CREATE INDEX idx_exercises_swap_group          ON exercises(swap_group);

CREATE INDEX idx_exinj_injury                  ON exercise_injury_relevance(injury_id);

CREATE INDEX idx_injury_prev_sport             ON injury_sport_prevalence(sport_id);

CREATE INDEX idx_muscle_parent                 ON muscle_groups(parent_id);

CREATE INDEX idx_routine_ex_routine            ON routine_exercises(routine_id);

CREATE INDEX idx_routine_sports_sport          ON routine_sports(sport_id);

CREATE INDEX idx_sport_depth                   ON sport_categories(depth);

CREATE INDEX idx_sport_parent                  ON sport_categories(parent_id);

CREATE INDEX idx_sub_context                   ON exercise_substitutions(context);

CREATE INDEX idx_sub_substitute                ON exercise_substitutions(substitute_id);
