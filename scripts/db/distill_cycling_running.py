#!/usr/bin/env python3
"""Distill cycling and running pre-season strength routines into coach.db.

Adds four authored `build` routines. Cycling comes from the Mountain Tactical
Institute 30-Mile Mountain Bike Race Training Plan (Friday gym sessions, weeks
1 and 4). Running comes from the 25K Ultra Training Plan (strength sessions,
weeks 3 and 6). Cycling and running had no `build` routine.

Catalog exercises only. Each movement is checked against the expected catalog
name, so a stale id fails the run instead of linking the wrong exercise.
Source movements with no catalog match are left out and named in the routine
notes. The source's effort cue is written into each movement's `notes` as
"Effort: ...".
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_cycling_running.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

CYCLING = 1
RUNNING = 50

BIKE_CREDIT = "Mountain Tactical Institute 30-Mile Mountain Bike Race Training Plan; movement selection adapted by Phase Training (2026-11-15)"
RUN_CREDIT = "Mountain Tactical Institute 25K Ultra Training Plan; movement selection adapted by Phase Training (2026-11-15)"

HARD = "hard but doable on the last round"

BLASTER_NOTE = "Leg Blaster round, performed as its parts: 20 air squats, 20 in-place lunges, 20 jumping lunges, 10 squat jumps"

ROUTINES = [
    dict(
        name="Cycling Pre-Season Strength: Front Squat, Pull-Up, Sandbag",
        sport=CYCLING, phase="build", goal="strength", difficulty="intermediate",
        minutes=50, environment="gym", source_name=BIKE_CREDIT,
        notes="Source: 30-Mile MTB plan, week 1 and week 5 gym session. Warm-up ramp is 3 rounds of 8 front squats (start light) and 8 push-ups. "
              "Not included, no catalog match: Scotty Bob, Standing Founder, and the stretch finishers.",
        movements=[
            (450, "Front Squat (Barbell)", 5, "5", HARD,
             "Raise the load rapidly each round until 5 reps is hard but doable"),
            (922, "Pull-Up", 5, "2-5", "steady",
             "Source scales 2 (women) / 5 (men)"),
            (13, "Push-Up", 3, "8", "steady",
             "Substitute for Hand Release Push-Up, which the source uses in the warm-up rounds"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5 per side", "steady grind, no rest between movements",
             "Substitute for Sandbag Getup and Sandbag Keg Lift, 40/60 lb in the source. The source is a 4 round grind"),
        ],
    ),
    dict(
        name="Cycling Pre-Season Strength: Back Squat, Floor Press, Pull-Up",
        sport=CYCLING, phase="build", goal="strength", difficulty="intermediate",
        minutes=50, environment="gym", source_name=BIKE_CREDIT,
        notes="Source: 30-Mile MTB plan, week 4 gym session. Warm-up ramp is 3 rounds of 8 back squats (start light) and 8 push-ups. "
              "Not included, no catalog match: Sandbag Cross Clean and the stretch finishers.",
        movements=[
            (57, "Barbell Back Squat", 5, "6", HARD,
             "Raise the load rapidly each round until 6 reps is hard but doable"),
            (313, "Dumbbell Floor Press", 5, "6", HARD,
             "Substitute for Kettlebell Floor Press, each arm. Raise the load each round"),
            (922, "Pull-Up", 5, "3-6", "steady",
             "Source scales 3 (women) / 6 (men)"),
            (13, "Push-Up", 3, "8", "steady",
             "Substitute for Hand Release Push-Up, which the source uses in the warm-up rounds"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5 per side", "steady grind, no rest between movements",
             "Substitute for Sandbag Clean + Press, 40/60 lb in the source. The source is a 4 round grind"),
            (327, "Zercher Good Morning", 4, "10", "steady",
             "Substitute for Sandbag Good Mornings, 40/60 lb in the source. Use a light load"),
        ],
    ),
    dict(
        name="Running Pre-Season Strength: Leg Blaster, Thruster, Crawl",
        sport=RUNNING, phase="build", goal="strength", difficulty="intermediate",
        minutes=40, environment="home", source_name=RUN_CREDIT,
        notes="Source: 25K Ultra plan, week 3 strength day, 15 and 25 lb dumbbell pair. Source order is 3 rounds of Full Leg Blaster, then an 18 minute grind. "
              "Not included, no catalog match: Scotty Bobs, Mini Leg Blaster, Kneeling Slasher, Low Back Lunge.",
        movements=[
            (1088, "Squat (Bodyweight)", 3, "20", "steady, 30 seconds rest after each round", BLASTER_NOTE),
            (1051, "Lunge (Bodyweight)", 3, "20", "steady", BLASTER_NOTE),
            (130, "Split Squat Jump", 3, "20", "steady", "Substitute for the jumping lunges in the Leg Blaster round"),
            (230, "Squat Jump (Counter-Movement)", 3, "10", "steady", BLASTER_NOTE),
            (1098, "Thruster (Kettlebell)", 3, "5", "steady grind, 18 minutes in the source",
             "Substitute for Dumbbell Thruster, 15/25 lb. Use dumbbells"),
            (120, "Bear Crawl", 3, "5", "steady grind",
             "Substitute for Dumbbell Crawl, 15/25 lb. Hold the dumbbells if you can keep the hips level"),
        ],
    ),
    dict(
        name="Running Pre-Season Strength: Leg Blaster, Get-Up, Hinge",
        sport=RUNNING, phase="build", goal="strength", difficulty="intermediate",
        minutes=40, environment="home", source_name=RUN_CREDIT,
        notes="Source: 25K Ultra plan, week 6 strength day, 15 and 25 lb dumbbell pair. Source order is 4 rounds of Full Leg Blaster, then a 20 minute grind. "
              "Not included, no catalog match: Scotty Bobs, Dumbbell Pass Through, Kneeling Slasher to Halo.",
        movements=[
            (1088, "Squat (Bodyweight)", 4, "20", "steady, 30 seconds rest after each round", BLASTER_NOTE),
            (1051, "Lunge (Bodyweight)", 4, "20", "steady", BLASTER_NOTE),
            (130, "Split Squat Jump", 4, "20", "steady", "Substitute for the jumping lunges in the Leg Blaster round"),
            (230, "Squat Jump (Counter-Movement)", 4, "10", "steady", BLASTER_NOTE),
            (634, "Turkish Get-Up (Light Load)", 3, "3", "steady grind, 20 minutes in the source",
             "Alternate hands each round, 15/25 lb"),
            (1170, "Dumbbell Deadlift", 3, "10", "light, steady grind",
             "Substitute for Dumbbell Hinge Lift, mid-shin to full hip extension, 15/25 lb. Catalog difficulty is advanced and default reps 3-5; use light load"),
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
