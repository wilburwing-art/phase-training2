#!/usr/bin/env python3
"""Distill Easy Strength (Dan John & Pavel) into coach.db as the generic base.

Source: ~/Downloads/Phase-Training/easy-strength-program-spec.md (a fully-cited
spec). Easy Strength is the classic autoregulated off-season strength BASE:
the five human movements (press / pull / hinge / squat / loaded carry) + a
solid ab set, ~2x5 per lift, "never miss, never grind, leave 1-2 in the tank,
finish stronger than you started" (the Rule of Ten, ~60-80% of max).

It lands as ONE `base`-phase routine tagged to `general-fitness` (added here —
it was a synthetic slug with no sport_categories row) AND to every outdoor
authored sport, so it rotates into their off-season. The AuthoredRoutineSelector
also falls back to the general-fitness pool, making Easy Strength the universal
cross-sport base whenever a sport/phase has no bespoke content.

All five movements already exist in the catalog — no new exercises.

Run:  python3 scripts/db/distill_easy_strength.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

GENERAL_FITNESS_SLUG = "general-fitness"
# sport_categories.id to tag the base routine to: general-fitness (added below)
# + the outdoor authored sports so it shows in their off-season rotation.
OUTDOOR_SPORT_IDS = {
    "snowboarding": 221, "mountain-biking": 2, "mountaineering": 150,
    "trail-running": 57, "hiking-trekking": 480, "thru-hiking": 483,
    "climbing": 100,
}

# (movement_name, sets, reps, rest, superset_group, notes) — the EES 2x5 staple.
ROUTINE = dict(
    name="Easy Strength — 5-Lift Base",
    goal="strength", difficulty="intermediate", phase="base", duration_minutes=40,
    frequency="5x/week", environment="gym", time_commitment="40 min",
    notes="Autoregulated — never miss a rep, never grind, leave 1-2 in the tank, "
          "finish feeling stronger than you started. ~60-80% of max on the 2x5s "
          "(Dan John / Pavel, Easy Strength). When the weight feels light, add load.",
    source_name="Easy Strength — Dan John & Pavel Tsatsouline (distilled)",
    tags=["general", "strength", "base", "off-season", "easy-strength", "5-lift"],
    exercises=[
        ("Barbell Overhead Press (Strict)", 2, "5", "2 min", None, "Press — 60-80%, never miss"),
        ("Weighted Pull-Up", 2, "5", "2 min", None, "Pull"),
        ("Trap Bar Deadlift", 2, "5", "2-3 min", None, "Hinge — heavy but easy"),
        ("Front Squat (Barbell)", 2, "5", "2-3 min", None, "Squat"),
        ("Farmer's Carry", 3, "40m", "60 sec", None, "Loaded carry — vary distance/load"),
        ("Ab Wheel Rollout", 1, "5", "60 sec", None, "One solid set"),
    ],
)


def slugify(name):
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -—–/&+'":
            out.append("-")
    s = "".join(out)
    while "--" in s:
        s = s.replace("--", "-")
    return s.strip("-")


def load(name):
    return json.load((SOURCE / f"{name}.json").open())


def save(name, rows):
    with (SOURCE / f"{name}.json").open("w") as f:
        json.dump(rows, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main():
    exercises = load("exercises")
    sport_categories = load("sport_categories")
    routines = load("routines")
    routine_exercises = load("routine_exercises")
    routine_sports = load("routine_sports")

    name_to_id = {e["name"].lower(): e["id"] for e in exercises}

    def blank(template_rows):
        return {k: None for k in template_rows[0].keys()}

    # 1. Ensure general-fitness has a sport_categories row (synthetic slug).
    gf_id = next((s["id"] for s in sport_categories if s["slug"] == GENERAL_FITNESS_SLUG), None)
    if gf_id is None:
        gf_id = max(s["id"] for s in sport_categories) + 1
        row = blank(sport_categories)
        row.update(id=gf_id, name="General Fitness", slug=GENERAL_FITNESS_SLUG,
                   parent_id=None, depth=0, sort_order=999, common_injuries=None,
                   created_at="2026-07-18 00:00:00", updated_at="2026-07-18 00:00:00")
        sport_categories.append(row)
        print(f"added sport_categories general-fitness (id {gf_id})")

    # 2. Add the routine (idempotent by slug).
    slug = slugify(ROUTINE["name"])
    if any(r["slug"] == slug for r in routines):
        print(f"skip (exists): {slug}")
        return

    unresolved = [mv for (mv, *_ ) in ROUTINE["exercises"] if mv.lower() not in name_to_id]
    if unresolved:
        print("UNRESOLVED movements:", unresolved)
        return

    rid = max(r["id"] for r in routines) + 1
    rrow = blank(routines)
    rrow.update(
        id=rid, name=ROUTINE["name"], slug=slug, description=ROUTINE["notes"],
        goal=ROUTINE["goal"], difficulty=ROUTINE["difficulty"], phase=ROUTINE["phase"],
        duration_minutes=ROUTINE["duration_minutes"], frequency=ROUTINE["frequency"],
        environment=ROUTINE["environment"], time_commitment=ROUTINE["time_commitment"],
        notes=ROUTINE["notes"], source_name=ROUTINE["source_name"],
        tags=json.dumps(ROUTINE["tags"]),
        created_at="2026-07-18 00:00:00", updated_at="2026-07-18 00:00:00",
    )
    routines.append(rrow)

    # tag to general-fitness + every outdoor authored sport
    for sid in [gf_id, *OUTDOOR_SPORT_IDS.values()]:
        routine_sports.append({"routine_id": rid, "sport_id": sid})

    next_re_id = max((r["id"] for r in routine_exercises), default=0) + 1
    for pos, (mv, sets, reps, rest, ss, notes) in enumerate(ROUTINE["exercises"], start=1):
        xrow = blank(routine_exercises)
        xrow.update(id=next_re_id, routine_id=rid, exercise_id=name_to_id[mv.lower()],
                    position=pos, superset_group=ss, sets=sets, reps=reps, rest=rest, notes=notes)
        routine_exercises.append(xrow)
        next_re_id += 1

    save("sport_categories", sport_categories)
    save("routines", routines)
    save("routine_exercises", routine_exercises)
    save("routine_sports", routine_sports)
    print(f"added routine {rid}: {ROUTINE['name']} (tagged to {1 + len(OUTDOOR_SPORT_IDS)} sports)")


if __name__ == "__main__":
    main()
