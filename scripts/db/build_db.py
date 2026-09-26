#!/usr/bin/env python3
"""Build coach.db from db/source/*.json files.

Single source of truth for the bundled SQLite. Edit the JSON files in
db/source/, run this script, commit both the JSON diff AND the regenerated
coach.db. Pure Python stdlib — no third-party deps so it runs anywhere with
Python 3.

Order matters for the 14 tables we kept. Parents go in first (lookup tables),
relations after. Foreign keys aren't enforced at runtime by the iOS app but
we still respect the dependency order for cleanliness.

Tables that were in the old server-product bundle (chat_*, coach_quality_*,
user_*, daily_sessions, exercise_logs, session_swaps, weekly_plans,
idempotency_cache, adjustment_log, adjustment_trigger_types) are
intentionally NOT in the TABLES list — they get dropped.
"""

import json
import shutil
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "db" / "source"
SCHEMA_FILE = SOURCE_DIR / "_schema.sql"
DEST_DB = REPO_ROOT / "db" / "coach.db"
APP_DB = REPO_ROOT / "PhaseTraining" / "Resources" / "coach.db"

# Load order matters: parents (lookup tables) before relations.
TABLES = [
    # Lookups
    "movement_patterns",
    "muscle_groups",
    "equipment",
    "common_injuries",
    "sport_categories",
    "sport_recovery_profiles",
    # Exercise records
    "exercises",
    "exercise_aliases",
    "exercise_phases",
    # Exercise relations
    "exercise_equipment",
    "exercise_muscles",
    "exercise_movement_patterns",
    "exercise_substitutions",
    "exercise_injury_relevance",
    "exercise_sport_relevance",
    # Season-aware generator (curated movement pool over the catalog)
    "sport_movements",
    # Cross-domain
    "injury_sport_prevalence",
    # Routines
    "routines",
    "routine_exercises",
    "routine_sports",
]

# Columns that store JSON arrays in the DB. We keep them as native lists in
# the source JSON for diff-friendliness, then re-encode on insert.
JSON_ARRAY_COLUMNS = {
    ("exercises", "cues"),
    ("sport_categories", "common_injuries"),
    ("sport_recovery_profiles", "primary_fatigue_type"),
    ("sport_recovery_profiles", "muscles_loaded"),
    ("sport_recovery_profiles", "avoid_before_session"),
    ("exercise_sport_relevance", "season_emphasis"),
    ("sport_movements", "demands"),
    ("sport_movements", "allowed_phases"),
    ("sport_movements", "allowed_variants"),
}


def renamed_without_alias(shipped_db, source_dir):
    """Exercises whose name changed since the shipped coach.db, with no alias
    row keeping the old name.

    The app keys a user's history by exercise NAME: previous sets, PRs,
    affinities and swap counts (session_exercises has no exercise_id). A
    rename therefore splits a user's history in two and resets their PRs for
    that lift. scripts/rename-exercises.sh renamed 39 at once with nothing to
    stop it. Keeping the old name as an exercise_aliases row at least keeps
    it searchable and resolvable (ExerciseLookupCache walks aliases); the
    history split itself needs the name-keyed lookups made alias-aware.

    Returns a list of (exercise_id, old_name, new_name).
    """
    if not Path(shipped_db).exists():
        return []
    conn = sqlite3.connect(shipped_db)
    try:
        old = dict(conn.execute("SELECT id, name FROM exercises").fetchall())
    finally:
        conn.close()
    new = {r["id"]: r["name"] for r in json.loads((Path(source_dir) / "exercises.json").read_text())}
    aliases = {(a["exercise_id"], a["alias"].lower())
               for a in json.loads((Path(source_dir) / "exercise_aliases.json").read_text())}
    return [(i, old[i], new[i]) for i in sorted(old)
            if i in new and old[i] != new[i] and (i, old[i].lower()) not in aliases]


def build(allow_renames=False):
    if not SCHEMA_FILE.exists():
        sys.exit(f"schema not found: {SCHEMA_FILE}\nRun extract_to_source.py first.")

    # 0. Rename guard, against the coach.db the app currently ships.
    renamed = renamed_without_alias(APP_DB, SOURCE_DIR)
    if renamed and not allow_renames:
        lines = "\n".join(f"  {i}: {o!r} -> {n!r}" for i, o, n in renamed)
        sys.exit(
            f"Refusing to build: {len(renamed)} shipped exercise(s) renamed with no alias for the old name.\n"
            f"{lines}\n"
            "User history (previous sets, PRs, affinities) is keyed by name, so a rename splits it.\n"
            "Add each old name to db/source/exercise_aliases.json, or pass --allow-renames to accept the split."
        )

    if DEST_DB.exists():
        DEST_DB.unlink()

    # 1. Schema
    schema_sql = SCHEMA_FILE.read_text()
    conn = sqlite3.connect(DEST_DB)
    conn.executescript(schema_sql)

    # 2. Data — one table at a time, in dependency order
    print(f"Building {DEST_DB.relative_to(REPO_ROOT)}")
    for table in TABLES:
        path = SOURCE_DIR / f"{table}.json"
        if not path.exists():
            print(f"  skip {table:<35} (no source file)")
            continue
        with path.open() as f:
            rows = json.load(f)
        if not rows:
            print(f"  empty {table:<35} (0 rows)")
            continue
        cols = list(rows[0].keys())
        placeholders = ",".join("?" * len(cols))
        sql = f"INSERT INTO {table} ({','.join(cols)}) VALUES ({placeholders})"
        for row in rows:
            values = []
            for c in cols:
                v = row.get(c)
                if (table, c) in JSON_ARRAY_COLUMNS and v is not None:
                    v = json.dumps(v)
                values.append(v)
            conn.execute(sql, values)
        print(f"  loaded {table:<35} {len(rows):>5} rows")

    conn.commit()

    # 3. Verify
    cur = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    actual = [r[0] for r in cur.fetchall()]
    expected = sorted(TABLES)
    missing = [t for t in expected if t not in actual]
    extra = [t for t in actual if t not in expected]
    if missing:
        print(f"\nWARNING: tables in source but missing from DB: {missing}")
    if extra:
        print(f"\nWARNING: extra tables in DB not in source list: {extra}")

    conn.close()

    # 4. Copy to app resources
    APP_DB.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(DEST_DB, APP_DB)
    size = APP_DB.stat().st_size
    print(f"\nWrote {APP_DB.relative_to(REPO_ROOT)} ({size:,} bytes)")


if __name__ == "__main__":
    build(allow_renames="--allow-renames" in sys.argv[1:])
