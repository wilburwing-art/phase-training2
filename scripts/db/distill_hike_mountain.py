#!/usr/bin/env python3
"""Distill hiking and mountaineering child-sport strength routines into coach.db.

Backlog 2026-11e 3.4. Sources are ten Mountain Tactical Institute plans: Half
Dome Day Hike (222), Mountaineering & Hiking Prep (215), Backpack Pre-Season V2
(210), Grand Canyon Rim to Rim to Rim (211), Kilimanjaro (214), Rainier (228),
Teton Grand Traverse (223), Denali (226), Big Mountain V3 (225) and Peak Bagger
V5 (216).

Every plan is a pre-season build toward one objective, so every routine here is
`build`. All ten share one spine: a leg blaster progression (rounds of the mini
leg blaster give way to rounds of the full one over the weeks), a core or low
back grind, sandbag getups and rapid calf raise intervals. The shapes repeat
across plans, so each distinct shape is distilled once and tagged to every
child sport whose plan uses it:

- day-hiking (481): Half Dome core day and low back day.
- backpacking (482), international-trekking (485): the Backpack Pre-Season V2
  strength days. The Kilimanjaro plan repeats them session for session in a
  five-week block, so one set of three routines serves both. Kilimanjaro is
  also a source for non-tech-mountaineering (151) in the 11e tracker, so the
  same three are tagged there.
- fastpacking (484): Rim to Rim to Rim eccentric leg days, early and late.
- non-tech-mountaineering (151): Rainier leg and low back day, Rainier chassis
  and upper body day.
- technical-mountaineering (155): the Teton strength day. Teton's other
  strength day is a bouldering V-sum test with founders, which has no catalog
  match, so the Rainier routines are tagged here too (same glacier fitness).
- expedition-mountaineering (159): the Denali Tuesday and Thursday PM strength
  work, which is the Teton strength day at different reps (one routine), plus
  the Rainier routines: the Denali Friday chassis day is sandbag getups and a
  founder and slasher grind, and the Rainier chassis day is the same getup
  count with a pull-up and push-up circuit that the catalog covers.
- scrambling (164): Peak Bagger good morning day and getup and pull-up day,
  plus the Half Dome low back day, which Peak Bagger repeats word for word.

Not distilled: step-up, rucking, uphill, tire drag and running sessions, the
bouldering V-sum test, assessments, and the Big Mountain chassis grinds (15 to
22 minutes, under the 25 minute session floor). Mountaineering & Hiking Prep
(215) is already distilled as routines 311 and 314 (maintenance); its build
days are a push-up, lunge and pull-up percentage grind that the Half Dome and
Peak Bagger routines cover, so nothing new is written from it.

Catalog exercises only. Each movement is checked against the expected catalog
name, so a stale id fails the run instead of linking the wrong exercise.
Source movements with no catalog match are left out and named in the routine
notes. Source loads written "40/60#" and reps written "3/5x" are MTI's
women/men scale.
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_hike_mountain.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

NON_TECH = 151
TECHNICAL = 155
EXPEDITION = 159
SCRAMBLING = 164
DAY_HIKING = 481
BACKPACKING = 482
FASTPACKING = 484
TREKKING = 485

HALF_DOME = "MTI Half Dome Day Hike Training Plan (distilled)"
LOW_BACK_CREDIT = "MTI Half Dome Day Hike Training Plan and Peak Bagger V5 (distilled)"
BACKPACK = "MTI Backpack Pre-Season V2 and Kilimanjaro Training Plan (distilled)"
R2R2R = "MTI Grand Canyon Rim to Rim to Rim Training Plan (distilled)"
RAINIER = "MTI Rainier Training Plan (distilled)"
TETON_DENALI = "MTI Teton Grand Traverse and Denali Training Plans (distilled)"
PEAK_BAGGER = "MTI Peak Bagger V5 (distilled)"

GRIND = "work steadily, not frantically, through the circuit"
STEADY = "steady"
HAND_RELEASE = "Hand-release: chest to the floor and hands lifted each rep"
MINI = "Mini leg blaster round, done as its parts: 10 squats, 10 in-place lunges, 10 jumping lunges, 5 squat jumps"
FULL = "Full leg blaster round, done as its parts: 20 squats, 20 in-place lunges, 20 jumping lunges, 10 squat jumps"
CALVES = ("Rapid calf raise interval: 20 seconds fast, 10 second hold at the top, 20 seconds fast, 10 second hold, "
          "30 seconds rest. Rounds rise across the plan")
GETUP = ("Substitute for Sandbag Getup, 40/60 lb in the source: lie down with the bag on one shoulder, stand up, "
         "alternate shoulders each rep")
GOOD_MORNING = "Substitute for Sandbag Good Morning, 40/60 lb in the source. Use a light bar or hold a sandbag"
BACK_EXT = "Face-down back extension: lift chest and legs off the floor and lower, 10 reps"


def blaster(sets_mini, sets_full):
    """The leg blaster as its catalog parts, one row per part. Sets count mini
    and full rounds together; reps span both sizes when the routine mixes them."""
    rounds = sets_mini + sets_full
    if sets_mini == 0:
        big, small = "20", "10"
    elif sets_full == 0:
        big, small = "10", "5"
    else:
        big, small = "10-20", "5-10"
    return [
        (1088, "Squat (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 1"),
        (1051, "Lunge (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 2. In place, alternate legs, each step is a rep"),
        (130, "Split Squat Jump", rounds, big, STEADY, "Leg blaster, part 3: jumping lunges"),
        (1034, "Jump Squat", rounds, small, STEADY, "Leg blaster, part 4. Rest 30 seconds after each round"),
    ]


ROUTINES = [
    dict(
        name="Day Hike Leg Strength: Leg Blaster, Core, Calf Intervals",
        sports=[DAY_HIKING], credit=HALF_DOME,
        minutes=40, environment="home", goal="endurance",
        notes="Source: Half Dome Day Hike sessions 2, 8, 14, 20, 26, 32 and 38 (Tuesday AM, a run follows in the PM). "
              "Week 1 is 10 rounds of the mini leg blaster; from week 2 the full leg blaster takes over (2 rounds plus 6 mini, "
              "rising to 6 full rounds by week 6). Then 3 to 4 rounds of the 30/5/30 Sean Special, 20 sit-ups and 10 EOs "
              "(weeks 6 and 7 swap the sit-ups for 10 seated Russian twists at 15/25 lb), then 3 to 8 rounds of calf raise intervals. "
              f"Leg blaster rows: {MINI}. {FULL}. Warm-up is 3 rounds of 10 squats, 8 hand-release push-ups and 5 walking lunges. "
              "Not included, no catalog match: 30/5/30 Sean Special, EOs, instep stretch. Not distilled: the PM run.",
        movements=blaster(6, 2) + [
            (969, "Sit-Up", 4, "20", STEADY, "Core circuit with the Sean Special and EOs. Weeks 6 and 7 use the Russian twist instead"),
            (970, "Russian Twist", 4, "10", STEADY, "Seated, 15/25 lb dumbbell. Weeks 6 and 7 only, in place of the sit-ups"),
            (636, "Calf Raise Endurance (Bilateral High-Rep)", 5, "20 sec on, 10 sec hold, twice", STEADY, CALVES),
        ],
    ),
    dict(
        name="Hike and Scramble Leg Strength: Leg Blaster, Low Back, Calf Intervals",
        sports=[DAY_HIKING, SCRAMBLING], credit=LOW_BACK_CREDIT,
        minutes=40, environment="home", goal="endurance",
        notes="Source: Half Dome Day Hike sessions 5, 11, 17, 23, 29 and 35 (Friday), and Peak Bagger V5's Friday sessions, "
              "which are the same day with 7 full leg blaster rounds at the peak. "
              "Leg blaster rounds progress as on the Tuesday day: 10 mini, then 2 full and 6 mini, up to 5 to 7 full. "
              "Then 3 to 4 rounds of 15/15 standing founder, 15/15 kneeling founder, 10 face-down back extensions and "
              "10 one-leg poor man's leg curls, then 3 to 8 rounds of calf raise intervals and foam rolling for legs and low back. "
              f"Leg blaster rows: {MINI}. {FULL}. Warm-up is 3 rounds of 10 squats, 8 hand-release push-ups and 5 walking lunges. "
              "Not included, no catalog match: standing and kneeling founder, one-leg poor man's leg curl (a sliding hamstring curl "
              "on the floor), foam rolling. The catalog Superman hold stands in for the face-down back extension, done as reps.",
        movements=blaster(6, 2) + [
            (220, "Superman Hold", 4, "10", STEADY, BACK_EXT),
            (636, "Calf Raise Endurance (Bilateral High-Rep)", 5, "20 sec on, 10 sec hold, twice", STEADY, CALVES),
        ],
    ),
    dict(
        name="Backpacking Strength: Leg Blaster, Sandbag Getup, Russian Twist",
        sports=[BACKPACKING, TREKKING, NON_TECH], credit=BACKPACK,
        minutes=45, environment="home", goal="strength",
        notes="Source: Backpack Pre-Season V2 sessions 2, 8 and 14, and Kilimanjaro sessions 2, 8 and 14 (the same days). "
              "8 to 10 rounds of the mini leg blaster (session 14: 2 full and 6 mini), then 4 rounds of 3 to 4 Scotty Bobs at 15/25 lb, "
              "5 to 6 sandbag getups, 10 seated Russian twists at 15/25 lb and 5 backwards sandbag drags, then from session 14 "
              "5 rounds of calf raise intervals. A 30 to 40 minute run follows in the PM. "
              f"Leg blaster rows: {MINI}. {FULL}. "
              "Not included, no catalog match: Scotty Bobs, backwards sandbag drag. Not distilled: the PM run.",
        movements=blaster(8, 1) + [
            (786, "Sandbag Stone-to-Shoulder", 4, "5-6", GRIND, GETUP),
            (970, "Russian Twist", 4, "10", GRIND, "Seated, 15/25 lb dumbbell"),
            (636, "Calf Raise Endurance (Bilateral High-Rep)", 5, "20 sec on, 10 sec hold, twice", STEADY, CALVES + ". From session 14 on"),
        ],
    ),
    dict(
        name="Backpacking Strength: Leg Blaster, Sandbag Getup, Crawl",
        sports=[BACKPACKING, TREKKING, NON_TECH], credit=BACKPACK,
        minutes=45, environment="home", goal="strength",
        notes="Source: Backpack Pre-Season V2 sessions 20, 26, 32 and 38, and Kilimanjaro sessions 20 and 26. "
              "3 to 5 rounds of the full leg blaster (with 2 to 4 mini rounds in the early weeks), then 4 rounds of 4 to 5 Scotty Bobs "
              "at 15/25 lb, 6 to 7 sandbag getups, 10 dumbbell crawls at 15/25 lb and 10 kneeling slashers at 15/25 lb. "
              "Session 38 is a taper week: 2 rounds of the circuit. A 50 to 60 minute run follows in the PM. "
              f"Leg blaster rows: {FULL}. "
              "Not included, no catalog match: Scotty Bobs, kneeling slasher. Not distilled: the PM run.",
        movements=blaster(0, 5) + [
            (786, "Sandbag Stone-to-Shoulder", 4, "6-7", GRIND, GETUP),
            (120, "Bear Crawl", 4, "10", GRIND,
             "Substitute for Dumbbell Crawl, 15/25 lb. Hold the dumbbells if you can keep the hips level"),
        ],
    ),
    dict(
        name="Backpacking Strength: Leg Blaster, Good Morning, Sandbag Getup",
        sports=[BACKPACKING, TREKKING, NON_TECH], credit=BACKPACK,
        minutes=45, environment="home", goal="strength",
        notes="Source: Backpack Pre-Season V2 sessions 23, 29 and 35, and Kilimanjaro sessions 23 and 29 (low back days). "
              "3 to 5 rounds of the full leg blaster, then 4 rounds of 10 sandbag good mornings at 40/60 lb, 4 to 5 Scotty Bobs "
              "at 15/25 lb, 15/15 low back lunge and 6 to 7 sandbag getups. The earlier low back days (Backpack sessions 5, 11 and 17, "
              "Kilimanjaro 5, 11 and 17) run 15/15 standing and kneeling founders in place of the good morning and low back lunge. "
              "A 50 to 60 minute run follows in the PM. "
              f"Leg blaster rows: {FULL}. "
              "Not included, no catalog match: Scotty Bobs, low back lunge, standing and kneeling founder. Not distilled: the PM run.",
        movements=blaster(0, 5) + [
            (921, "Barbell Good Morning", 4, "10", GRIND, GOOD_MORNING),
            (786, "Sandbag Stone-to-Shoulder", 4, "6-7", GRIND, GETUP),
        ],
    ),
    dict(
        name="Fastpacking Eccentric Legs: Mini Leg Blaster, Push-Up, Sandbag Grind",
        sports=[FASTPACKING], credit=R2R2R,
        minutes=50, environment="home", goal="endurance",
        notes="Source: Rim to Rim to Rim sessions 1, 9 and 16 (and 4, 12, 19, 23 and 26 in the same weeks). "
              "10 rounds of the mini leg blaster with 3/6 push-ups (weeks 2 to 4: 2 to 3 full leg blasters first, then 4 to 6 mini), "
              "30 seconds rest each round. Then a 12 to 15 minute grind of 4 to 5 sandbag getups, 2 to 3 sandbag cross cleans and "
              "8 to 10 sandbag good mornings at 40/60 lb. The alternate days swap that grind for sandbag toss and chase, backwards "
              "sandbag drags and 15/15 to 20/20 standing founder. Then 3 to 5 rounds of calf raise intervals and 2 rounds of the HUG "
              "hip mobility drill. Warm-up is 3 rounds of 10 squats, 5 walking lunges and 5 burpees. "
              f"Leg blaster rows: {MINI}. {FULL}. "
              "Not included, no catalog match: sandbag cross clean, sandbag toss and chase, backwards sandbag drag, standing founder, "
              "HUG hip mobility drill.",
        movements=blaster(8, 2) + [
            (13, "Push-Up", 10, "3-6", STEADY, "3 (women) / 6 (men) in the source, after each leg blaster round. Hand-release from week 4"),
            (786, "Sandbag Stone-to-Shoulder", 4, "4-5", GRIND, GETUP + ". Grind circuit, 12 to 15 minutes"),
            (921, "Barbell Good Morning", 4, "8-10", GRIND, GOOD_MORNING),
            (636, "Calf Raise Endurance (Bilateral High-Rep)", 4, "20 sec on, 10 sec hold, twice", STEADY, CALVES),
        ],
    ),
    dict(
        name="Fastpacking Eccentric Legs: Leg Blaster, Plyo Push-Up, Carry Grind",
        sports=[FASTPACKING], credit=R2R2R,
        minutes=55, environment="home", goal="endurance",
        notes="Source: Rim to Rim to Rim sessions 30, 33, 37, 40, 44, 47 and 51 (weeks 5 to 8). "
              "5 to 7 rounds of the full leg blaster, each followed by 3/5 alligator push-ups (weeks 7 and 8: 2/4 to 3/5 clapping "
              "push-ups). Then an 18 to 20 minute sandbag grind at 40/60 lb in rotating shapes: 5 getups, 2 clean and runs and 10 EOs; "
              "3 Mr. Spectaculars, 3 cross cleans and a 30 second bear hug walk; 10 good mornings, a 30/30 second shoulder carry "
              "and 5 getups; or 3 clean, squat and runs and 10 toes to sky. Then 6 to 8 rounds of calf raise intervals. "
              "Sessions 30 and 37 add a 3 mile moderate run, which may be done in the PM. Warm-up is 3 rounds of 10 squats, "
              "5 walking lunges and 5 burpees. "
              f"Leg blaster rows: {FULL}. "
              "Not included, no catalog match: alligator push-up, sandbag clean and run, Mr. Spectacular, cross clean, EOs, toes to sky. "
              "Not distilled: the run.",
        movements=blaster(0, 6) + [
            (1059, "Plyo Push-Up", 6, "3-5", STEADY,
             "Clapping push-ups in weeks 7 and 8, alligator push-ups (a travelling push-up) before. 3 (women) / 5 (men) in the source"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, GETUP + ". Grind circuit, 18 to 20 minutes"),
            (328, "Sandbag Bear Hug Carry", 4, "30 sec", GRIND, "Bear hug walk, 40/60 lb"),
            (571, "Sandbag Shoulder Carry", 4, "30 sec per shoulder", GRIND, "30 seconds on the right shoulder, then 30 on the left"),
            (636, "Calf Raise Endurance (Bilateral High-Rep)", 7, "20 sec on, 10 sec hold, twice", STEADY, CALVES),
        ],
    ),
    dict(
        name="Mountaineering Leg Strength: Leg Blaster, Low Back Grind, Calf Intervals",
        sports=[NON_TECH, TECHNICAL, EXPEDITION], credit=RAINIER,
        minutes=45, environment="home", goal="endurance",
        notes="Source: Rainier sessions 2, 8, 20, 26, 32 and 38 (2-a-day leg and chassis days; a mountain endurance session follows). "
              "3 to 5 rounds of the 4 square drill, then the leg blaster progression: 10 mini rounds in week 1, 2 full and 6 mini, "
              "then 4 to 5 full rounds by week 4. Then a 15 to 18 minute grind of 20/20 standing founder, 10 face-down back extensions, "
              "20/20 kneeling founder and 10 sandbag good mornings at 40/60 lb, then 3 to 6 rounds of 2 calf raise intervals. "
              "The Friday leg days (sessions 5, 11, 23, 29 and 35) are the same work without the grind. "
              f"Leg blaster rows: {MINI}. {FULL}. "
              "Not included, no catalog match: 4 square drill, standing and kneeling founder. "
              "The catalog Superman hold stands in for the face-down back extension, done as reps. "
              "Also tagged to technical and expedition mountaineering: the Teton and Denali plans' own low back work is founder "
              "grinds with no catalog match.",
        movements=blaster(4, 4) + [
            (220, "Superman Hold", 4, "10", GRIND, BACK_EXT + ". Grind circuit, 15 to 18 minutes"),
            (921, "Barbell Good Morning", 4, "10", GRIND, GOOD_MORNING),
            (636, "Calf Raise Endurance (Bilateral High-Rep)", 5, "20 sec on, 10 sec hold, twice", STEADY, CALVES),
        ],
    ),
    dict(
        name="Mountaineering Chassis: Sandbag Getups, Pull-Up, Push-Up, Sit-Up",
        sports=[NON_TECH, TECHNICAL, EXPEDITION], credit=RAINIER,
        minutes=45, environment="home", goal="strength",
        notes="Source: Rainier sessions 3, 9, 21, 27 and 33 (chassis integrity and upper body). "
              "50 sandbag getups at 40/60 lb in week 1, rising to 80 by week 6, done for total reps at a steady pace. "
              "Then 5 rounds of 3/5 pull-ups, 7/10 hand-release push-ups and 10 sit-ups, rising to 10 rounds. "
              "The Denali Friday chassis day opens with the same getups (40 to 70) and follows with a founder and slasher grind; "
              "this routine stands in for it on expedition and technical mountaineering.",
        movements=[
            (786, "Sandbag Stone-to-Shoulder", 1, "50-80 total", GRIND,
             GETUP + ". One block for total reps: 50 in week 1, 65 in week 2, 70 to 80 from week 4"),
            (922, "Pull-Up", 8, "3-5", STEADY, "3 (women) / 5 (men) in the source. 5 rounds in week 1, up to 10"),
            (13, "Push-Up", 8, "7-10", STEADY, HAND_RELEASE + ". 7 (women) / 10 (men) in the source"),
            (969, "Sit-Up", 8, "10", STEADY, "Third movement of each pull-up and push-up round"),
        ],
    ),
    dict(
        name="Alpine Strength: Leg Blaster, Push-Up, Pull-Up",
        sports=[TECHNICAL, EXPEDITION], credit=TETON_DENALI,
        minutes=40, environment="home", goal="strength",
        notes="Source: Teton Grand Traverse strength days (sessions 2, 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35, 38, 41 and 44), "
              "and the PM strength work of Denali sessions 2, 4, 8, 10, 14, 16, 20, 22, 26, 28, 32, 34 and 38. "
              "Leg blasters progress from 10 mini rounds to 2 full and 6 mini, then 4 full and 2 mini, then 5 full. "
              "Then 3 to 6 rounds of an upper body circuit: Teton runs 5/10 hand-release push-ups, 2/5 pull-ups and 10 EOs, "
              "rising to 8/16, 5/8 and 16; Denali runs 3/5 pull-ups, 7/10 hand-release push-ups and 8 EOs on Tuesday and "
              "3/5 pull-ups, 10/15 push-ups and 20 sit-ups on Thursday after the tire drag. Foam roll quads and low back to finish. "
              f"Leg blaster rows: {MINI}. {FULL}. "
              "Not included, no catalog match: EOs, foam rolling. Not distilled: Teton's run, Denali's run and tire drag.",
        movements=blaster(4, 4) + [
            (13, "Push-Up", 5, "5-16", STEADY, HAND_RELEASE + ". 5 to 8 (women) / 10 to 16 (men) in the Teton plan"),
            (922, "Pull-Up", 5, "2-8", STEADY, "2 to 5 (women) / 5 to 8 (men) in the Teton plan, 3/5 in the Denali plan"),
            (969, "Sit-Up", 4, "20", STEADY, "Denali Thursday only, in place of the EOs"),
        ],
    ),
    dict(
        name="Scrambling Strength: Leg Blaster, Good Morning, Hip Bridge",
        sports=[SCRAMBLING], credit=PEAK_BAGGER,
        minutes=40, environment="home", goal="endurance",
        notes="Source: Peak Bagger V5 sessions 2, 8, 14, 20, 26 and 32 (Tuesday AM, a run follows in the PM). "
              "10 mini leg blaster rounds in week 1, then 3 full and 6 mini, 4 full and 2 mini, and 5 full from week 4. "
              "Then 3 to 4 rounds of 10 sandbag good mornings at 40/60 lb, 10 hip bridges and 10 EOs, then 2 to 6 calf raise "
              "intervals and foam rolling. Warm-up is 3 rounds of 10 squats, 5 hand-release push-ups, 5 walking lunges and 10 sit-ups. "
              f"Leg blaster rows: {MINI}. {FULL}. "
              "Not included, no catalog match: EOs, instep stretch, foam rolling. Not distilled: the PM run.",
        movements=blaster(4, 4) + [
            (921, "Barbell Good Morning", 4, "10", STEADY, GOOD_MORNING),
            (1020, "Glute Bridge", 4, "10", STEADY, "Hip bridge"),
            (636, "Calf Raise Endurance (Bilateral High-Rep)", 4, "20 sec on, 10 sec hold, twice", STEADY, CALVES),
        ],
    ),
    dict(
        name="Scrambling Strength: Sandbag Getups, Pull-Up, Walking Lunge",
        sports=[SCRAMBLING], credit=PEAK_BAGGER,
        minutes=35, environment="home", goal="strength",
        notes="Source: Peak Bagger V5 sessions 3, 9, 15, 21, 27, 33 and 39 (core and upper body day; a 2 to 5 mile run follows). "
              "40 sandbag getups at 40/60 lb for total reps, then 3 to 4 rounds of 5 Scotty Bobs at 15/25 lb and 3/5 pull-ups. "
              "Warm-up is 3 rounds of 5 walking lunges, 5 hand-release push-ups and 10 sit-ups, with instep and lat/pec stretches. "
              "Not included, no catalog match: Scotty Bobs, stretches. Not distilled: the run.",
        movements=[
            (943, "Walking Lunge", 3, "5", "warm-up", "Warm-up circuit with the push-up and sit-up"),
            (13, "Push-Up", 3, "5", "warm-up", HAND_RELEASE),
            (969, "Sit-Up", 3, "10", "warm-up", "Warm-up circuit"),
            (786, "Sandbag Stone-to-Shoulder", 1, "40 total", GRIND, GETUP + ". One block for total reps"),
            (922, "Pull-Up", 4, "3-5", STEADY, "3 (women) / 5 (men) in the source. Paired with 5 Scotty Bobs each round"),
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
            difficulty="intermediate", phase="build",
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
