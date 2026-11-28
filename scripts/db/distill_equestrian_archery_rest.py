#!/usr/bin/env python3
"""Distill published S&C programs for the equestrian, archery and remaining sports of bucket C into coach.db routines.

Backlog 2026-11e 4.7: equestrian-trail, equestrian-endurance, equestrian-eventing, show-jumping, polo, archery,
sprinting-masters, canyoneering, slacklining, dog-agility. Sources meet the Phase 0 #4 standard as applied in 4.1 to
4.6: a named author with credentials or an affiliation, and a named venue. Each is cited in `source_name` with its URL
in `source_url`. Movements and doses are distilled. The notes are ours.

The StrengthLog and Penn State Extension rider programs are written for riders across disciplines, so under the
owner's family rule they are tagged to all five riding slugs. Hyttinen et al. 2025 studied show jumping and eventing
riders and is tagged to those two only. Dressage (4.1) is out of scope here.

No source met the standard for sprinting-masters, canyoneering or slacklining after one search pass; they move to
bucket D (see the 4.7 note in the backlog). Dog agility reaches one routine (4.14).

Phase follows `AuthoredRoutine.phaseLabels(for:)`. Where the source names no season, the phase is chosen from what
the source says the block is for, and the note says so. Sport tags are the sport slugs only; family roots and parent
mapping are left to 5.1.

Substitutes, where the catalog has no row for the movement the source names, are named in each movement note.
Doses the source does not print are not filled in: the note gives a working rule.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

STEADY = "steady"
HARD = "hard but controlled"
HEAVY = "heavy, 1 to 2 reps in reserve"
FAST = "fast, full intent"

# ------------------------------------------------------------------ equestrian
RIDING = (691, 692, 693, 695, 696)
JUMPING_EVENTING = (693, 695)

ABELSSON = ("Abelsson A (certified nutrition coach and bodybuilding specialist, four decades of training). Strength Training "
            "for Equestrians: Guide and Training Program, StrengthLog, strengthlog.com (distilled)")
ABELSSON_URL = "https://www.strengthlog.com/strength-training-for-equestrians/"

SMARSH = ("Smarsh D (Equine Extension Specialist, Associate Professor of Equine Science), Kocher A (Equine Extension "
          "Specialist, Instructor of Equine Science), McCann J (extension intern), Penn State Extension. Being a fit rider "
          "can help your horse, extension.psu.edu (distilled)")
SMARSH_URL = "https://extension.psu.edu/being-a-fit-rider-can-help-your-horse"

HYTTINEN = ("Hyttinen A-M, Ahtiainen JP, Hakkinen K (Neuromuscular Research Center, Faculty of Sport and Health Sciences, "
            "University of Jyvaskyla). Effects of strength and/or endurance training on cardiorespiratory characteristics in "
            "female horseback riders in the obstacle test track. Comparative Exercise Physiology 2025;21(1):51-61, "
            "doi 10.1163/17552559-00001083 (accepted version, distilled)")
HYTTINEN_URL = "https://jyx.jyu.fi/bitstreams/79ffe2c4-cacd-4665-a021-a5f5ceb8672e/download"

_ABEL_ALL = ("The source is written for equestrians in general and gives no discipline split, so all five riding slugs are "
             "tagged. The source gives no load and no week-by-week progression: work near a 6 to 10RM on the "
             "weighted lifts, leaving 1 to 2 reps in reserve. The source runs three sessions a week (Mon, Wed, Fri) and "
             "allows two. The phase is ours.")

# ------------------------------------------------------------------ archery
ARCHERY = (711,)

AHMAD_2024 = ("Ahmad MF, Adnan MAK, Japilus SJM, Adnan MA, Shahudin NN, Halim MHA (Faculty of Sport Science and Recreation, "
              "Universiti Teknologi MARA; Universiti Malaysia Kelantan). The Effect of 6-Week Different Resistance Training on "
              "Shooting Performance among Elite Archers. Jurnal Intelek 2024;19(1) (distilled)")
AHMAD_URL = "https://ir.uitm.edu.my/90379/2/90379.pdf"

# ------------------------------------------------------------------ dog agility
DOG_AGILITY = (753,)

WESTERFELD = ("Westerfeld J (Certified Personal Trainer and Corrective Exercise Specialist, Austin TX, 25 years of experience). "
              "Fitness Essentials for Handlers, USDAA (United States Dog Agility Association) website, 25 Feb 2025, from the "
              "Feb 2025 OVERview digital magazine (distilled)")
WESTERFELD_URL = "https://www.usdaa.com/news/fitness-essentials-for-handlers.cfm"

ROUTINES = [

    dict(
        name="Equestrian: Gym Lower Body",
        phase="base", goal="strength", minutes=35, sports=RIDING,
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Workout 1 of the source's three-day gym program for riders. " + _ABEL_ALL,
        movements=[
            (57, "Barbell Back Squat", 3, "6", HEAVY, "Source: squat, 3 x 6."),
            (1052, "Lunge (Dumbbell)", 3, "8", STEADY, "Source: dumbbell lunge, 3 x 8."),
            (108, "Single-Leg Romanian Deadlift", 3, "8", STEADY, "3 x 8, per leg."),
            (112, "Standing Calf Raise", 3, "12", STEADY, "3 x 12."),
            (1058, "Plank", 3, "30 s", STEADY, "Source: plank with leg lifts, 3 x 30 s. Lift one leg at a time while holding."),
        ],
    ),
    dict(
        name="Equestrian: Gym Upper Body",
        phase="maintenance", goal="strength", minutes=35, sports=RIDING,
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Workout 2 of the source's three-day gym program for riders. " + _ABEL_ALL,
        movements=[
            (1045, "Lat Pulldown (Cable)", 3, "10", STEADY, "3 x 10."),
            (14, "Dumbbell Bench Press", 3, "10", STEADY, "Source: dumbbell chest press, 3 x 10."),
            (9, "Seated Cable Row", 3, "10", STEADY, "3 x 10."),
            (908, "Seated Dumbbell Press", 3, "10", STEADY, "Source: dumbbell shoulder press, 3 x 10."),
            (1205, "Dead Bug", 3, "12", STEADY, "3 x 12."),
        ],
    ),
    dict(
        name="Equestrian: Gym Full Body",
        phase="build", goal="strength", minutes=35, sports=RIDING,
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Workout 3 of the source's three-day gym program for riders. " + _ABEL_ALL,
        movements=[
            (451, "Trap Bar Deadlift", 3, "5", HEAVY, "3 x 5."),
            (61, "Kettlebell Swing", 3, "12", FAST, "3 x 12."),
            (238, "Loaded Step-Up", 3, "10", STEADY, "Source: dumbbell step-up, 3 x 10, per leg."),
            (905, "Push Press", 3, "6", HARD, "3 x 6."),
            (115, "Cable Wood Chop (High-to-Low)", 3, "12", STEADY, "Source: wood chop, 3 x 12 per side."),
        ],
    ),
    dict(
        name="Equestrian: Bodyweight Lower Body",
        phase="base", goal="strength", minutes=30, sports=RIDING, environment="home",
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Workout 1 of the source's bodyweight program for riders. The source runs three sessions a week and "
              "offers the five exercises as an optional three-round circuit with minimal rest for a cardio effort. The "
              "source's side lunge maps to the catalog Lateral Lunge. All five riding slugs are tagged because the source "
              "is written for equestrians in general. The phase is ours.",
        movements=[
            (1088, "Squat (Bodyweight)", 3, "12", STEADY, "3 x 12."),
            (1051, "Lunge (Bodyweight)", 3, "10", STEADY, "3 x 10, per leg."),
            (103, "Single-Leg Glute Bridge", 3, "10", STEADY, "Source: one-legged glute bridge, 3 x 10, per leg."),
            (227, "Lateral Lunge", 3, "10", STEADY, "Source: side lunge, 3 x 10, per side."),
            (125, "Wall Sit", 3, "30 s", STEADY, "3 x 30 s."),
        ],
    ),
    dict(
        name="Equestrian: Bodyweight Upper Body",
        phase="maintenance", goal="strength", minutes=30, sports=RIDING, environment="home",
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Workout 2 of the source's bodyweight program for riders. The source offers the five exercises as an "
              "optional three-round circuit with minimal rest. The inverted row needs a low bar or sturdy table. All five "
              "riding slugs are tagged because the source is written for equestrians in general. The phase is ours.",
        movements=[
            (13, "Push-Up", 3, "10", STEADY, "3 x 10."),
            (135, "Inverted Row", 3, "8", STEADY, "3 x 8."),
            (987, "Bench Dip", 3, "8", STEADY, "3 x 8."),
            (983, "Back Extension", 3, "12", STEADY, "Source: floor back extension, 3 x 12."),
            (1058, "Plank", 3, "30 s", STEADY, "Source: plank with leg lifts, 3 x 30 s."),
        ],
    ),
    dict(
        name="Equestrian: Bodyweight Full Body Circuit",
        phase="maintenance", goal="endurance", minutes=30, sports=RIDING, environment="home",
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Workout 3 of the source's bodyweight program for riders. The source prints 3 sets for each exercise and "
              "offers three back-to-back rounds with minimal rest as the cardio option; either layout fits. The source's "
              "heel raise maps to the catalog Standing Calf Raise (bodyweight). All five riding slugs are tagged because "
              "the source is written for equestrians in general. The phase is ours.",
        movements=[
            (216, "Burpee", 3, "12", HARD, "3 x 12."),
            (1051, "Lunge (Bodyweight)", 3, "10", STEADY, "3 x 10, per leg."),
            (13, "Push-Up", 3, "10", STEADY, "3 x 10."),
            (112, "Standing Calf Raise", 3, "15", STEADY, "Source: heel raise, 3 x 15, bodyweight."),
            (132, "Side Plank", 3, "30 s", STEADY, "3 x 30 s, per side."),
        ],
    ),
    dict(
        name="Equestrian: Core and Leg Basics",
        phase="off_season", goal="accessory", minutes=25, sports=RIDING, environment="home",
        credit=SMARSH, url=SMARSH_URL,
        notes="The five rider exercises from Penn State Extension. The page says the benefits apply across hunter/jumper, "
              "endurance, trail, reining and other disciplines, so all five riding slugs are tagged. The source gives no "
              "frequency and no load: add weight only after the plain version is easy, and run it two to three times a "
              "week. The source recommends running, swimming or biking for endurance with no dose, which is left out. "
              "The phase is ours; the source names no season. About 25 minutes with rest between sets.",
        movements=[
            (1205, "Dead Bug", 3, "8-12", STEADY, "Per side. Easier option in the source: legs at 45 degrees, toe-tap the floor."),
            (1088, "Squat (Bodyweight)", 3, "8-12", STEADY, "Source: squats. Add bands or weights only after plain squats are mastered."),
            (108, "Single-Leg Romanian Deadlift", 3, "8-12", STEADY, "Source: single-leg deadlifts, per side. A hand weight is optional."),
            (1058, "Plank", 3, "30 s", STEADY, "Source: 3 holds of 30 s, straight-arm or elbow."),
            (13, "Push-Up", 3, "8-12", STEADY, "Source: walkouts to push-ups. Walk the hands out, do a push-up, walk back."),
        ],
    ),
    dict(
        name="Show Jumping and Eventing: Rider Strength Block",
        phase="build", goal="strength", minutes=45, sports=JUMPING_EVENTING,
        credit=HYTTINEN, url=HYTTINEN_URL,
        notes="Strength arm of a 12-week randomised trial in 32 female show jumping and eventing riders who also rode "
              "4 to 6 times a week; the source tags these two disciplines only, so only they are tagged. The source ran "
              "this session 3 times a week at 30 to 60 min. Part one is a body-weight circuit of 7 muscle-endurance "
              "exercises: one warm-up round at low intensity, then 2 to 5 rounds of 40 s work and 30 s rest per exercise. "
              "Part two is max-strength work (leg press, knee extension, knee flexion) at 60 to 100 percent of 1RM, "
              "3 to 12 reps, 2 to 6 sets. The source cycles four-week blocks: week 1 60 to 80 percent, week 2 80 to 90, "
              "week 3 80 to 100, week 4 recovery 70 to 75. The circuit rows below cover the source exercises the catalog "
              "has (push-up, side plank, sit-up, arm and leg lift as Bird Dog); the source's pelvic tilt, ball knee tuck and "
              "static sit-up have no catalog row and are left out. The phase is ours.",
        movements=[
            (13, "Push-Up", 3, "40 s", STEADY, "Circuit: 40 s work, 30 s rest, 2 to 5 rounds in the source."),
            (132, "Side Plank", 3, "40 s", STEADY, "Circuit, per side."),
            (969, "Sit-Up", 3, "40 s", STEADY, "Circuit."),
            (1201, "Bird Dog", 3, "40 s", STEADY, "Source: arm and leg lift. Circuit."),
            (931, "Leg Press", 4, "6", HEAVY, "Source range 60 to 100 percent of 1RM, 3 to 12 reps, 2 to 6 sets. 4 x 6 is our pick in that range."),
            (933, "Leg Extension", 4, "8", HEAVY, "Source: knee extension, same range. 4 x 8 is our pick."),
            (934, "Lying Leg Curl", 4, "8", HEAVY, "Source: knee flexion, same range. 4 x 8 is our pick."),
        ],
    ),

    dict(
        name="Archery: Strength Block (Six-Week Study Protocol)",
        phase="build",
        goal="strength",
        minutes=30,
        sports=ARCHERY,
        credit=AHMAD_2024,
        url=AHMAD_URL,
        notes=("Six-week strength group of a randomized study in 12 elite young archers, two sessions a week, three sets of "
               "every movement. Reps progress across the six weeks: 5, then 8, then 3 on the presses, 10 to 12 on the upright "
               "row, 10 to 15 on the reverse pull-up, 10 to 12 on the squat (the printed table gives paired weeks). Loads in "
               "the study were light by lifting standards (5 to 7.5 kg dumbbells, 10 to 15 kg bar, 5 to 10 kg plate), set for "
               "the archers. Our rule: pick a load that leaves 1 to 2 reps in reserve at the listed reps. The source names "
               "no season; the phase is ours. Source: weight plate squat and TRX reverse pull-up map to the nearest rows."),
        movements=[
            (14, "Dumbbell Bench Press", 3, "5-8", HEAVY,
             "Source: dumbbell bench press, 5 kg for 5 then 8 reps, 7.5 kg for 3 reps, 3 sets."),
            (15, "Dumbbell Overhead Press", 3, "5-8", HEAVY,
             "Source: dumbbell frontal press, same dose as the bench press."),
            (1155, "EZ-Bar Upright Row", 3, "10-12", HARD,
             "Source: EZ-bar upright row, 10 kg for 10 reps up to 15 kg for 12 reps, 3 sets."),
            (135, "Inverted Row", 3, "10-15", HARD,
             "Source: TRX reverse pull-up, body weight, 10 then 12 then 15 reps, 3 sets."),
            (60, "Goblet Squat", 3, "10-12", HARD,
             "Source: weight plate squat, 5 to 10 kg, 10 to 12 reps, 3 sets."),
        ],
    ),
    dict(
        name="Archery: Strength Endurance Block (Six-Week Study Protocol)",
        phase="base",
        goal="endurance",
        minutes=30,
        sports=ARCHERY,
        credit=AHMAD_2024,
        url=AHMAD_URL,
        notes=("Six-week muscular endurance group of the same randomized study in elite archers, two sessions a week, three "
               "sets of every movement with lighter loads and higher reps than the strength block. The study's endurance "
               "group improved its 36-arrow score. The source names no season; the phase is ours. Loads in the study were "
               "5 to 15 kg. Our rule: stop each set 2 to 3 reps short of failure. Source: weight plate squat and TRX reverse "
               "pull-up map to the nearest rows."),
        movements=[
            (14, "Dumbbell Bench Press", 3, "10-20", STEADY,
             "Source: dumbbell bench press, 5 kg, reps 10 then 15 then 20, 3 sets."),
            (15, "Dumbbell Overhead Press", 3, "10-20", STEADY,
             "Source: dumbbell frontal press, 5 kg, reps 10 then 15 then 20, 3 sets."),
            (1155, "EZ-Bar Upright Row", 3, "8-12", STEADY,
             "Source: EZ-bar upright row, 10 kg for 10 reps, 15 kg for 8 then 12 reps, 3 sets."),
            (135, "Inverted Row", 3, "10-15", STEADY,
             "Source: TRX reverse pull-up, body weight, 10 then 12 then 15 reps, 3 sets."),
            (60, "Goblet Squat", 3, "8-12", STEADY,
             "Source: weight plate squat, 5 kg for 10 reps, 10 kg for 8 then 12 reps, 3 sets."),
        ],
    ),

    dict(
        name="Dog Agility: Handler Core and Hip Stability",
        phase="base", goal="accessory", minutes=25, sports=DOG_AGILITY, environment="home",
        credit=WESTERFELD, url=WESTERFELD_URL,
        notes=("Source: a trainer's list of nine handler exercises for the trunk, hips and upper back, written for the human "
               "on the course. The source prints reps and holds but no set counts and no loads, so 2 sets per movement is our "
               "working rule, which is what makes the 25 minute total, and body weight, a light band or light dumbbells are "
               "enough. Doses from the source: side plank up to 10 reps per side (knees first, feet against a wall later); "
               "glute bridge holds of 5 to 10 seconds, up to 10 reps; adductor squeeze with a medium ball, 5 to 10 second "
               "squeezes, 5 to 10 reps; rows with weights or bands, 10 to 15 reps; push-ups on a wall, bench or floor, "
               "10 to 15 reps to fatigue with a straight line from head to heels; cobra holds start at a few seconds and "
               "build to 15 seconds, 5 to 6 repeats (Source: cobra pose, mapped to Superman Hold); standing glute medius "
               "abduction with small pulsing lifts, 30 to 60 seconds per side (Source: standing pulses, mapped to "
               "Side-Lying Hip Abduction, so 2 sets of 30 to 60 seconds per side). Left out: the transverse abdominis "
               "draw-in and the lying deep neck flexor chin tuck, which have no catalog row. The source names no season; "
               "base is ours. The source asks for physician or rehab clearance before starting and to stop on pain."),
        movements=[
            (132, "Side Plank", 2, "up to 10 per side", STEADY,
             "Source: side plank, up to 10 reps per side. Knees on the floor first, then feet against a wall."),
            (1020, "Glute Bridge", 2, "up to 10, 5 to 10 second holds", STEADY,
             "Source: glute bridge, hold 5 to 10 seconds, lower partway between reps."),
            (220, "Superman Hold", 2, "5 to 6 holds of up to 15 seconds", STEADY,
             "Source: cobra pose for the deep back muscles. Start with holds of a few seconds, build to 15."),
            (1200, "Side-Lying Hip Abduction", 2, "30 to 60 seconds per side", STEADY,
             "Source: standing glute medius abduction with small pulsing lifts, 30 to 60 seconds per side."),
            (550, "Adductor Ball Squeeze (Supine)", 2, "5 to 10, 5 to 10 second squeezes", STEADY,
             "Source: hip adductor squeeze with a medium ball, release slightly between reps."),
            (10, "Dumbbell Single-Arm Row", 2, "10 to 15 per side", STEADY,
             "Source: rows with weights or bands, 10 to 15 reps. The source gives no load: use a weight that makes rep 15 hard."),
            (13, "Push-Up", 2, "10 to 15, to fatigue", STEADY,
             "Source: push-ups on wall, table or floor, 10 to 15 reps to fatigue, straight line head to heels."),
        ],
    ),
]

CREATED = "2026-11-28 00:00:00"


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
            difficulty="intermediate", phase=spec["phase"],
            duration_minutes=spec["minutes"], frequency="2-3x/week",
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
