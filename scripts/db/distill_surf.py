#!/usr/bin/env python3
"""Distill surf pre-season strength routines into coach.db.

Adds five authored `build` routines from the Mountain Tactical Institute Surf
Pre-Season plan V2 (5 weeks, 6 days a week). Distilled: the bodyweight
assessment (sessions 1, 15, 29), the 40% grind (8, 22), the two Thursday
bodyweight strength shapes (4, 18, 25 and 11, 32), and the no-pool option of
the Tuesday/Friday swim days. Each is tagged to surf-wave-sports, surfing,
bodyboarding, bodysurfing and skimboarding (backlog 2026-11e 3.1: the family
shares the source). The plan is pre-season only, so no `base` or
`maintenance` routine is written. Not distilled: the pool swims, the recovery
runs and the Sunday pop-up practice, which are not gym sessions.

Catalog exercises only. Each movement is checked against the expected catalog
name, so a stale id fails the run instead of linking the wrong exercise.
Source movements with no catalog match are left out and named in the routine
notes. The source's effort cue is written into each movement's `notes` as
"Effort: ...".
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_surf.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

# surf-wave-sports, surfing, bodyboarding, bodysurfing, skimboarding
SURF_SPORTS = [420, 421, 426, 427, 428]

CREDIT = "MTI Surf Pre-Season V2 (distilled)"

GRIND = "work steadily, not frantically, through the circuit"
MAX2 = "max reps in 2 minutes, rest when needed but keep working the full 2 minutes"
LOW_BACK_UNMATCHED = "standing founder, kneeling founder and low back lunge (15 s each side)"

ROUTINES = [
    dict(
        name="Surf Pre-Season Assessment: Push-Up, Lunge, Pull-Up, Sit-Up",
        phase="build", goal="endurance", difficulty="intermediate",
        minutes=45, environment="home",
        notes="Source: Surf Pre-Season V2 sessions 1, 15, 29, the bodyweight assessment. Record a 2-minute max for each of the four movements: "
              "the grind days prescribe 30% and 40% of them, rounded up. After the tests, 3 rounds of 30% of each max, then the low back circuit. "
              "Warm-up is 3 rounds of 10 hand-release push-ups, 5 in-place lunges, 10 sit-ups and 5 pop-ups. Retest in weeks 3 and 5 and compare. "
              f"Not included, no catalog match: hand-release push-up (the catalog push-up stands in), face-down back extension (the catalog Superman hold stands in, done as reps), {LOW_BACK_UNMATCHED}, instep and lat/pec stretches.",
        movements=[
            (670, "Board Pop-Up on Foam", 3, "5", "warm-up, crisp form", "Warm-up, one round with each warm-up circuit"),
            (13, "Push-Up", 4, "max in 2 min, then 3 x 30% of max", MAX2,
             "Hand-release: chest to the floor and hands lifted each rep. Drop to the knees when needed"),
            (1051, "Lunge (Bodyweight)", 4, "max in 2 min, then 3 x 30% of max", MAX2, "In place, alternate legs"),
            (922, "Pull-Up", 4, "max in 2 min, then 3 x 30% of max", MAX2, "The three 30% rounds are a grind circuit with the other three movements"),
            (969, "Sit-Up", 4, "max in 2 min, then 3 x 30% of max", MAX2, "Rest 3-5 min between the max tests"),
            (220, "Superman Hold", 2, "10", "steady, low back strength endurance",
             "Face-down back extension: lift chest and legs off the floor and lower, 10 reps. Alternates with the founder and low back lunge holds"),
        ],
    ),
    dict(
        name="Surf Pre-Season Grind: 40% Push-Up, Lunge, Pull-Up, Sit-Up",
        phase="build", goal="endurance", difficulty="intermediate",
        minutes=40, environment="home",
        notes="Source: Surf Pre-Season V2 sessions 8 and 22. Reps per round are 40% of the last assessment max, rounded up: "
              "35 push-ups at the assessment means 14 a round. 5 rounds of the circuit, then 3 rounds (week 2) or 4 rounds (week 4) of the low back circuit. "
              "Warm-up is 3 rounds of 10 hand-release push-ups, 5 in-place lunges, 10 sit-ups and 5 pop-ups. "
              f"Not included, no catalog match: hand-release push-up (the catalog push-up stands in), face-down back extension (the catalog Superman hold stands in, done as reps), {LOW_BACK_UNMATCHED}, instep and lat/pec stretches.",
        movements=[
            (670, "Board Pop-Up on Foam", 3, "5", "warm-up, crisp form", "Warm-up"),
            (13, "Push-Up", 5, "40% of max", GRIND, "Hand-release, 5 rounds as a circuit with the next three"),
            (1051, "Lunge (Bodyweight)", 5, "40% of max", GRIND, "In place, alternate legs"),
            (922, "Pull-Up", 5, "40% of max", GRIND, "Rounded up, so a 9-rep max gives 4 a round"),
            (969, "Sit-Up", 5, "40% of max", GRIND, "Last movement of each round"),
            (220, "Superman Hold", 4, "10", "steady, low back strength endurance",
             "Face-down back extension: lift chest and legs off the floor and lower, 10 reps. 3 rounds in week 2, 4 in week 4"),
        ],
    ),
    dict(
        name="Surf Pre-Season Bodyweight Strength: Chin-Up Grind, Superman, Plank",
        phase="build", goal="strength", difficulty="intermediate",
        minutes=50, environment="home",
        notes="Source: Surf Pre-Season V2 sessions 4, 18, 25 (bodyweight, core and low back strength). "
              "A 20-minute grind (25 in weeks 3 and 4) of chin-ups and pull-ups with the core work, then 5 rounds of Superman holds that grow from 30 to 60 seconds "
              "with 60 seconds rest (45 in week 4), then the low back circuit and a stretch block of hip flexor, instep, pigeon and lat/pec. "
              "Warm-up is 3 rounds of 10 hand-release push-ups, 5 in-place lunges, 10 sit-ups and 5 pop-ups. "
              "Not included, no catalog match: bodyweight Rob Shaul, toes to sky, mini leg blaster, alligator push-up, mixed-grip pull-up, the 30/5/30 Sean Special, "
              "plank walk-up, standing and kneeling founder.",
        movements=[
            (670, "Board Pop-Up on Foam", 3, "5", "warm-up, crisp form", "Warm-up"),
            (923, "Chin-Up", 6, "2-6", GRIND, "Part of the 20 to 25 minute grind. Use the low end of the range when the reps slow"),
            (922, "Pull-Up", 6, "1-2", GRIND, "Session 18 shape: pull-up, chin-up and mixed-grip pull-up each round"),
            (974, "Front Plank", 6, "30 sec", GRIND, "Elevated: feet on a bench. Last movement of each grind round"),
            (220, "Superman Hold", 5, "30-60 sec", "hold the full time, 60 seconds rest (45 in week 4)",
             "30 s in week 1, 60 s by week 3"),
        ],
    ),
    dict(
        name="Surf Pre-Season Bodyweight Strength: Lunge, Clapping Push-Up, Pull-Up Grind",
        phase="build", goal="strength", difficulty="intermediate",
        minutes=55, environment="home",
        notes="Source: Surf Pre-Season V2 sessions 11 and 32 (bodyweight, core and low back strength). "
              "A 20-minute grind (30 in week 5) of the first six movements, then 5 rounds of 45 to 60 second Superman holds with 60 seconds rest (30 in week 5), "
              "then the low back circuit and a stretch block of hip flexor, instep, pigeon and lat/pec. "
              "Warm-up is 3 rounds of 10 hand-release push-ups, 5 in-place lunges, 10 sit-ups and 5 pop-ups. "
              "Not included, no catalog match: mixed-grip pull-up (the catalog pull-up stands in), the 30/5/30 Sean Special, plank walk-up, standing and kneeling founder.",
        movements=[
            (670, "Board Pop-Up on Foam", 3, "5", "warm-up, crisp form", "Warm-up"),
            (943, "Walking Lunge", 6, "5", GRIND, "Bodyweight. First movement of each grind round"),
            (725, "Jumping Switch Lunge (TKD Power)", 6, "3", GRIND, "Jumping lunges, switch legs in the air"),
            (13, "Push-Up", 6, "5-10", GRIND, "Low end of the range when the reps slow"),
            (1059, "Plyo Push-Up", 6, "2-5", GRIND, "Clapping push-up"),
            (922, "Pull-Up", 6, "2-5", GRIND, "The source uses a mixed grip"),
            (970, "Russian Twist", 6, "10", GRIND, "Unloaded, seated"),
            (220, "Superman Hold", 5, "45-60 sec", "hold the full time, 60 seconds rest (30 in week 5)", "45 s in week 2, 60 s in week 5"),
        ],
    ),
    dict(
        name="Surf Pre-Season Conditioning (No Pool): Jump Rope, Step-Up, Superman",
        phase="build", goal="endurance", difficulty="intermediate",
        minutes=45, environment="home",
        notes="Source: Surf Pre-Season V2 Tuesday and Friday no-pool option (sessions 2, 5, 9, 12, 16, 19, 23, 26, 30, 33). The plan's first choice on these days is a swim: "
              "5 to 10 rounds of 25 m sprints, then 15 to 20 minutes of moderate swimming or a swim PT circuit of 50 m swim, squats and knees to elbows on the pool edge. "
              "Without a pool: 5 to 8 rounds of jump rope (2 minutes in week 1, rising to 6 minutes with a 10-second sprint each minute by week 5) and 20 step-ups "
              "on a 12-20 inch box (or a 200 m run), then Superman holds and the core finisher. "
              "Warm-up is 3 rounds of 2 minutes jump rope, 10 squats, 10 sit-ups and 5 pop-ups. "
              "Not included, no catalog match: the 30/5/30 Sean Special and EOs, instep and lat/pec stretches.",
        movements=[
            (1088, "Squat (Bodyweight)", 3, "10", "warm-up", "Warm-up, with 2 min jump rope, 10 sit-ups and 5 pop-ups each round"),
            (1032, "Jump Rope", 8, "2-6 min", GRIND + ", sprint the first 10 seconds of every minute from week 2",
             "8 rounds in weeks 1 and 3, 7 in week 2, 5 in weeks 4 and 5 as the rope time grows"),
            (238, "Loaded Step-Up", 8, "20", GRIND, "Bodyweight, 12-20 inch box or bench. A 200 m run (100 m out and back) can replace it"),
            (220, "Superman Hold", 5, "30-60 sec", "hold the full time, 60 seconds rest, down to 30 by week 5", "5 rounds, 6 in weeks 4 and 5"),
        ],
    ),
]

CREATED = "2026-11-25 00:00:00"


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
        routine_sports.extend({"routine_id": rid, "sport_id": sp} for sp in SURF_SPORTS)

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
