#!/usr/bin/env python3
"""Distill the MTI In-Season Strength Training For Endurance Athletes plan into coach.db.

Adds three authored `maintenance` routines, one per lower-body session shape of
the 12-session plan (box squat, front squat, walking lunge). Each is tagged to
paddle-sports, kayaking, sup, cycling and running. A session is a heavy lower
lift, a press/pull superset, a timed 20-minute chassis "grind" and a durability
finisher. Stretch and foam-roll items are left out.

Catalog exercises only. No MTI signature movement is added to the catalog: each
one is replaced by its closest catalog movement or dropped, and the routine
notes name every substitution and drop. Each movement is checked against the
expected catalog name, so a stale id fails the run. The source's effort cue is
written into each movement's `notes` as "Effort: ...".
The source gives the grind as 20 minutes with reps per round and no round
count. Each routine writes 8 rounds (about 2.5 minutes a round, an estimate)
and the note says to stop at 20:00 either way.
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_inseason_endurance.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

SPORTS = [380, 381, 395, 1, 50]  # paddle-sports, kayaking, sup, cycling, running

CREDIT = "MTI In-Season Strength for Endurance Athletes V3 (distilled)"

HEAVY = "increase load rapidly each round until the reps are hard but doable"
GRIND = "steady, not frantic; keep moving for the full 20 minutes, no rest"
GRIND_NOTE = ("Source: 20 minute grind, rounds not stated. Written as 8 rounds (about 2.5 min each, an estimate); "
              "stop at 20:00 whether or not the rounds are done.")
SHARED = ("Plan gives 12 weeks, 2 sessions a week at most, supplementing the sport training, not replacing it. "
          "Not included: instep, lat and pec, hip flexor and pigeon stretches, shoulder dislocates, foam roll.")

ROUTINES = [
    dict(
        name="In-Season Endurance Strength: Box Squat, Bench Press, Pull-Up",
        phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=55, environment="gym",
        notes=f"Source: In-Season Strength for Endurance Athletes sessions 1, 7, 13, 19. Loads: warm-up box squat 65/75 lb (women/men), sandbag 40/60 lb, plate 25 lb. {SHARED} "
              "Sessions 7, 13, 19 raise the finisher from 10 to 15 and 20 reps over 3 rounds. "
              "Substitutions: Kneeling Plate Halfmoon becomes Half-Kneeling Landmine Rotation; Keg Lift becomes Sandbag Stone-to-Shoulder; "
              "Hamstring Hell becomes Nordic Hamstring Curl. Dropped: Standing Founder (15/15), no catalog match. "
              + GRIND_NOTE,
        movements=[
            (13, "Push-Up", 3, "6", "warm-up", "Hand release push-ups, alternating with the warm-up box squats"),
            (920, "Box Squat", 6, "4", HEAVY, "Heavy, low volume lower lift. Warm-up first: 3 rounds of 6 box squats at 65/75 lb, alternating with the push-ups"),
            (900, "Barbell Bench Press", 6, "5", HEAVY, "Superset with the pull-up", 1),
            (922, "Pull-Up", 6, "2-5", "steady", "Superset with the bench press. 2 reps in week 1, 5 reps by week 4", 1),
            (381, "Half-Kneeling Landmine Rotation", 8, "5", GRIND, "Grind. Source: Kneeling Plate Halfmoon, 25 lb"),
            (786, "Sandbag Stone-to-Shoulder", 8, "5", GRIND, "Grind. Source: Keg Lift, 40/60 lb sandbag"),
            (102, "Nordic Hamstring Curl", 2, "10", "steady", "Durability finisher. Source: Hamstring Hell"),
        ],
    ),
    dict(
        name="In-Season Endurance Strength: Front Squat, Push-Up, Horizontal Pull",
        phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=55, environment="gym",
        notes=f"Source: In-Season Strength for Endurance Athletes sessions 3, 9, 15, 21. Loads: warm-up front squat 45/65 lb (women/men), dumbbell crawl 25 lb. {SHARED} "
              "Finisher reps rise from 10 to 15 and 20 over the 12 weeks. "
              "Substitutions: Horizontal Pull Up becomes Inverted Row; Dumbbell Crawl becomes Bear Crawl, load 25 lb dumbbell as written; "
              "Low Back Lunge becomes Walking Lunge; Poor Man's Leg Curl becomes Lying Leg Curl. "
              "Dropped: Scotty Bob (4x warm-up), Sandbag Toss & Chase (5x), no catalog match. "
              + GRIND_NOTE,
        movements=[
            (450, "Front Squat (Barbell)", 6, "4", HEAVY, "Heavy, low volume lower lift. Warm-up first: 3 rounds of 8 front squats at 45/65 lb (the source pairs them with 4 Scotty Bobs, dropped)"),
            (13, "Push-Up", 6, "8-10", "steady", "Superset with the row. Hand release push-ups", 1),
            (135, "Inverted Row", 6, "8-10", "steady", "Superset with the push-up. Source: Horizontal Pull Up", 1),
            (120, "Bear Crawl", 8, "10", GRIND, "Grind. Source: Dumbbell Crawl, 25 lb"),
            (943, "Walking Lunge", 8, "15 per side", GRIND, "Grind. Source: Low Back Lunge, 15/15"),
            (934, "Lying Leg Curl", 3, "10", "steady", "Durability finisher. Source: Poor Man's Leg Curl"),
        ],
    ),
    dict(
        name="In-Season Endurance Strength: Walking Lunge, Push Press, Single-Arm Row",
        phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=55, environment="gym",
        notes=f"Source: In-Season Strength for Endurance Athletes sessions 2, 8, 14, 20. Loads: sandbag 40/60 lb. {SHARED} "
              "Sessions 14 and 20 lengthen the finisher from 15 to 20 seconds. "
              "Substitutions: Sandbag Get Up becomes Sandbag Stone-to-Shoulder, alternating shoulders each round; Jane Fonda becomes Side-Lying Hip Abduction. "
              "Dropped: Slasher (10x, 12/16 kg) and Kneeling Founder (15/15), no catalog match, so the grind is one movement. "
              + GRIND_NOTE,
        movements=[
            (13, "Push-Up", 3, "8", "warm-up", "Hand release push-ups, alternating with the warm-up walking lunges"),
            (943, "Walking Lunge", 6, "4", HEAVY, "Heavy, low volume lower lift. Warm-up first: 3 rounds of 8 walking lunges"),
            (905, "Push Press", 6, "3", "increase load each round until 5 reps would be hard but doable", "Superset with the row", 1),
            (10, "Dumbbell Single-Arm Row", 6, "6", "increase load each round until 5 reps would be hard but doable", "Superset with the push press", 1),
            (786, "Sandbag Stone-to-Shoulder", 8, "5", GRIND, "Grind. Source: Sandbag Get Up, 40/60 lb, alternate shoulders each round"),
            (1200, "Side-Lying Hip Abduction", 2, "15 sec", "steady", "Durability finisher, glute medius. Source: Jane Fonda"),
        ],
    ),
]

CREATED = "2026-11-16 00:00:00"


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
        routine_sports.extend({"routine_id": rid, "sport_id": sp} for sp in SPORTS)

        for pos, (ex_id, _name, sets, reps, effort, note, *group) in enumerate(spec["movements"], start=1):
            xrow = {k: None for k in re_keys}
            xrow.update(id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                        sets=sets, reps=reps, superset_group=group[0] if group else None,
                        notes=f"Effort: {effort}. Note: {note}")
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
