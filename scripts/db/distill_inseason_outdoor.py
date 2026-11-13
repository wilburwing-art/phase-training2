#!/usr/bin/env python3
"""Distill in-season and trail-running strength routines into coach.db.

Adds eight authored strength routines that fill the empty sport and phase
cells: mountaineering, thru-hiking and hiking-trekking get two `maintenance`
routines each (in-season), and trail running gets two `build` routines
(pre-season). Sources are Mountain Tactical Institute plans, credited in
source_name.

Catalog exercises only. Each movement is checked against the expected catalog
name, so a stale id fails the run instead of linking the wrong exercise.
The draft's RPE column is written into each movement's `notes` as "Effort: ...".
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_inseason_outdoor.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

MOUNTAINEERING = 150
THRU_HIKING = 483
HIKING_TREKKING = 480
TRAIL_RUNNING = 57

FLEX_CREDIT = "Mountain Tactical Institute Mountain Athlete In-Season Flex; movement selection adapted by Phase Training (2026-11-12)"
PREP_CREDIT = "Mountain Tactical Institute Mountaineering & Hiking Prep; movement selection adapted by Phase Training (2026-11-12)"
ULTRA_CREDIT = "Mountain Tactical Institute Ultra Running Pre-Season Training Plan; movement selection adapted by Phase Training (2026-11-12)"

HARD = "hard but doable on the last round"

# Each movement: (exercise id, expected catalog name, sets, reps, effort cue, note)
ROUTINES = [
    dict(
        name="Mountaineering In-Season Strength: Squat, Bench, Lunge",
        sport=MOUNTAINEERING, phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=40, environment="gym", source_name=FLEX_CREDIT, notes=None,
        movements=[
            (57, "Barbell Back Squat", 6, "3", HARD,
             "Raise the load quickly each round until 3 reps is hard but doable"),
            (900, "Barbell Bench Press", 5, "5", HARD,
             "Raise the load each round until 5 reps is hard but doable"),
            (943, "Walking Lunge", 5, "5", HARD,
             "Same load progression as the bench press"),
            (638, "Dead Hang with Pack", 2, "30 count", "easy",
             'Substitute for "30-Count Dead Hang". The source uses it as a shoulder and back stretch, not grip work'),
        ],
    ),
    dict(
        name="Mountaineering In-Season Strength: Bodyweight Grind",
        sport=MOUNTAINEERING, phase="maintenance", goal="strength", difficulty="beginner",
        minutes=40, environment="home", source_name=PREP_CREDIT,
        notes="Needs a pull-up bar.",
        movements=[
            (13, "Push-Up", 6, "30-40% of your 2-minute max", 'steady, not frantic ("grind")',
             "Source movement is Hand Release Push-Up. Prep Week 1 sets 30%, Week 3 sets 40%"),
            (1051, "Lunge (Bodyweight)", 6, "30-40% of your 2-minute max", "steady",
             "Source movement is In-Place Lunge"),
            (922, "Pull-Up", 6, "30-40% of your max", "steady",
             "Source offers Negative Pull-Ups when you cannot do one; no catalog match (see list)"),
            (132, "Side Plank", 3, "30-45 sec per side", "steady",
             "Substitute for Side Plank Raises, from the plan's chassis grind"),
        ],
    ),
    dict(
        name="Thru Hike In-Season Strength: Lunge, Squat, Row",
        sport=THRU_HIKING, phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=40, environment="gym", source_name=FLEX_CREDIT, notes=None,
        movements=[
            (943, "Walking Lunge", 6, "5", HARD,
             "Raise the load quickly each round"),
            (57, "Barbell Back Squat", 5, "5", HARD,
             "Raise the load each round"),
            (373, "Renegade Row", 5, "5 per side", HARD,
             'Source says "5x Renegade Rows", raise the load each round'),
            (638, "Dead Hang with Pack", 2, "45 count", "easy",
             'Substitute for "45-Count Dead Hang"'),
        ],
    ),
    dict(
        name="Thru Hike In-Season Strength: Hinge, Thruster, Chin-Up",
        sport=THRU_HIKING, phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=40, environment="gym", source_name=FLEX_CREDIT, notes=None,
        movements=[
            (58, "Romanian Deadlift (Barbell)", 6, "3", HARD,
             'Substitute for "Hinge Lift" (see list). Raise the load quickly each round'),
            (1097, "Thruster (Barbell)", 5, "3", HARD,
             "Raise the load each round"),
            (923, "Chin-Up", 5, "3-6", "steady",
             "Source scales 3 (women) / 6 (men)"),
            (638, "Dead Hang with Pack", 2, "30 count", "easy",
             'Substitute for "30-Count Dead Hang"'),
        ],
    ),
    dict(
        name="Hiking In-Season Strength: Bodyweight Grind",
        sport=HIKING_TREKKING, phase="maintenance", goal="strength", difficulty="beginner",
        minutes=40, environment="home", source_name=PREP_CREDIT,
        notes="Needs a pull-up bar.",
        movements=[
            (13, "Push-Up", 6, "30-40% of your 2-minute max", 'steady ("grind")',
             "Source movement is Hand Release Push-Up"),
            (1051, "Lunge (Bodyweight)", 6, "30-40% of your 2-minute max", "steady",
             "Source movement is In-Place Lunge"),
            (922, "Pull-Up", 6, "30-40% of your max", "steady",
             "Source offers Negative Pull-Ups when you cannot do one"),
            (921, "Barbell Good Morning", 3, "6", "light, steady",
             "Substitute for Sandbag Good Morning (6 reps in the plan's 15 minute chassis grind). Use a pack or a light bar"),
        ],
    ),
    dict(
        name="Hiking In-Season Strength: Front Squat, Hinge, Pull-Up",
        sport=HIKING_TREKKING, phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=40, environment="gym", source_name=FLEX_CREDIT, notes=None,
        movements=[
            (58, "Romanian Deadlift (Barbell)", 6, "3", HARD,
             'Substitute for "Hinge Lift". Raise the load quickly each round'),
            (450, "Front Squat (Barbell)", 5, "5", HARD,
             "Raise the load each round"),
            (922, "Pull-Up", 5, "2-5", "steady",
             "Source scales 2 (women) / 5 (men)"),
            (638, "Dead Hang with Pack", 2, "30 count", "easy",
             'Substitute for "30-Count Dead Hang"'),
        ],
    ),
    dict(
        name="Trail Running Pre-Season Strength: Squat, Floor Press, Chin-Up",
        sport=TRAIL_RUNNING, phase="build", goal="strength", difficulty="intermediate",
        minutes=35, environment="gym", source_name=ULTRA_CREDIT, notes=None,
        movements=[
            (57, "Barbell Back Squat", 5, "6", HARD,
             "Raise the load quickly each round until 6 reps is hard but doable"),
            (313, "Dumbbell Floor Press", 5, "8", HARD,
             "Substitute for Kettlebell Floor Press. Raise the load each round"),
            (923, "Chin-Up", 5, "3-6", "steady",
             "Source scales 3 (women) / 6 (men)"),
        ],
    ),
    dict(
        name="Trail Running Pre-Season Strength: Lunge, Bench, Pull-Up",
        sport=TRAIL_RUNNING, phase="build", goal="strength", difficulty="intermediate",
        minutes=45, environment="gym", source_name=ULTRA_CREDIT, notes=None,
        movements=[
            (943, "Walking Lunge", 5, "5", HARD,
             "Raise the load quickly each round"),
            (900, "Barbell Bench Press", 5, "5", HARD,
             "Raise the load each round"),
            (922, "Pull-Up", 5, "3-5", "steady",
             "Source scales 3 (women) / 5 (men)"),
            (1170, "Dumbbell Deadlift", 3, "10", "light, steady",
             "Substitute for Dumbbell-Kettlebell Hinge Lift in the plan's 15 minute grind. "
             "Catalog difficulty is advanced and default reps 3-5; use light load"),
        ],
    ),
]

CREATED = "2026-11-12 00:00:00"


def slugify(name):
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -/&+'.":
            out.append("-")
    s = "".join(out)
    while "--" in s:
        s = s.replace("--", "-")
    return s.strip("-")


def load(n):
    return json.load((SOURCE / f"{n}.json").open())


def save(n, rows):
    with (SOURCE / f"{n}.json").open("w") as f:
        json.dump(rows, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main():
    exercises = load("exercises")
    routines = load("routines")
    routine_exercises = load("routine_exercises")
    routine_sports = load("routine_sports")

    names_by_id = {e["id"]: e["name"] for e in exercises}
    rt_keys = list(routines[0].keys())
    re_keys = list(routine_exercises[0].keys())

    existing_slugs = {r["slug"] for r in routines}
    next_rt_id = max(r["id"] for r in routines) + 1
    next_re_id = max(r["id"] for r in routine_exercises) + 1

    mismatches = []
    for spec in ROUTINES:
        for ex_id, expected, *_ in spec["movements"]:
            actual = names_by_id.get(ex_id)
            if actual != expected:
                mismatches.append((spec["name"], ex_id, expected, actual))
    if mismatches:
        print("CATALOG MISMATCH, nothing written:")
        for r, ex_id, expected, actual in mismatches:
            print(f"  [{r}] id {ex_id}: expected {expected!r}, catalog has {actual!r}")
        raise SystemExit(1)

    added = []
    for spec in ROUTINES:
        slug = slugify(spec["name"])
        if slug in existing_slugs:
            print(f"  skip (exists): {slug}")
            continue
        rid = next_rt_id
        next_rt_id += 1
        row = {k: None for k in rt_keys}
        row.update(
            id=rid, name=spec["name"], slug=slug, goal=spec["goal"],
            difficulty=spec["difficulty"], phase=spec["phase"],
            duration_minutes=spec["minutes"], frequency="1-2x/week",
            environment=spec["environment"], time_commitment=f'{spec["minutes"]} min',
            notes=spec["notes"], source_name=spec["source_name"],
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        routine_sports.append({"routine_id": rid, "sport_id": spec["sport"]})

        for pos, (ex_id, _name, sets, reps, effort, note) in enumerate(spec["movements"], start=1):
            xrow = {k: None for k in re_keys}
            xrow.update(id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                        sets=sets, reps=reps, notes=f"Effort: {effort}. Note: {note}")
            routine_exercises.append(xrow)
            next_re_id += 1
        added.append((rid, spec["name"]))

    save("routines", routines)
    save("routine_exercises", routine_exercises)
    save("routine_sports", routine_sports)

    print("Routines added:")
    for i, n in added:
        print(f"  {i}  {n}")
    if not added:
        print("  none (all slugs already exist)")


if __name__ == "__main__":
    main()
