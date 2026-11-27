#!/usr/bin/env python3
"""Distill the land sessions of the MTI USCG Rescue Swimmer plan into coach.db routines.

Backlog 2026-11e 3.13, which replaces 3.2 (Swimming Improvement, plan 184, is pool-only). The
source is USCG Rescue Swimmer Plan V2 (64, 42 sessions), a selection prep plan for the Coast
Guard Aviation Survival Technician (AST) school.

Phase follows `AuthoredRoutine.phaseLabels(for:)`: the plan builds toward a test date, so every
routine is `build`, which serves preSeason and eventPrep.

Sport tags: swimming (450), lap-swimming (451) and open-water-swimming (457). swim-butterfly
comes through its parent lap-swimming.

The plan prepares a candidate for a selection test. These routines are for a recreational
swimmer's pre-season, so the volumes are cut (fewer rounds, lower rep totals) and each note says
what the source prescribes.

Not distilled:
- Every run: the 400 m warm-up lap, the 1.5 mile test run, the 3 to 5 mile moderate runs, the
  800 m intervals and the runs between calisthenics blocks.
- Every pool session (3, 7, 9, 13, 15, 21, 25, 27, 31, 33, 39), the 450 m timed swim, the 25
  yard underwater swims, the 200 yard buddy tow and the swim legs of the swim, run and
  calisthenics stamina sessions (12, 24, 36). Poolside pull-outs are left out with the pool work.
- Rest and recovery sessions (11, 17, 23, 29, 35, 38, 40 to 42), the foam roll complex, the
  instep, lat and pec stretches, the pigeon stretch and shoulder dislocates.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

SWIM = (450, 451, 457)
CREDIT = "MTI USCG Rescue Swimmer Plan V2 (distilled)"

STEADY = "steady"
HARD = "hard but controlled"
MAX = "max reps, stop at the first rep that breaks form"
BW = "bodyweight"

ROUTINES = [
    dict(
        name="Rescue Swimmer: Push-Up, Sit-Up and Pull-Up Test",
        phase="build", credit=CREDIT, sports=SWIM, minutes=30,
        notes="Source: USCG Rescue Swimmer AST assessment, sessions 1, 19 and 37 (week 1, then retests in weeks 4 and 7). "
              "Warm up with 3 rounds of in-line lunges, pull-ups and push-ups. Then test in order with 2 minutes of rest "
              "between: max push-ups in 2 minutes, max sit-ups in 2 minutes, max pull-ups, max chin-ups. Record each score; "
              "the Calisthenics routine works from them. The source follows the strength tests with a 1.5 mile run, a 500 "
              "yard timed swim, underwater swims and a buddy tow, all dropped here. Run it at the start of pre-season and "
              "every 3 to 4 weeks.",
        movements=[
            (1051, "Lunge (Bodyweight)", 3, "5", STEADY, "Warm-up rounds with pull-ups and push-ups, in-line stance"),
            (13, "Push-Up", 1, "max in 2 min", MAX, "Continuous, record the count. Rest 2 minutes after"),
            (969, "Sit-Up", 1, "max in 2 min", MAX, "Record the count. Rest 2 minutes after"),
            (922, "Pull-Up", 1, "max", MAX, "Continuous from a dead hang, record the count. Rest 2 minutes after"),
            (923, "Chin-Up", 1, "max", MAX, "Continuous, record the count"),
        ],
    ),
    dict(
        name="Rescue Swimmer: Percentage Calisthenics Intervals",
        phase="build", credit=CREDIT, sports=SWIM, minutes=30,
        notes="Source: USCG Rescue Swimmer Calisthenics / Run sessions 2, 4, 8, 10, 14, 16, 20, 22, 26, 28, 32 and 34. "
              "Every 75 seconds, do 30 to 35 percent of your test score for one movement, and work through push-ups, "
              "pull-ups, sit-ups and chin-ups in turn. The source runs 6 rounds of each movement and rises from 30 to 35 "
              "percent of the latest test across each block, then follows with a 3 to 5 mile run or 800 m intervals. Cut "
              "to 4 rounds here for a recreational swimmer, with the run dropped. Add a fifth and sixth round as the work "
              "gets easy.",
        movements=[
            (1051, "Lunge (Bodyweight)", 3, "5", STEADY, "Warm-up rounds with pull-ups, push-ups and sit-ups"),
            (13, "Push-Up", 4, "30-35% of test max", HARD, "Start a set every 75 seconds"),
            (922, "Pull-Up", 4, "30-35% of test max", HARD, "Start a set every 75 seconds"),
            (969, "Sit-Up", 4, "30-35% of test max", HARD, "Start a set every 75 seconds"),
            (923, "Chin-Up", 4, "30-35% of test max", HARD, "Start a set every 75 seconds"),
        ],
    ),
    dict(
        name="Rescue Swimmer: Push-Up, Squat and Pull-Up Rounds",
        phase="build", credit=CREDIT, sports=SWIM, minutes=40,
        notes="Source: USCG Rescue Swimmer mini event and stamina sessions 6 and 30. The source alternates runs of 2 to "
              "0.5 miles with rounds of 75 push-ups, 50 air squats and 25 pull-ups, from 3 rounds in session 6 to 10 "
              "rounds in session 30. Cut here to 3 rounds of 25 push-ups, 20 squats and 8 pull-ups with the runs dropped. "
              "Break each set into as many pieces as you need and keep moving. Add a round every 2 weeks.",
        movements=[
            (1051, "Lunge (Bodyweight)", 3, "5", STEADY, "Warm-up rounds with pull-ups and push-ups"),
            (13, "Push-Up", 3, "25", STEADY, "Partition as needed, source prescribes 75 per round"),
            (1088, "Squat (Bodyweight)", 3, "20", STEADY, "Air squats, source prescribes 50 per round"),
            (922, "Pull-Up", 3, "8", HARD, "Partition as needed, source prescribes 25 per round"),
        ],
    ),
    dict(
        name="Rescue Swimmer: Step-Up and Calisthenics Stamina",
        phase="build", credit=CREDIT, sports=SWIM, minutes=45,
        notes="Source: USCG Rescue Swimmer stamina session 18. The source opens with a 30 minute AMRAP of a half mile "
              "run and 50 step-ups on a 16 to 18 inch box, then 6 rounds each of 30 seconds of push-ups, jump lunges "
              "and burpees with 30 seconds of rest, 3 rounds of front and side bridges, and a 2 mile run. Cut here to 3 "
              "rounds of 20 step-ups and 4 rounds of each 30 second block, with the runs dropped. Rest 2 minutes "
              "between blocks.",
        movements=[
            (238, "Loaded Step-Up", 3, "20 total", STEADY, "Bodyweight or a light pack, 16 to 18 inch box, count total steps not per leg"),
            (13, "Push-Up", 4, "30 sec", HARD, "30 seconds on, 30 seconds rest"),
            (130, "Split Squat Jump", 4, "30 sec", HARD, "Jump lunges in the source; step back to walking lunges if landings get sloppy"),
            (216, "Burpee", 4, "30 sec", HARD, "30 seconds on, 30 seconds rest"),
            (1058, "Plank", 3, "30 sec", STEADY, "Front bridge"),
            (132, "Side Plank", 3, "30 sec each side", STEADY, "Side bridge left then right, 30 seconds rest after"),
        ],
    ),
]
CREATED = "2026-11-26 00:00:00"


def slugify(name):
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -/&+'.:,":
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
            id=rid, name=spec["name"], slug=slug, goal="strength",
            difficulty="intermediate", phase=spec["phase"],
            duration_minutes=spec["minutes"], frequency="1-2x/week",
            environment="gym", time_commitment=f'{spec["minutes"]} min',
            notes=spec["notes"], source_name=spec["credit"],
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        for sport in spec["sports"]:
            routine_sports.append({"routine_id": rid, "sport_id": sport})

        for pos, (ex_id, _name, sets, reps, effort, note) in enumerate(spec["movements"], start=1):
            xrow = {k: None for k in re_keys}
            xrow.update(id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                        sets=sets, reps=reps, notes=f"Effort: {effort}. Note: {note}")
            routine_exercises.append(xrow)
            next_re_id += 1
        added.append((rid, spec["phase"], spec["name"]))

    save("routines", routines)
    save("routine_exercises", routine_exercises)
    save("routine_sports", routine_sports)

    print("Routines added:")
    for i, ph, n in added:
        print(f"  {i}  {ph:12s} {n}")
    if not added:
        print("  none (all slugs already exist)")


if __name__ == "__main__":
    main()
