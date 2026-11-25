#!/usr/bin/env python3
"""Coverage validator for the bundled coach.db.

Reads the *generated* PhaseTraining/Resources/coach.db and reports gaps
that would cause planner features to silently no-op for some users:

  - Sports declared in the app's Sport.catalog but missing from
    sport_categories (the planner falls through to generic)
  - Sports with no antagonist tagging (Tier 1.5 antagonist substitution
    would be a no-op)
  - Sports with no recovery_profile (spacing logic can't reason about them)
  - Difficulty buckets that are dangerously thin (advanced users get
    intermediate/beginner because there's nothing else)

Doesn't fail the build — just prints a report. Wire to CI later if you
want a hard gate.
"""

import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = REPO_ROOT / "PhaseTraining" / "Resources" / "coach.db"

# Mirror of Sport.catalog in PhaseTraining/Data/TrainingMemory.swift.
# Update when Sport.catalog changes. Yes this is duplication; alternative is
# parsing the Swift file which is more brittle.
APP_SPORT_SLUGS = [
    "general-fitness",
    "climbing", "running", "cycling", "swimming", "tennis", "pickleball",
    "soccer", "basketball", "volleyball", "golf", "surfing",
    "snow-sports", "alpine-skiing", "ski-mountaineering", "mountaineering",
    "hiking-trekking", "trail-running",
    "yoga", "pilates", "crossfit", "powerlifting", "olympic-weightlifting",
    "bodybuilding", "martial-arts", "bjj", "boxing", "muay-thai",
    "rowing", "paddle-sports", "sup",
    "obstacle-course-racing",
]

ANTAGONIST_MIN = 5  # antagonist exercises needed per sport for Tier 1.5 to feel meaningful
DIFFICULTY_MIN = 20  # routines per difficulty bucket — below this a user with that experience gets thin pickings

# Same filter as CoachDatabase.authoredRoutineIds over every phase label: a
# full session (25+ min, 3+ exercises) whose goal is not an add-on block.
AUTHORED_EXCLUDED_GOALS = ("prehab", "mobility", "warm_up", "pt_rehab", "recovery")
PROGRAM_MIN_ROUTINES = 2  # a sport's program needs 2+ qualifying routines to rotate

# The routines with no source_name at b128f61. The owner kept them: they were
# distilled from hand-authored routines (backlog 2026-11e). Any other routine
# must name its source.
UNSOURCED_ALLOWED_IDS = frozenset({
    1, 2, 3, 4, 6, 7, 10, 12, 20, 21, 24, 25, 30, 31,
    32, 34, 35, 41, 42, 44, 45, 50, 51, 53, 54, 55, 60, 61,
    64, 65, 70, 71, 72, 74, 75, 80, 81, 82, 84, 90, 91, 93,
    95, 98, 99, 100, 101, 103, 104, 105, 106, 107, 108, 200, 201, 202,
    205, 206, 213, 214, 216, 217, 218, 220, 224, 226, 229, 230, 231, 232,
    233, 235, 236, 237, 238, 239, 242, 244, 245, 246, 247, 250, 251, 254,
    256, 257, 258, 259, 260, 262, 263, 269, 270, 272, 273, 275, 277, 278,
    279, 280, 281, 282, 283, 285, 292, 293, 294, 306, 307, 308, 309,
})


def qualifying_routine_counts(conn):
    """Qualifying routines per sport slug, for every row in sport_categories.

    Counts the sport's own routine_sports tags. A child sport resolves to its
    parent's program once 5.1 tags the child to the parent's routines, so the
    own tag count is the resolved count."""
    goals = ",".join("?" for _ in AUTHORED_EXCLUDED_GOALS)
    sql = f"""
        SELECT s.slug,
               COUNT(DISTINCT CASE
                   WHEN r.goal NOT IN ({goals})
                    AND COALESCE(r.duration_minutes, 0) >= 25
                    AND (SELECT COUNT(*) FROM routine_exercises re
                         WHERE re.routine_id = r.id) >= 3
                   THEN r.id END)
        FROM sport_categories s
        LEFT JOIN routine_sports rs ON rs.sport_id = s.id
        LEFT JOIN routines r ON r.id = rs.routine_id
        GROUP BY s.slug
        ORDER BY s.slug
    """
    return dict(conn.execute(sql, AUTHORED_EXCLUDED_GOALS).fetchall())


