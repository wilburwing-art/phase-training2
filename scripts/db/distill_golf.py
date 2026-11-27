#!/usr/bin/env python3
"""Distill published golf S&C programs into coach.db routines for golf-fitness and golf-senior.

Backlog 2026-11e 4.8, which replaces 3.9 (SF45 Golf is a general 45+ plan, not a golf plan).
Two sources, both under the Phase 4 source standard:

- Lephart et al. 2007, J Strength Cond Res: an 8 week off-season band, stretch and balance
  program for trained recreational golfers (Table 4).
- White 2026, University of Essex PhD thesis: Table 2.1, resistance training prescriptions for
  golfers by quality (strength, power) and training status (novice, intermediate), with example
  exercises; and the in-season strength and power priming doses of chapters 5 and 6.

Table 2.1 prints doses and example exercises, not sessions. Grouping its exercises into
sessions and choosing the phase for each session is ours, and each note says so.

Nothing in either source is age-specific. golf-senior gets the novice prescriptions and the
band program; golf-fitness gets those plus the intermediate ones. Both slugs sit outside
`SportSeasonGenerator.supports`, so a phase with no routine falls back to any phase.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

GOLF_FITNESS = 331
GOLF_SENIOR = 332
BOTH = (GOLF_FITNESS, GOLF_SENIOR)

LEPHART_2007 = ("Lephart SM, Smoliga JM, Myers JB, Sell TC, Tsai YS (Neuromuscular Research Laboratory, "
                "University of Pittsburgh). An eight-week golf-specific exercise program improves physical "
                "characteristics, swing mechanics, and golf performance in recreational golfers. "
                "J Strength Cond Res 2007;21(3):860-869, Table 4 (distilled)")
LEPHART_URL = ("https://sites.pitt.edu/~neurolab/publications/2007/"
               "LephartSM_2007_JStrengthCondRes_8wkGolfSpecificExerciseProgram.pdf")
WHITE_2026 = ("White SR. A mixed-methods evaluation of strength and conditioning training to optimise "
              "in-season golf performance. PhD thesis, School of Sport, Rehabilitation and Exercise "
              "Sciences, University of Essex 2026, Table 2.1 (distilled)")
WHITE_2026_INSEASON = ("White SR. A mixed-methods evaluation of strength and conditioning training to optimise "
                       "in-season golf performance. PhD thesis, School of Sport, Rehabilitation and Exercise "
                       "Sciences, University of Essex 2026, chapters 5 and 6 and Table 2.1 (distilled)")
WHITE_URL = "https://doi.org/10.5526/ERR-00043057"

STEADY = "steady"
HARD = "hard but controlled"
HEAVY = "heavy, 1 to 2 reps in reserve"
FAST = "fast, full intent"

ROUTINES = [
    dict(
        name="Golf: Band Swing Strength and Balance",
        phase="off_season", goal="strength", minutes=40, sports=BOTH,
        credit=LEPHART_2007, url=LEPHART_URL, environment="home",
        notes="Source: an 8 week off-season program for trained recreational golfers (mean age 47), 3 to 4 "
              "days a week at home with one elastic tube and a foam pad. Start with the 7 stretches, one "
              "30 s hold each: knees to chest, inverted V, kneeling lunge, seated hip rotation, seated torso "
              "rotation, seated torso rotation with a club behind the neck, wide-stance side bend. Then the "
              "tube work: 3 sets of 10 to 15, 2 s out and 2 s back. When 3 sets of 15 are comfortable, stand "
              "farther from the anchor. Finish with balance, 2 sets of 30 s each leg: a squat hold at 45 "
              "degrees of knee bend, single-leg stance on the floor, single-leg stance on the foam pad. The "
              "stretches and balance holds have no catalog row and stay in this note.",
        movements=[
            (1200, "Side-Lying Hip Abduction", 3, "10-15", STEADY, "Source: standing on one leg, tube at the other ankle, lift out to the side. Each leg"),
            (937, "Hip Adduction (Machine)", 3, "10-15", STEADY, "Source: standing on one leg, tube at the other ankle, pull across. Each leg"),
            (21, "Band Pull-Apart", 3, "10-15", STEADY, "Source: kneeling, one arm, pull the tube out to the side at shoulder height"),
            (350, "Cable Low-to-High Lift", 3, "10-15", STEADY, "Source: resisted backswing. Take the backswing against the tube. Each side"),
            (764, "Half-Kneeling Cable Chop (Golf)", 3, "10-15", STEADY, "Source: resisted downswing, standing in your golf posture"),
            (127, "Half-Kneeling Cable Rotation", 3, "10-15", STEADY, "Source: resisted through-swing, standing, rotate to the finish"),
            (968, "Crunch", 3, "10-15", STEADY, "Hips and knees at 90 degrees, lift the shoulder blades"),
        ],
    ),
    dict(
        name="Golf: Foundation Strength",
        phase="base", goal="strength", minutes=45, sports=BOTH,
        credit=WHITE_2026, url=WHITE_URL,
        notes="Source: the novice strength row of Table 2.1, for golfers building foundational strength and "
              "movement competency: 2 to 4 sets of 8 to 12 at 60 to 80 percent of 1RM (RPE 6 to 7, 3 to 4 "
              "reps in reserve), 1 to 2 minutes rest, 2 to 3 sessions a week. The exercises are the row's "
              "examples. The table gives no phase; this general block sits in base here.",
        movements=[
            (60, "Goblet Squat", 3, "8-12", STEADY, "RPE 6 to 7"),
            (931, "Leg Press", 3, "8-12", STEADY, "60 to 80% of 1RM"),
            (101, "Barbell Hip Thrust", 3, "8-12", STEADY, "60 to 80% of 1RM"),
            (983, "Back Extension", 3, "8-12", STEADY, ""),
            (13, "Push-Up", 3, "8-12", STEADY, "Hands on a bench if 8 is out of reach"),
            (135, "Inverted Row", 3, "8-12", STEADY, "Source: barbell inverted row"),
            (922, "Pull-Up", 3, "8-12", STEADY, "Source: assisted pull-up. Band or machine assistance"),
        ],
    ),
    dict(
        name="Golf: Foundation Power and Strength",
        phase="build", goal="power", minutes=40, sports=BOTH,
        credit=WHITE_2026, url=WHITE_URL,
        notes="Source: the novice power row of Table 2.1 (light implements only: 2 to 4 sets of 6 to 10 at "
              "RPE 5 to 6, 2 to 4 minutes rest), followed by a shortened novice strength block (2 to 4 sets "
              "of 8 to 12 at RPE 6 to 7). Putting power ahead of strength in one pre-season session is our "
              "choice; the table gives no phase. Use a 2 to 4 kg medicine ball and a low box.",
        movements=[
            (616, "Box Jump to Stick (Soft Landing)", 3, "6", FAST, "Source: box jump and box land. Low box, step down"),
            (431, "Med Ball Chest Pass (Explosive)", 3, "6-10", FAST, "Source: medicine ball chest throw. Light ball"),
            (50, "Medicine Ball Slam", 3, "6-10", FAST, "Light ball"),
            (60, "Goblet Squat", 2, "8-12", STEADY, "RPE 6 to 7"),
            (101, "Barbell Hip Thrust", 2, "8-12", STEADY, "RPE 6 to 7"),
            (13, "Push-Up", 2, "8-12", STEADY, ""),
            (135, "Inverted Row", 2, "8-12", STEADY, "Source: barbell inverted row"),
        ],
    ),
    dict(
        name="Golf: Senior In-Season Strength",
        phase="maintenance", goal="strength", minutes=30, sports=(GOLF_SENIOR,),
        credit=WHITE_2026_INSEASON, url=WHITE_URL,
        notes="Source: the novice strength and power rows of Table 2.1 at their lowest volume (2 sets), for "
              "the playing season. The thesis advises keeping heavy lifting out of the 48 hours before "
              "competition and splitting in-season volume into short, frequent sessions. The low volume and "
              "the in-season slot are our reading of that advice; the table gives no phase.",
        movements=[
            (431, "Med Ball Chest Pass (Explosive)", 2, "6", FAST, "Light ball, RPE 5 to 6"),
            (60, "Goblet Squat", 2, "8-12", STEADY, "RPE 6 to 7"),
            (101, "Barbell Hip Thrust", 2, "8-12", STEADY, "RPE 6 to 7"),
            (13, "Push-Up", 2, "8-12", STEADY, "Hands on a bench if 8 is out of reach"),
            (135, "Inverted Row", 2, "8-12", STEADY, "Source: barbell inverted row"),
            (983, "Back Extension", 2, "8-12", STEADY, ""),
        ],
    ),
    dict(
        name="Golf: Intermediate Strength",
        phase="base", goal="strength", minutes=55, sports=(GOLF_FITNESS,),
        credit=WHITE_2026, url=WHITE_URL,
        notes="Source: the intermediate strength row of Table 2.1, for golfers with a lifting base: 3 to 5 "
              "sets of 3 to 8 at 75 to 90 percent of 1RM (RPE 7 to 8, 2 to 3 reps in reserve), 2 to 3 "
              "minutes rest, 2 to 3 sessions a week, adding load as reps allow. The exercises are the row's "
              "examples. The table gives no phase; the strength block sits in base here.",
        movements=[
            (451, "Trap Bar Deadlift", 4, "3-8", HARD, "Source: hexagonal bar deadlift. 75 to 90% of 1RM"),
            (57, "Barbell Back Squat", 4, "3-8", HARD, "75 to 90% of 1RM"),
            (14, "Dumbbell Bench Press", 4, "3-8", HARD, "RPE 7 to 8"),
            (8, "Barbell Bent-Over Row", 4, "3-8", HARD, "RPE 7 to 8"),
            (15, "Dumbbell Overhead Press", 3, "3-8", HARD, "RPE 7 to 8"),
            (922, "Pull-Up", 3, "3-8", HARD, "Add load once 8 is easy"),
        ],
    ),
    dict(
        name="Golf: Intermediate Power",
        phase="build", goal="power", minutes=45, sports=(GOLF_FITNESS,),
        credit=WHITE_2026, url=WHITE_URL,
        notes="Source: the intermediate power row of Table 2.1: 3 to 5 sets of 3 to 6 at RPE 6 to 7 (3 to 4 "
              "reps in reserve), 3 to 5 minutes rest, 2 to 3 sessions a week. Strength-speed work at 50 to 70 "
              "percent of 1RM, speed-strength at 30 to 50 percent. The exercises are the row's examples; the "
              "rotational box jump (a 90 degree turn in the air) has no catalog row and is left out. The "
              "table gives no phase; the power block sits in build here, before the season.",
        movements=[
            (1034, "Jump Squat", 3, "3-6", FAST, "Source: dumbbell countermovement jump. 30 to 50% load"),
            (61, "Kettlebell Swing", 3, "3-6", FAST, ""),
            (905, "Push Press", 3, "3-6", FAST, "50 to 70% of 1RM"),
            (114, "Medicine Ball Rotational Throw", 3, "3-6", FAST, "Each side"),
            (1059, "Plyo Push-Up", 3, "3-6", FAST, "Source: ballistic press-up"),
        ],
    ),
    dict(
        name="Golf: In-Season Strength and Power",
        phase="maintenance", goal="strength", minutes=30, sports=(GOLF_FITNESS,),
        credit=WHITE_2026_INSEASON, url=WHITE_URL,
        notes="Source: the in-season priming doses tested in the thesis, run as one short session. Chapter 6: "
              "hexagonal bar deadlift 3 sets of 3 at 85 percent of 1RM (strength) and hexagonal bar jumps 3 "
              "sets of 3 at 40 percent (power), after a 5 minute dynamic warm-up. Chapter 5: 3 sets of 5 "
              "rotational medicine ball throws with a 4 kg ball. The upper body pair uses the intermediate "
              "strength row of Table 2.1 at its lowest volume (3 sets). Joining these into one session is "
              "ours. Keep it out of the 48 hours before competition unless you have tried it as a primer.",
        movements=[
            (451, "Trap Bar Deadlift", 3, "3", HEAVY, "Source: hexagonal bar deadlift, 85% of 1RM"),
            (1034, "Jump Squat", 3, "3", FAST, "Source: hexagonal bar jump, 40% of deadlift 1RM"),
            (114, "Medicine Ball Rotational Throw", 3, "5", FAST, "4 kg ball. Each side"),
            (14, "Dumbbell Bench Press", 3, "5", HARD, "RPE 7 to 8"),
            (922, "Pull-Up", 3, "5", HARD, "RPE 7 to 8"),
        ],
    ),
]

CREATED = "2026-11-27 00:00:00"


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
            id=rid, name=spec["name"], slug=slug, goal=spec["goal"],
            difficulty="beginner" if GOLF_SENIOR in spec["sports"] else "intermediate",
            phase=spec["phase"], duration_minutes=spec["minutes"], frequency="2-3x/week",
            environment=spec.get("environment", "gym"), time_commitment=f'{spec["minutes"]} min',
            notes=spec["notes"], source_name=spec["credit"], source_url=spec["url"],
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        for sport in spec["sports"]:
            routine_sports.append({"routine_id": rid, "sport_id": sport})

        for pos, (ex_id, _name, sets, reps, effort, note) in enumerate(spec["movements"], start=1):
            xrow = {k: None for k in re_keys}
            text = f"Effort: {effort}." + (f" Note: {note}" if note else "")
            xrow.update(id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                        sets=sets, reps=reps, notes=text)
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
