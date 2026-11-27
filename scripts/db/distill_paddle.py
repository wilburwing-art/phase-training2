#!/usr/bin/env python3
"""Distill paddling pre-season strength routines into coach.db.

Adds three authored `build` routines from the Mountain Tactical Institute
Kayak/Paddling Pre-Season plan (6 weeks, gym sessions only: the assessment on
sessions 1/9/17 and the two strength endurance session shapes). Each is tagged
to paddle-sports, kayaking, sup, canoeing and rafting. The plan has no in-season content, so no
`maintenance` routine is written. Water sessions are not distilled.

Catalog exercises only. Each movement is checked against the expected catalog
name, so a stale id fails the run instead of linking the wrong exercise.
Source movements with no catalog match are left out and named in the routine
notes. The source's effort cue is written into each movement's `notes` as
"Effort: ...".
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_paddle.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

PADDLE_SPORTS = [380, 381, 395, 390, 400]  # paddle-sports, kayaking, sup, canoeing, rafting

CREDIT = "MTI Kayak/Paddling Pre-Season (distilled)"

MAX90 = "sprint for the full 90 seconds, rest by putting the weight down and keep working"
PCT = "5 rounds, one every 60 seconds, at 35% of the assessment max reps (rounded up), then 1 round of max reps in 60 seconds"

ROUTINES = [
    dict(
        name="Paddling Pre-Season Assessment: Press, Row, Twist, Front Squat",
        phase="build", goal="endurance", difficulty="intermediate",
        minutes=60, environment="gym",
        notes="Source: Kayak/Paddling Pre-Season sessions 1, 9, 17, the gym assessment. Record max reps for press, row and twist: the strength endurance sessions prescribe 35% of them. "
              "Loads 20/35 lb dumbbells (women/men); 45/75 lb front squat. Warm-up is 3 rounds of 10 press, 10 renegade rows and 10 twists at 15/25 lb. "
              "Rest 3-5 minutes between the three max tests. Count a press when the dumbbell reaches the top and the other touches the chest, a row when the dumbbell reaches the shoulder joint with shoulders stacked, a twist when the dumbbell touches the floor with heels off the floor. "
              "Not included: the 400 m run after each front squat round (no catalog match), the dislocates, teacups and hip flexor, pigeon and foam roll finishers.",
        movements=[
            (14, "Dumbbell Bench Press", 1, "max in 90 sec", MAX90,
             "Alternating press, 20/35 lb"),
            (373, "Renegade Row", 1, "max in 90 sec", MAX90, "20/35 lb"),
            (970, "Russian Twist", 1, "max in 90 sec", MAX90, "Dumbbell held by the handle, feet off the floor, 20/35 lb"),
            (450, "Front Squat (Barbell)", 5, "8", "for time, 5 rounds",
             "45/75 lb. The source follows each round with a 400 m run, which is not in the catalog"),
        ],
    ),
    dict(
        name="Paddling Pre-Season Strength Endurance: Bodyweight Ladder, Press, Row, Twist",
        phase="build", goal="endurance", difficulty="intermediate",
        minutes=60, environment="gym",
        notes="Source: Kayak/Paddling Pre-Season sessions 3, 7, 11, 15, 19, 23 (strength endurance, 20/35 lb dumbbells). Reps per round come from the assessment max reps. "
              "Weeks 4 to 6 add chin-ups to the warm-up ladder (8-7-6-5-4-3-2-1). Rest 3-5 minutes after each block's max round. "
              "Not included, no catalog match: instep stretch, hip flexor and pigeon, foam roll, shoulder dislocates, Y+L, teacups, 3rd world stretch, shoulder screwcrow.",
        movements=[
            (13, "Push-Up", 1, "8-7-6-5-4-3-2-1", "steady warm-up ladder", "Warm-up, alternates with sit-up and squat each rung"),
            (969, "Sit-Up", 1, "8-7-6-5-4-3-2-1", "steady warm-up ladder", "Warm-up"),
            (1088, "Squat (Bodyweight)", 1, "8-7-6-5-4-3-2-1", "steady warm-up ladder", "Warm-up"),
            (14, "Dumbbell Bench Press", 6, "35% of max reps", PCT,
             "Alternating press, 20/35 lb. 3-5 min rest after the max round"),
            (373, "Renegade Row", 6, "35% of max reps", PCT, "20/35 lb. 3-5 min rest after the max round"),
            (970, "Russian Twist", 7, "35% of max reps", "6 rounds, one every 60 seconds, at 35% of the assessment max reps (rounded up), then 1 round of max reps in 60 seconds",
             "Dumbbell held by the handle, 20/35 lb"),
        ],
    ),
    dict(
        name="Paddling Pre-Season Strength Endurance: Goblet Squat, Press, Row, Twist",
        phase="build", goal="endurance", difficulty="intermediate",
        minutes=60, environment="gym",
        notes="Source: Kayak/Paddling Pre-Season sessions 5, 13, 21 (strength endurance, 20/35 lb dumbbells). Reps per round come from the assessment max reps. "
              "Warm-up is 4 rounds of Scotty Bobs, goblet squats and Russian triangles at 15/25 lb. Rest 3-5 minutes after each block's max round. "
              "Not included, no catalog match: Scotty Bob, Russian triangle, instep stretch, floor slide, toe touch complex, shoulder hand jobs.",
        movements=[
            (60, "Goblet Squat", 4, "8", "steady warm-up", "Warm-up, 15/25 lb"),
            (14, "Dumbbell Bench Press", 6, "35% of max reps", PCT,
             "Alternating press, 20/35 lb. 3-5 min rest after the max round"),
            (373, "Renegade Row", 6, "35% of max reps", PCT, "20/35 lb. 3-5 min rest after the max round"),
            (970, "Russian Twist", 7, "35% of max reps", "6 rounds, one every 60 seconds, at 35% of the assessment max reps (rounded up), then 1 round of max reps in 60 seconds",
             "Dumbbell held by the handle, 20/35 lb"),
        ],
    ),
]

CREATED = "2026-11-15 00:00:00"


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
            notes=spec["notes"], source_name=CREDIT,
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        routine_sports.extend({"routine_id": rid, "sport_id": sp} for sp in PADDLE_SPORTS)

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
