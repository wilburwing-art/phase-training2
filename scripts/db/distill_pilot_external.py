#!/usr/bin/env python3
"""Distill published S&C programs for the five bucket C pilot sports into coach.db routines.

Backlog 2026-11e 4.1: boxing, fencing, dressage, dinghy-sailing and table-tennis. None of them has
an MTI plan, so each source is a journal paper, a thesis or a governing body document, cited in
`source_name` with its URL in `source_url`. Movements and doses are distilled. The notes are ours.

Phase follows `AuthoredRoutine.phaseLabels(for:)`. Where the source names no season, the phase
is chosen from what the source says the block is for, and the note says so. All five sports are
outside `SportSeasonGenerator.supports`, so a phase with no routine falls back to the sport's
routines in any phase (tier 2 of `AuthoredRoutineSelector.select`).

Sport tags are the pilot slugs only. Family roots (martial-arts, racquet-sports,
sailing-air-sports, equestrian) and siblings are left to 4.2 to 4.7 and 5.1.

Substitutes, where the catalog has no row for the movement the source names, are named in each
movement note. Doses the source does not print are not filled in: those movements stay in the
routine note and out of the movement list.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

BOXING = (272,)
FENCING = (289,)
DRESSAGE = (694,)
DINGHY = (661,)
TABLE_TENNIS = (355,)

MA_2017 = ("Ma Y, Guo Z, Wang X (School of Kinesiology, Shanghai University of Sport). "
           "J Sport Health Sci 2017;6(4):474-481, Table 2 training protocol (distilled)")
MA_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6189260/"
FINLAY_2025 = ("Finlay MJ (S&C coach and applied sport scientist, University Academy 92). "
               "Int J Strength Cond 2025;5(1), four week contrast programme (distilled)")
FINLAY_URL = "https://journal.iusca.org/index.php/Journal/article/view/426"
TURNER_2013 = ("Turner A (MSc, CSCS*D) et al. Strength and Conditioning for Fencing. "
               "Strength Cond J 2013;35(1):1-9, Table 8 (distilled)")
TURNER_URL = "https://doi.org/10.1519/SSC.0b013e31826e7283"
LEE_2015 = ("Lee JT. 8-week home-based isometric strength program for dressage riders. MA thesis, "
            "Exercise and Sport Science, UNC Chapel Hill 2015; Comp Exerc Physiol 11(4):223-230 (distilled)")
LEE_URL = "https://doi.org/10.17615/gctn-rs63"
HYTTINEN_2025 = ("Hyttinen AM, Ahtiainen JP, Hakkinen K (Neuromuscular Research Center, University of "
                 "Jyvaskyla). Comp Exerc Physiol 2025, rider strength training protocol (distilled)")
HYTTINEN_URL = "https://doi.org/10.1163/17552559-00001083"
BROWN_WS = ("Brown A (BSc Exercise and Sport Science). Introduction to S&C for Sailing, World Sailing "
            "coach education, ILCA sailor template (distilled)")
BROWN_URL = "https://media.sailing.org/sailing/wp-content/uploads/2025/10/22095632/SC.pdf"
BLACKBURN = ("Blackburn M (PhD Human Movement Studies, 2006 Laser world champion, author of Sail Fitter). Simple strength training for "
             "sailing, Sail Magazine (distilled)")
BLACKBURN_URL = "https://sailmagazine.com/?p=18587"
QU_DONG = ("Qu H et al. Front Physiol 2026;17 (high-load lower body arm) and Dong K et al. PLOS ONE "
           "2025;20(5):e0323430 (periodized core training), both in college table tennis players (distilled)")
QU_URL = "https://doi.org/10.3389/fphys.2026.1822610"
DONG_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC12080838/"

STEADY = "steady"
HARD = "hard but controlled"
HEAVY = "heavy, 1 to 2 reps in reserve"
FAST = "fast, full intent"

ROUTINES = [
    # ------------------------------------------------------------------ boxing
    dict(
        name="Boxing: Max Strength Day",
        phase="base", goal="strength", minutes=35, sports=BOXING,
        credit=MA_2017, url=MA_URL,
        notes="Source: the maximum strength day of a 3 week high-intensity block for trained amateur boxers, "
              "run twice a week. The block has no season label; it is a general strength block run away "
              "from competition, so it sits in base here. Squat and bench at 85 percent of 1RM: 6 sets of 2 "
              "in week 1, 8 sets of 2 in week 2, 8 sets of 3 in week 3. The source follows the lifts with "
              "bag rounds, pad rounds and sprints, dropped here. The study itself tested a supplement; only "
              "its training protocol is used.",
        movements=[
            (57, "Barbell Back Squat", 6, "2-3", HEAVY, "85% of 1RM. 8 sets from week 2, 3 reps in week 3"),
            (900, "Barbell Bench Press", 6, "2-3", HEAVY, "85% of 1RM. 8 sets from week 2, 3 reps in week 3"),
            (1032, "Jump Rope", 4, "2 min", HARD, "Rounds at fight pace after the lifts"),
        ],
    ),
    dict(
        name="Boxing Camp: Hinge and Press Contrast",
        phase="build", goal="power", minutes=45, sports=BOXING,
        credit=FINLAY_2025, url=FINLAY_URL,
        notes="Source: the Tuesday contrast session of a 4 week pre-tournament programme for elite amateur "
              "boxers, run twice a week (Tuesday and Thursday) alongside boxing. Every exercise is 3 sets of "
              "5. Pair each heavy lift with the fast movement after it, a few minutes apart. The source gives "
              "no load or rest; work the heavy lifts near a 5RM and rest 2 to 3 minutes between pairs. It "
              "ends with an accessory of the boxer's choice, left out here.",
        movements=[
            (49, "Box Jump", 3, "5", FAST, "Step down, stick each landing"),
            (114, "Medicine Ball Rotational Throw", 3, "5", FAST, "Source: rugby pass with a medicine ball"),
            (451, "Trap Bar Deadlift", 3, "5", HEAVY, "Heavy lift of the first pair"),
            (1034, "Jump Squat", 3, "5", FAST, "Source: hex bar jumps, light trap bar"),
            (14, "Dumbbell Bench Press", 3, "5", HEAVY, "Source adds a band for accommodating resistance"),
            (431, "Med Ball Chest Pass (Explosive)", 3, "5", FAST, "Source: supine chest pass, throw from the floor"),
            (135, "Inverted Row", 3, "5", HARD, "Source: TRX row isometric hold at the top of each rep"),
            (927, "Pendlay Row", 3, "5", HEAVY, "Bar from the floor each rep"),
        ],
    ),
    dict(
        name="Boxing Camp: Squat and Punch Contrast",
        phase="build", goal="power", minutes=45, sports=BOXING,
        credit=FINLAY_2025, url=FINLAY_URL,
        notes="Source: the Thursday contrast session of the same 4 week pre-tournament programme. Every "
              "exercise is 3 sets of 5, heavy lift then fast movement a few minutes later. Load and rest are "
              "not given; work near a 5RM on squat, weighted push-up and RDL and rest 2 to 3 minutes between "
              "pairs. The source's isometric punch hold has no catalog row and is left out.",
        movements=[
            (52, "Broad Jump", 3, "5", FAST, "Single jumps, reset each rep"),
            (329, "Lateral Bound to Stick", 3, "5", FAST, "Source: skaters. Each side"),
            (225, "Med Ball Shot Put", 3, "5", FAST, "Source: punch-specific medicine ball throw, each side"),
            (57, "Barbell Back Squat", 3, "5", HEAVY, "Heavy lift of the squat pair"),
            (230, "Squat Jump (Counter-Movement)", 3, "5", FAST, "Fast pair to the squat"),
            (13, "Push-Up", 3, "5", HEAVY, "Source: weighted push-ups, plate or vest"),
            (1059, "Plyo Push-Up", 3, "5", FAST, "Fast pair to the weighted push-up"),
            (58, "Romanian Deadlift (Barbell)", 3, "5", HEAVY, ""),
        ],
    ),
    # ------------------------------------------------------------------ fencing
    dict(
        name="Fencing: Lower and Pull Strength",
        phase="maintenance", goal="strength", minutes=40, sports=FENCING,
        credit=TURNER_2013, url=TURNER_URL,
        notes="Source: strength sessions 1 and 2 of the in-season example, joined into one session. In "
              "season the source alternates blocks of 2 to 4 strength sessions with blocks of 2 to 4 power "
              "sessions, switching with the competition calendar. Every strength lift is 4 sets of 4 at a "
              "4 to 5RM, with a slow eccentric. The source finishes strength days with technique work and "
              "medicine ball slams and throws at no stated dose.",
        movements=[
            (57, "Barbell Back Squat", 4, "4", HEAVY, "4 to 5RM, slow lowering"),
            (8, "Barbell Bent-Over Row", 4, "4", HEAVY, "4 to 5RM"),
            (62, "Bulgarian Split Squat", 4, "4", HEAVY, "Source: split squat. Rear foot may stay on the floor. Each leg, lead with both"),
            (917, "Stiff-Leg Deadlift", 4, "4", HEAVY, "4 to 5RM"),
        ],
    ),
    dict(
        name="Fencing: Press, Pull and Hinge Strength",
        phase="maintenance", goal="strength", minutes=40, sports=FENCING,
        credit=TURNER_2013, url=TURNER_URL,
        notes="Source: strength sessions 3 and 4 of the in-season example, joined into one session. Every "
              "lift is 4 sets of 4 at a 4 to 5RM. Alternate this session with Lower and Pull Strength during "
              "a strength block.",
        movements=[
            (900, "Barbell Bench Press", 4, "4", HEAVY, "4 to 5RM"),
            (1, "Weighted Pull-Up", 4, "4", HEAVY, "Load to a 4 to 5RM; bodyweight if 4 is near max"),
            (59, "Conventional Deadlift", 4, "4", HEAVY, "4 to 5RM"),
            (102, "Nordic Hamstring Curl", 4, "4", HARD, "Bodyweight, control the lowering"),
        ],
    ),
    dict(
        name="Fencing: Power Session",
        phase="maintenance", goal="power", minutes=35, sports=FENCING,
        credit=TURNER_2013, url=TURNER_URL,
        notes="Source: the power sessions of the in-season example. Every lift is 4 sets of 3 at varied "
              "loads: power clean at 60 to 80 percent of 1RM on one day and above 80 percent on the next. "
              "Alternate the lead leg on the split snatch. The source follows with single-leg and lateral "
              "box jumps, drop landings and drop jumps, then a 2-4-2 m shuttle led with the non-preferred "
              "stance, at no stated dose.",
        movements=[
            (217, "Power Clean", 4, "3", FAST, "60 to 80% of 1RM, above 80% on alternate power days"),
            (912, "Power Snatch", 4, "3", FAST, "Source: split snatch. Land in a split, alternate the lead leg"),
            (1034, "Jump Squat", 4, "3", FAST, "Light load, maximum height"),
        ],
    ),
    # ------------------------------------------------------------------ dressage
    dict(
        name="Rider Band Strength: Weeks 1 to 4",
        phase="base", goal="strength", minutes=30, sports=DRESSAGE,
        credit=LEE_2015, url=LEE_URL, environment="home",
        notes="Source: an 8 week home program for dressage riders, 3 sessions a week with a resistance "
              "band, a tennis ball and a chair, after 6 minutes of easy cardio and stretching. Every "
              "exercise is held isometrically at the working position. Weeks 1 to 4: 2 to 3 sets of 10 "
              "to 15, light to moderate band, holds rising from 20 to 30 seconds in week 1 to 45 to 50 "
              "seconds in week 4, 30 to 60 seconds rest.",
        movements=[
            (9, "Seated Cable Row", 2, "10-15", STEADY, "Source: band, sit tall without back support, squeeze the shoulder blades and hold"),
            (968, "Crunch", 2, "10-15", STEADY, "Source: band anchored low behind the head, arms overhead, curl the shoulder blades up"),
            (127, "Half-Kneeling Cable Rotation", 2, "10-15", STEADY, "Source: seated band trunk twist, band at navel height. Each side"),
            (983, "Back Extension", 2, "10-15", STEADY, "Source: seated, band at shoulder height, pull back to upright"),
            (937, "Hip Adduction (Machine)", 2, "10-15", STEADY, "Source: standing band adduction, knee straight. Each leg"),
            (551, "Rider Wall Sit with Ball Squeeze", 2, "20-50 s", STEADY, "Knees at 90 degrees, tennis ball between the knees"),
        ],
    ),
    dict(
        name="Rider Band Strength: Weeks 5 to 8",
        phase="build", goal="strength", minutes=35, sports=DRESSAGE,
        credit=LEE_2015, url=LEE_URL, environment="home",
        notes="Source: weeks 5 to 8 of the same 8 week home program, 3 sessions a week. Week 5 is 3 sets "
              "of 12 to 15 on a moderate band; weeks 6 to 8 are 4 sets of 8 to 12 on a heavy band. Holds "
              "rise from 40 seconds to 55 to 60 seconds in week 8, with 1 to 1.5 minutes rest.",
        movements=[
            (9, "Seated Cable Row", 4, "8-12", HARD, "Band, unsupported sitting, hold the squeeze"),
            (968, "Crunch", 4, "8-12", HARD, "Band anchored low behind the head"),
            (127, "Half-Kneeling Cable Rotation", 4, "8-12", HARD, "Source: seated band trunk twist. Each side"),
            (983, "Back Extension", 4, "8-12", HARD, "Source: seated band back extension"),
            (937, "Hip Adduction (Machine)", 4, "8-12", HARD, "Source: standing band adduction. Each leg"),
            (551, "Rider Wall Sit with Ball Squeeze", 4, "40-60 s", HARD, "Knees at 90 degrees, ball squeeze"),
        ],
    ),
    dict(
        name="Rider Gym Strength: Circuit and Leg Machines",
        phase="maintenance", goal="strength", minutes=45, sports=DRESSAGE,
        credit=HYTTINEN_2025, url=HYTTINEN_URL,
        notes="Source: a 12 week gym program for female show jumping and eventing riders who rode 4 to 6 "
              "times a week alongside it, 3 sessions a week, in 4 week cycles (light, moderate, hard, "
              "recovery). A bodyweight circuit comes first: 1 warm-up round, then 2 to 5 rounds of 40 "
              "seconds work and 30 seconds rest. Then the machine lifts at 2 to 6 sets of 3 to 12 at 60 to "
              "100 percent of 1RM by cycle week. The circuit's knee tuck on a ball and static sit-up have no "
              "catalog row and are left out.",
        movements=[
            (13, "Push-Up", 3, "40 s", STEADY, "Circuit, 30 s rest. 2 to 5 rounds"),
            (1020, "Glute Bridge", 3, "40 s", STEADY, "Source: pelvic tilt. Circuit"),
            (132, "Side Plank", 3, "40 s", STEADY, "Circuit, switch sides halfway"),
            (969, "Sit-Up", 3, "40 s", STEADY, "Circuit"),
            (1201, "Bird Dog", 3, "40 s", STEADY, "Source: arm and leg lift. Circuit"),
            (933, "Leg Extension", 4, "3-12", HEAVY, "60 to 100% of 1RM by cycle week, 2 to 6 sets"),
            (934, "Lying Leg Curl", 4, "3-12", HEAVY, "60 to 100% of 1RM by cycle week, 2 to 6 sets"),
            (931, "Leg Press", 4, "3-12", HEAVY, "60 to 100% of 1RM by cycle week, 2 to 6 sets"),
        ],
    ),
    # ------------------------------------------------------------------ dinghy sailing
    dict(
        name="Dinghy Sailing: Hiking Strength Template",
        phase="base", goal="strength", minutes=50, sports=DINGHY,
        credit=BROWN_WS, url=BROWN_URL,
        notes="Source: the ILCA sailor example session from World Sailing's S&C coach course. It carries no "
              "season label; its rep ranges (8 to 14) suit a general strength block, so it sits in base. "
              "Front squat and single-leg curl for hiking, pull-ups for sheeting, and trunk work for holding "
              "the hiking position. Rest 90 seconds on the lower body, 2 minutes on pull-ups, 30 seconds on "
              "the rest.",
        movements=[
            (450, "Front Squat (Barbell)", 3, "10-14", HARD, "90 s rest"),
            (934, "Lying Leg Curl", 3, "8-10", HARD, "Source: single-leg curl. Each leg, 90 s rest"),
            (922, "Pull-Up", 4, "6-8", HARD, "2 min rest"),
            (15, "Dumbbell Overhead Press", 3, "10-12", STEADY, "30 s rest"),
            (948, "Dumbbell Curl", 3, "12-14", STEADY, "Standing, 30 s rest"),
            (969, "Sit-Up", 3, "10-12", HARD, "Weighted, 30 s rest"),
            (1079, "Side Bend (Dumbbell)", 3, "10-12", STEADY, "Standing, each side, 30 s rest"),
        ],
    ),
    dict(
        name="Dinghy Sailing: Bodyweight and Bungee Circuit",
        phase="maintenance", goal="strength", minutes=30, sports=DINGHY,
        credit=BLACKBURN, url=BLACKBURN_URL, environment="home",
        notes="Source: a 20 to 30 minute circuit, 3 times a week to build a base and twice a week to hold "
              "it in the sailing season (the slot used here). 5 minutes of easy cardio first. Run each "
              "circuit twice, 12 to 15 reps a set, 30 seconds between sets. After 3 weeks go to 3 sets; "
              "after 5 weeks add resistance. The source's supine ankle touch has no dose and is left out.",
        movements=[
            (1184, "Table Inverted Row", 2, "12-15", STEADY, "Chest to the table edge, body straight"),
            (13, "Push-Up", 2, "12-15", STEADY, "From the knees until full push-ups are easy"),
            (1088, "Squat (Bodyweight)", 2, "12-15", STEADY, ""),
            (923, "Chin-Up", 2, "12-15", STEADY, "Assisted with a band or a foot on a box"),
            (9, "Seated Cable Row", 2, "12-15", STEADY, "Source: shock cord row"),
            (1086, "Squat (Band)", 2, "12-15", STEADY, "Source: shock cord resisted squat"),
            (1058, "Plank", 2, "20-30 s", STEADY, "Forearms"),
            (220, "Superman Hold", 2, "8-10", STEADY, "Source: face-down alternate arm and leg raise, hold each 2 s"),
        ],
    ),
    # ------------------------------------------------------------------ table tennis
    dict(
        name="Table Tennis: Heavy Legs and Core Stability",
        phase="base", goal="strength", minutes=45, sports=TABLE_TENNIS,
        credit=QU_DONG, url=QU_URL,
        notes="Source: two off-season studies in college table tennis players, joined into one session. "
              "Lower body from Qu et al.: squat, leg press and leg extension, 4 sets of 8 at 80 percent of "
              "1RM, 2 to 3 minutes rest, twice a week, retest 1RM every 2 weeks. Core from Dong et al. "
              "weeks 1 to 3 (core stability): a circuit of 3 sets, 30 seconds rest. Core block also at "
              f"{DONG_URL}.",
        movements=[
            (57, "Barbell Back Squat", 4, "8", HEAVY, "80% of 1RM. Pause 5 s at 90 degrees of knee bend each rep"),
            (931, "Leg Press", 4, "8", HEAVY, "80% of 1RM, knees to 90 degrees"),
            (933, "Leg Extension", 4, "8", HEAVY, "80% of 1RM, from 90 degrees"),
            (974, "Front Plank", 3, "40 s", STEADY, "Circuit, 30 s rest"),
            (132, "Side Plank", 3, "30 s", STEADY, "Each side"),
            (103, "Single-Leg Glute Bridge", 3, "12", STEADY, "Each leg"),
            (427, "Prone Y-T-W-L Complex", 3, "12", STEADY, "Source: prone Y, T and A raises"),
        ],
    ),
    dict(
        name="Table Tennis: Heavy Legs and Core Strength",
        phase="base", goal="strength", minutes=45, sports=TABLE_TENNIS,
        credit=QU_DONG, url=QU_URL,
        notes="Source: the same lower body sets from Qu et al., with Dong et al. weeks 4 to 6 (core "
              "strength): a circuit of 3 sets, 30 seconds rest. Rotate with Heavy Legs and Core Stability, "
              "moving to this one after 3 weeks. The source's windshield wipers have no catalog row and are "
              f"left out. Core block also at {DONG_URL}.",
        movements=[
            (57, "Barbell Back Squat", 4, "8", HEAVY, "80% of 1RM. Pause 5 s at 90 degrees of knee bend each rep"),
            (931, "Leg Press", 4, "8", HEAVY, "80% of 1RM"),
            (933, "Leg Extension", 4, "8", HEAVY, "80% of 1RM"),
            (13, "Push-Up", 3, "15", STEADY, "Circuit, 30 s rest"),
            (21, "Band Pull-Apart", 3, "10", STEADY, "Source: band pull-out"),
            (228, "Lateral Shuffle / Agility Line", 3, "5 each way", STEADY, "Source: side-step slide"),
            (119, "Turkish Get-Up", 3, "10", STEADY, "Light load, alternate sides"),
        ],
    ),
    dict(
        name="Table Tennis: Core Power and Footwork",
        phase="build", goal="power", minutes=30, sports=TABLE_TENNIS,
        credit=("Dong K, Tian J (Central China Normal University), Jeong G, Chun B. Periodization core "
                "training in college table tennis players. PLOS ONE 2025;20(5):e0323430 (distilled)"),
        url=DONG_URL,
        notes="Source: weeks 7 to 12 of a 12 week periodized core program, 3 sessions a week, run as a "
              "circuit: core power (weeks 7 to 9) then sport-specific core work (weeks 10 to 12), 3 sets "
              "each, 90 seconds rest. Both blocks are joined here into one pre-competition session. The "
              "source gives no loads; use a 3 to 5 kg medicine ball.",
        movements=[
            (50, "Medicine Ball Slam", 3, "8", FAST, "Weeks 7 to 9"),
            (114, "Medicine Ball Rotational Throw", 3, "8", FAST, "Source: medicine ball circles around the trunk. Weeks 7 to 9"),
            (725, "Jumping Switch Lunge (TKD Power)", 3, "8", FAST, "Source: change-leg jumps. Each side"),
            (228, "Lateral Shuffle / Agility Line", 3, "10", FAST, "Source: multi-directional slide. Each side, weeks 10 to 12"),
            (986, "Battle Ropes", 3, "10", FAST, "Source: rope pull with up and down waves. Each side"),
            (431, "Med Ball Chest Pass (Explosive)", 3, "10", FAST, "Source: medicine ball throw. Weeks 10 to 12"),
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
