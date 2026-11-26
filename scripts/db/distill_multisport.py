#!/usr/bin/env python3
"""Distill triathlon and adventure race strength routines into coach.db.

Backlog 2026-11e 3.3. Sources are the Mountain Tactical Institute triathlon
plans (Sprint 380, Olympic 379, Half Ironman 376, Ironman 377) and the 6, 12
and 24-hour Adventure Race plans (245, 242, 243).

The four triathlon plans share one Thursday "Strength, Chassis Integrity" day
in a few rotating shapes, so the shapes are distilled once: three gym shapes
and the Sprint plan's bodyweight option, all `build`. Ironman weeks 13 to 17
(sessions 88, 95, 109, 116) keep the same shapes at 4 reps and 3 chassis
rounds while swim, bike and run volume peaks, and weeks 18 to 26 drop the
strength day. Those reduced-dose sessions are written as two `maintenance`
routines. The adventure race plans have one "Chassis Integrity" day of 20
minute sandbag grinds in three shapes, distilled into two `build` routines.
None of the seven plans has an off-season block, so no `base` routine is
written and multi-sport-endurance joins
`AuthoredRoutineTests.knownPhaseGapSports`.

Not distilled: the swim, bike, run, ruck, paddle and mountain bike sessions,
the assessments and the mini races, which are not gym sessions.

Tagging: triathlon routines to triathlon (501) and multi-sport-endurance
(500); adventure race routines to adventure-racing (510) and
multi-sport-endurance (500).

Catalog exercises only. Each movement is checked against the expected catalog
name, so a stale id fails the run instead of linking the wrong exercise.
Source movements with no catalog match are left out and named in the routine
notes. Source loads written "40/60#" and reps written "2/5x" are MTI's
women/men scale.
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_multisport.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

MULTISPORT = 500
TRIATHLON = 501
ADVENTURE_RACING = 510
TRI_SPORTS = [MULTISPORT, TRIATHLON]
AR_SPORTS = [MULTISPORT, ADVENTURE_RACING]

TRI_CREDIT = "MTI Sprint, Olympic, Half Ironman and Ironman Triathlon plans (distilled)"
IRONMAN_CREDIT = "MTI Ironman Triathlon Training Plan (distilled)"
AR_CREDIT = "MTI 6, 12 and 24-Hour Adventure Race Training Plans (distilled)"

HARD = "raise the load each round until the reps are hard but doable"
GRIND = "work steadily, not frantically, through the circuit"
HAND_RELEASE = "Hand-release: chest to the floor and hands lifted each rep"
STONE = ("Substitute for Sandbag Getup and Sandbag Keg Lift, 40/60 lb in the source. "
         "Alternate shoulders each round")
TRI_UNMATCHED = "Scotty Bob, standing founder, toe touch complex, instep, hip flexor and lat/pec stretches, foam rolling"

ROUTINES = [
    dict(
        name="Triathlon Strength: Front Squat, Pull-Up, Sandbag Shoulder",
        sports=TRI_SPORTS, credit=TRI_CREDIT,
        phase="build", goal="strength", difficulty="intermediate",
        minutes=50, environment="gym",
        notes="Source: Sprint and Olympic Triathlon session 4, Ironman sessions 4 and 39 (Thursday strength and chassis integrity). "
              "5 rounds of the front squat, Scotty Bob and pull-up circuit, then 4 rounds of sandbag getup, keg lift and standing founder, "
              "then 2 rounds of the toe touch complex and foam rolling. Warm-up is 3 rounds of 10 hand-release push-ups and 10 goblet squats. "
              f"Not included, no catalog match: {TRI_UNMATCHED}.",
        movements=[
            (60, "Goblet Squat", 3, "10", "warm-up", "12 kg kettlebell or 25 lb dumbbell. Warm-up circuit with the push-up"),
            (13, "Push-Up", 3, "10", "warm-up", HAND_RELEASE),
            (1159, "Dumbbell Front Squat", 5, "6", HARD, "Dumbbell or kettlebell. Circuit with the pull-up"),
            (922, "Pull-Up", 5, "2-5", "steady", "2 (women) / 5 (men) in the source"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, STONE),
        ],
    ),
    dict(
        name="Triathlon Strength: Walking Lunge, Bench Press, Chin-Up",
        sports=TRI_SPORTS, credit=TRI_CREDIT,
        phase="build", goal="strength", difficulty="intermediate",
        minutes=50, environment="gym",
        notes="Source: Sprint and Olympic Triathlon session 11, Ironman sessions 11 and 53. "
              "5 rounds of the loaded walking lunge, bench press and chin-up circuit, then 4 rounds of sandbag getup, keg lift and standing founder, "
              "then foam rolling. Warm-up is 3 rounds of 10 goblet squats at 12 kg, 10 bench press at 45/75 lb and 5 walking lunges. "
              f"Not included, no catalog match: {TRI_UNMATCHED}.",
        movements=[
            (60, "Goblet Squat", 3, "10", "warm-up", "12 kg. Warm-up circuit with a light bench press and 5 walking lunges"),
            (1164, "Kettlebell Walking Lunge", 5, "6", HARD, "6 total steps. Circuit with the bench press and chin-up"),
            (900, "Barbell Bench Press", 5, "6", HARD, "Start from the 45/75 lb warm-up load"),
            (923, "Chin-Up", 5, "3-6", "steady", "3 (women) / 6 (men) in the source"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, STONE),
        ],
    ),
    dict(
        name="Triathlon Strength: Back Squat, Floor Press, Good Morning",
        sports=TRI_SPORTS, credit=TRI_CREDIT,
        phase="build", goal="strength", difficulty="intermediate",
        minutes=50, environment="gym",
        notes="Source: Sprint Triathlon sessions 25 and 32, Olympic Triathlon sessions 18 and 39. "
              "5 rounds of back squat, kettlebell floor press and pull-up, then 4 rounds of sandbag clean and press, slasher and sandbag good morning, "
              "then foam rolling. Sprint session 32 swaps the back squat for the hinge lift (a deadlift from mid-shin) at 6 reps and the floor press to 8. "
              "Sprint session 18 and Olympic session 25 are a front squat variant of the same day: front squat, kneeling curl to press and mixed-grip pull-up. "
              "Warm-up is 3 rounds of 10 back squats at 45/75 lb and 3/5 Scotty Bobs at 25 lb. "
              f"Not included, no catalog match: slasher (12/16 kg), kneeling curl to press, {TRI_UNMATCHED}.",
        movements=[
            (57, "Barbell Back Squat", 5, "6", HARD, "Warm up with 3 rounds of 10 at 45/75 lb first"),
            (313, "Dumbbell Floor Press", 5, "6", HARD, "Kettlebell floor press in the source"),
            (922, "Pull-Up", 5, "3-6", "steady", "3 (women) / 6 (men) in the source"),
            (1036, "Kettlebell Clean", 4, "5", GRIND,
             "Substitute for Sandbag Clean & Press, 40/60 lb in the source: clean to the rack, then press overhead"),
            (921, "Barbell Good Morning", 4, "10", "light, steady",
             "Substitute for Sandbag Good Morning, 40/60 lb in the source. Use a light bar or hold a sandbag"),
        ],
    ),
    dict(
        name="Triathlon Bodyweight Strength: Mini Leg Blaster, Push-Up, Pull-Up",
        sports=TRI_SPORTS, credit=TRI_CREDIT,
        phase="build", goal="strength", difficulty="intermediate",
        minutes=45, environment="home",
        notes="Source: Sprint Triathlon sessions 4, 11, 18, 25 and 32, bodyweight option for limited gym access (do it instead of the gym day). "
              "8 to 10 rounds of a mini leg blaster, hand-release push-ups and pull-ups, then a 5 round core grind, then 2 rounds of the toe touch complex. "
              "Sessions 18 to 32 open with 2 to 4 rounds of the full leg blaster (20 squats, 20 lunges, 20 jumping lunges, 10 squat jumps) and swap the "
              "core grind to toes to sky, hip bridge, EOs and low back lunge. The mini leg blaster is done as its parts here. "
              "Not included, no catalog match: squat jumps, toes to sky, EOs, alligator push-up, standing and kneeling founder, low back lunge, "
              "toe touch complex, instep and lat/pec stretches.",
        movements=[
            (1088, "Squat (Bodyweight)", 8, "10", GRIND, "Mini leg blaster, part 1. 8 rounds in session 4, 10 in session 11"),
            (1051, "Lunge (Bodyweight)", 8, "10", GRIND, "Mini leg blaster, part 2. In place, alternate legs"),
            (130, "Split Squat Jump", 8, "10", GRIND, "Mini leg blaster, part 3: jumping lunges"),
            (13, "Push-Up", 8, "5-10", GRIND, HAND_RELEASE + ". 5 (women) / 10 (men) in the source"),
            (922, "Pull-Up", 8, "2-4", GRIND, "2 (women) / 4 (men) in the source. 4/8 inverted rows if a pull-up is not there yet"),
            (974, "Front Plank", 5, "60 sec", GRIND, "Front bridge. Core grind with the side plank"),
            (132, "Side Plank", 5, "5 raises per side", GRIND, "Side plank raises: lower the hip to the floor and lift it"),
            (1020, "Glute Bridge", 5, "10", GRIND, "Hip bridge, from session 18 on"),
        ],
    ),
    dict(
        name="Ironman Race-Phase Strength: Walking Lunge, Pull-Up, Sandbag Shoulder",
        sports=TRI_SPORTS, credit=IRONMAN_CREDIT,
        phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=40, environment="gym",
        notes="Source: Ironman Triathlon sessions 88 and 116 (weeks 13 and 17). The plan keeps one strength day while the swim, bike and run volume peaks, "
              "at 4 reps a set and 3 chassis rounds against 6 reps and 4 rounds in weeks 1 to 8, and drops the strength day from week 18. "
              "5 rounds of the walking lunge (session 116: dumbbell or kettlebell front squat), Scotty Bob and pull-up circuit, then 3 rounds of sandbag getup, "
              "keg lift and sandbag good morning (session 116: standing founder), then the toe touch complex. "
              "Warm-up is 3 rounds of 10 hand-release push-ups and 10 walking lunges. "
              f"Not included, no catalog match: {TRI_UNMATCHED}.",
        movements=[
            (13, "Push-Up", 3, "10", "warm-up", HAND_RELEASE + ". Warm-up circuit with 10 walking lunges"),
            (1164, "Kettlebell Walking Lunge", 5, "4", HARD, "4 total steps. Circuit with the pull-up"),
            (922, "Pull-Up", 5, "2-5", "steady", "2 (women) / 5 (men) in the source"),
            (786, "Sandbag Stone-to-Shoulder", 3, "5", GRIND, STONE),
            (921, "Barbell Good Morning", 3, "10", "light, steady",
             "Substitute for Sandbag Good Morning, 40/60 lb in the source. Use a light bar or hold a sandbag"),
        ],
    ),
    dict(
        name="Ironman Race-Phase Strength: Back Squat, Floor Press, Clean",
        sports=TRI_SPORTS, credit=IRONMAN_CREDIT,
        phase="maintenance", goal="strength", difficulty="intermediate",
        minutes=40, environment="gym",
        notes="Source: Ironman Triathlon sessions 95 and 109 (weeks 14 and 16), the reduced dose of the race-phase weeks: 4 reps a set and 3 chassis rounds. "
              "5 rounds of back squat, kettlebell floor press and pull-up (session 109: front squat, kneeling curl to press and mixed-grip pull-up), "
              "then 3 rounds of sandbag clean and press, slasher and sandbag good morning (session 109: sandbag cross clean and standing founder). "
              "Warm-up is 3 rounds of 10 back squats from a light load and 3/5 Scotty Bobs at 25 lb. "
              f"Not included, no catalog match: slasher (12/16 kg), kneeling curl to press, sandbag cross clean, {TRI_UNMATCHED}.",
        movements=[
            (57, "Barbell Back Squat", 5, "4", HARD, "Warm up with 3 rounds of 10 from a light load first"),
            (313, "Dumbbell Floor Press", 5, "4", HARD, "Kettlebell floor press in the source"),
            (922, "Pull-Up", 5, "3-5", "steady", "3 (women) / 5 (men) in the source"),
            (1036, "Kettlebell Clean", 3, "5", GRIND,
             "Substitute for Sandbag Clean & Press, 40/60 lb in the source: clean to the rack, then press overhead"),
            (921, "Barbell Good Morning", 3, "10", "light, steady",
             "Substitute for Sandbag Good Morning, 40/60 lb in the source. Use a light bar or hold a sandbag"),
        ],
    ),
    dict(
        name="Adventure Race Chassis Grind: Sandbag Getup, Back Extension",
        sports=AR_SPORTS, credit=AR_CREDIT,
        phase="build", goal="endurance", difficulty="intermediate",
        minutes=35, environment="home",
        notes="Source: 12 and 24-Hour Adventure Race plans, chassis integrity sessions 17, 38, 52, 59, 66 and 72 (24-hour numbering). The 6-hour plan does not use this shape. "
              "A 20 minute grind of 5 sandbag getups (40/60 lb, alternate shoulders), 5 sandbag toss and chase, 5 backwards sandbag drags and 10 face-down back extensions, "
              "again and again for the time. Then 2 rounds of hip flexor and lat/pec stretches and foam rolling. "
              "Warm-up is 4 rounds of 10 squats, 5 hand-release push-ups, 4 40-foot shuttles and an instep stretch. "
              "Not included, no catalog match: sandbag toss and chase, backwards sandbag drag, 40-foot shuttles, stretches, foam rolling. "
              "The catalog Superman hold stands in for the face-down back extension, done as reps.",
        movements=[
            (1088, "Squat (Bodyweight)", 4, "10", "warm-up", "Warm-up circuit with the push-up and 4 40-foot shuttles"),
            (13, "Push-Up", 4, "5", "warm-up", HAND_RELEASE),
            (786, "Sandbag Stone-to-Shoulder", 6, "5", GRIND,
             "Substitute for Sandbag Getup, 40/60 lb in the source. Alternate shoulders each round. Rounds are as many as fit in 20 minutes"),
            (220, "Superman Hold", 6, "10", GRIND,
             "Face-down back extension: lift chest and legs off the floor and lower, 10 reps. Last movement of each grind round"),
        ],
    ),
    dict(
        name="Adventure Race Chassis Grind: Keg Lift, Clean and Press, Back Extension",
        sports=AR_SPORTS, credit=AR_CREDIT,
        phase="build", goal="endurance", difficulty="intermediate",
        minutes=35, environment="home",
        notes="Source: 6, 12 and 24-Hour Adventure Race plans, chassis integrity sessions 3, 10, 24 and 31 (24-hour numbering). Two 20 minute grinds alternate: "
              "5 sandbag keg lifts, 5 sandbag clean and press and the 5/30/3 Sean Special (sessions 10, 31), and 5 sandbag getups, 15/15 standing founder, "
              "5 sandbag cross cleans and 10 face-down back extensions (sessions 3, 24). Sandbag at 40/60 lb. Then 2 rounds of hip flexor and lat/pec stretches and foam rolling. "
              "Warm-up is 4 rounds of 10 squats, 5 hand-release push-ups, 4 40-foot shuttles and an instep stretch. "
              "Not included, no catalog match: 5/30/3 Sean Special, standing founder, sandbag cross clean, 40-foot shuttles, stretches, foam rolling. "
              "The catalog Superman hold stands in for the face-down back extension, done as reps.",
        movements=[
            (1088, "Squat (Bodyweight)", 4, "10", "warm-up", "Warm-up circuit with the push-up and 4 40-foot shuttles"),
            (13, "Push-Up", 4, "5", "warm-up", HAND_RELEASE),
            (786, "Sandbag Stone-to-Shoulder", 6, "5", GRIND,
             "Substitute for Sandbag Keg Lift (sessions 10, 31) and Sandbag Getup (sessions 3, 24), 40/60 lb in the source"),
            (1036, "Kettlebell Clean", 6, "5", GRIND,
             "Substitute for Sandbag Clean & Press, 40/60 lb in the source: clean to the rack, then press overhead"),
            (220, "Superman Hold", 6, "10", GRIND,
             "Sessions 3 and 24 only. Face-down back extension: lift chest and legs off the floor and lower, 10 reps"),
        ],
    ),
]

CREATED = "2026-11-26 00:00:00"


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
            notes=spec["notes"], source_name=spec["credit"],
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        routine_sports.extend({"routine_id": rid, "sport_id": sp} for sp in spec["sports"])

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
