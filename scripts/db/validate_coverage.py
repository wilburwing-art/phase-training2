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
    "rowing", "paddle-sports", "stand-up-paddleboarding",
    "obstacle-course-racing",
]

ANTAGONIST_MIN = 5  # antagonist exercises needed per sport for Tier 1.5 to feel meaningful
DIFFICULTY_MIN = 20  # routines per difficulty bucket — below this a user with that experience gets thin pickings


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
    if not (missing_sports or thin_antagonist or missing_recovery):
        print("  All app-catalog sports have full coverage.")

    conn.close()


if __name__ == "__main__":
    main()