def program_coverage(conn):
    """Print sports without a program as a count (expected until backlog 11e
    Phase 5 closes). Return the routines missing a source_name that are not in
    the b128f61 allowlist; those fail the run."""
    counts = qualifying_routine_counts(conn)
    none = sorted(s for s, n in counts.items() if n == 0)
    one = sorted(s for s, n in counts.items() if n == 1)
    print("=== Sport program coverage ===")
    print(f"  sports: {len(counts)}  covered (>={PROGRAM_MIN_ROUTINES} qualifying routines): "
          f"{len(counts) - len(none) - len(one)}")
    print(f"  uncovered sports: {len(none) + len(one)} "
          f"({len(none)} with no routines, {len(one)} with one)")
    unsourced = conn.execute(
        "SELECT id, slug FROM routines WHERE COALESCE(TRIM(source_name), '') = '' ORDER BY id"
    ).fetchall()
    return [(rid, slug) for rid, slug in unsourced if rid not in UNSOURCED_ALLOWED_IDS]


def main():
    if not DB_PATH.exists():
        sys.exit(f"missing DB: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    print("=== App sport catalog coverage ===")
    missing_sports = []
    thin_antagonist = []
    missing_recovery = []
    for slug in APP_SPORT_SLUGS:
        row = conn.execute(
            "SELECT id FROM sport_categories WHERE slug = ?", (slug,)
        ).fetchone()
        if not row:
            missing_sports.append(slug)
            continue
        sport_id = row["id"]
        ant = conn.execute(
            "SELECT COUNT(*) FROM exercise_sport_relevance WHERE sport_id=? AND support_role='antagonist'",
            (sport_id,),
        ).fetchone()[0]
        rec = conn.execute(
            "SELECT 1 FROM sport_recovery_profiles WHERE sport_id=?", (sport_id,)
        ).fetchone()
        ex_total = conn.execute(
            "SELECT COUNT(DISTINCT exercise_id) FROM exercise_sport_relevance WHERE sport_id=?",
            (sport_id,),
        ).fetchone()[0]
        if ant < ANTAGONIST_MIN:
            thin_antagonist.append((slug, ant))
        if not rec:
            missing_recovery.append(slug)
        flag = "  " if ant >= ANTAGONIST_MIN else "!!"
        print(f"  {flag} {slug:<26}  exercises:{ex_total:>4}  antagonist:{ant:>3}  recovery:{int(bool(rec))}")

    print()
    print("=== Routine difficulty distribution ===")
    for row in conn.execute(
        "SELECT difficulty, COUNT(*) FROM routines GROUP BY difficulty ORDER BY 2 DESC"
    ):
        diff, count = row[0], row[1]
        flag = "  " if count >= DIFFICULTY_MIN else "!!"
        print(f"  {flag} {diff or '(null)':<14} {count:>4}")

    print()
    new_unsourced = program_coverage(conn)

    print()
    print("=== Summary ===")
    if missing_sports:
        print(f"  Sports in app catalog with NO sport_categories entry ({len(missing_sports)}):")
        for s in missing_sports:
            print(f"    - {s}")
    if thin_antagonist:
        print(f"  Sports with <{ANTAGONIST_MIN} antagonist exercises ({len(thin_antagonist)}):")
        for slug, n in thin_antagonist:
            print(f"    - {slug} ({n})")
    if missing_recovery:
        print(f"  Sports without sport_recovery_profiles ({len(missing_recovery)}):")
        for s in missing_recovery:
            print(f"    - {s}")
    if new_unsourced:
        print(f"  Routines added after b128f61 with no source_name ({len(new_unsourced)}):")
        for rid, slug in new_unsourced:
            print(f"    - {rid} {slug}")
    if not (missing_sports or thin_antagonist or missing_recovery or new_unsourced):
        print("  All app-catalog sports have full coverage.")

    conn.close()
    if new_unsourced:
        sys.exit(1)


if __name__ == "__main__":
    main()
