#!/usr/bin/env python3
"""Distill Nordic, dryland and backcountry ski strength routines into coach.db.

Backlog 2026-11e 3.6. Sources are eight Mountain Tactical Institute plans:
10k, 15k, 20k, 30k and 50k Nordic Ski Race (272 to 276), Dryland Ski V6 (265),
In Season Ski Maintenance V2 (266) and Backcountry Ski Pre-Season V6 (268).

Phases follow the plan: Nordic race, Dryland and Backcountry Pre-Season are
`build`; In Season Ski Maintenance is `maintenance`.

- xc-skiing (212): the five Nordic race plans run one strength spine (a 4 round
  warm-up, assessments, leg blaster rounds and a 15 minute grind) in four
  rotating shapes, so each shape is distilled once and serves all five plans.
- xc-skiing, backcountry-touring (216), telemark-skiing (220): the Dryland plan's
  leg lactate day and eccentric leg day, and the In Season plan's two chassis
  strength days and its weekend warrior leg day.
- backcountry-touring, telemark-skiing: the Backcountry Pre-Season leg lactate
  days (early, late and the final weeks) and the eccentric uphill leg day.

The family root (snow-sports, 200) is not tagged, matching 3.5.

Not distilled: run, bike, ski and step-up-only endurance days, assessments and
the foam roll and stretch blocks, the Nordic plans' speed and interval days.

Catalog exercises only. Each movement is checked against the expected catalog
name, so a stale id fails the run instead of linking the wrong exercise.
Source movements with no catalog match are left out and named in the routine
notes. Source loads written "40/60#" and reps written "3/5x" are MTI's
women/men scale.
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_ski.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

XC = 212
BACKCOUNTRY = 216
TELEMARK = 220

NORDIC = "MTI 10k to 50k Nordic Ski Race Training Plans (distilled)"
DRYLAND = "MTI Dryland Ski Training Plan V6 (distilled)"
INSEASON = "MTI In Season Ski Maintenance - V2 (distilled)"
BACKCOUNTRY_PLAN = "MTI Backcountry Ski Pre-Season Training Plan V6 (distilled)"

ALL_SKI = [XC, BACKCOUNTRY, TELEMARK]
BC_SPORTS = [BACKCOUNTRY, TELEMARK]

GRIND = "work steadily, not frantically, through the circuit"
STEADY = "steady"
MODERATE = "moderate, comfortable but not easy"
HARD = "increase load each round until the reps are hard but doable"
HAND_RELEASE = "Hand-release: chest to the floor and hands lifted each rep"
MINI = "Mini leg blaster round, done as its parts: 10 squats, 10 in-place lunges, 10 jumping lunges, 5 squat jumps"
FULL = "Full leg blaster round, done as its parts: 20 squats, 20 in-place lunges, 20 jumping lunges, 10 squat jumps"
GETUP = ("Substitute for Sandbag Getup, 40/60 lb in the source: lie down with the bag on one shoulder, stand up, "
         "alternate shoulders each rep")
CURL = "Substitute for the poor man's leg curl: on your back, heels on a towel or slider, bridge up and curl the heels in"
TJT = ("Stands in for touch jump touch to box, an assessment then 25% of the assessed max reps every minute on the minute: "
       "touch the box, jump, touch it again")


def blaster(rounds, size, tail="Rest 30 seconds after each round"):
    """The leg blaster as its catalog parts, one row per part. `size` is
    "mini", "full" or "mixed" (full rounds first, then mini rounds)."""
    big, small = {"mini": ("10", "5"), "full": ("20", "10"), "mixed": ("10-20", "5-10")}[size]
    return [
        (1088, "Squat (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 1"),
        (1051, "Lunge (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 2. In place, alternate legs, each step is a rep"),
        (130, "Split Squat Jump", rounds, big, STEADY, "Leg blaster, part 3: jumping lunges"),
        (1034, "Jump Squat", rounds, small, STEADY, f"Leg blaster, part 4. {tail}"),
    ]


NORDIC_WARM = ("Warm-up is 4 rounds of 10 squats, 5 push-ups, 5 walking lunges and 10 sit-ups with an instep stretch. "
               "Assessments, run in sessions 1 and 14 and again late in the plan: max weighted sit-ups at 15/25 lb in 2 minutes, "
               "max strict pull-ups and max bench dips in 2 minutes. Early rounds then run at 30 to 40% of those max reps. ")

ROUTINES = [
    dict(
        name="Nordic Ski Strength: Leg Blaster, Pull-Up, Dip, Renegade Grind",
        sports=[XC], credit=NORDIC, phase="build",
        minutes=60, environment="gym", goal="strength",
        notes="Source: the 10k, 15k, 20k, 30k and 50k Nordic Ski Race strength days (Tuesdays and Thursdays, objective strength). "
              "Mini and full leg blaster rounds with pull-ups at 30 to 35% of the assessed max and 15 seconds rest, "
              "weighted sit-ups and bench dips, then a 15 minute grind of 5 renegade man makers and 5 kneeling plate half moons "
              "at 15/25 lb, 10 slashers and 10 face down back extensions. "
              f"Leg blaster rows: {MINI}. {FULL}. {NORDIC_WARM}"
              "Not included, no catalog match: renegade man maker, kneeling plate half moon, slasher, foam roll.",
        movements=[
            (969, "Sit-Up", 6, "11-15", "35% of assessed max", "Weighted at 15/25 lb. 6 rounds every 90 seconds, or a 2 minute max set on assessment days"),
        ] + blaster(5, "mixed", "Rest 15 seconds after each round") + [
            (922, "Pull-Up", 5, "30-40% of max", STEADY, "Inside each blaster round, from the assessed max"),
            (987, "Bench Dip", 6, "35% of max", "every 90 seconds", "Or a 2 minute max set on assessment days"),
            (373, "Renegade Row", 1, "5 per round", GRIND, "Stands in for the renegade man maker at 15/25 lb. 15 minute grind"),
            (220, "Superman Hold", 1, "10 per round", GRIND, "Face-down back extension: lift chest and legs off the floor and lower"),
        ],
    ),
    dict(
        name="Nordic Ski Strength: Leg Blaster, Pull-Up, Dip, Thruster and Crawl Grind",
        sports=[XC], credit=NORDIC, phase="build",
        minutes=60, environment="gym", goal="strength",
        notes="Source: the 10k, 15k, 20k, 30k and 50k Nordic Ski Race strength days from week 3 on. "
              "Full leg blaster rounds, 3 to 6 rounds, with pull-ups at 30% of the assessed max and 15 seconds rest, "
              "then bench dips, then a 15 minute grind of 5 thrusters and 5 dumbbell crawls at 15/25 lb, 10 kneeling slashers and 15/15 low back lunges. "
              f"Leg blaster rows: {FULL}. {NORDIC_WARM}"
              "Not included, no catalog match: kneeling slasher, low back lunge, foam roll.",
        movements=blaster(5, "full", "Rest 15 to 30 seconds after each round") + [
            (922, "Pull-Up", 5, "30% of max", STEADY, "Inside each blaster round, from the assessed max"),
            (969, "Sit-Up", 1, "max in 2 min", "assessment", "Weighted at 15/25 lb. Assessment days only"),
            (987, "Bench Dip", 1, "max in 2 min", "assessment", "Assessment days, 30 to 40% of max reps on the other days"),
            (1098, "Thruster (Kettlebell)", 1, "5 per round", GRIND, "Stands in for the dumbbell thruster at 15/25 lb. 15 minute grind"),
            (120, "Bear Crawl", 1, "5 per round", GRIND, "Substitute for the dumbbell crawl at 15/25 lb"),
        ],
    ),
    dict(
        name="Nordic Ski Strength: Leg Blaster, Turkish Get-Up, Hinge Grind",
        sports=[XC], credit=NORDIC, phase="build",
        minutes=60, environment="gym", goal="strength",
        notes="Source: the 15k, 20k, 30k and 50k Nordic Ski Race strength days from the middle of the plan (sessions 26 on). "
              "A 6 round sit-up grind every 90 seconds at 40% of the assessed max, 5 full leg blaster rounds with pull-ups at 40% of max, "
              "6 rounds of bench dips every 90 seconds, then a 15 minute grind of a 5/30/5 Sean Special, "
              "5 kneeling slasher to halos, 3 Turkish get-ups (alternate hands each round) and 15 dumbbell hinge lifts at 15/25 lb. "
              f"Leg blaster rows: {FULL}. {NORDIC_WARM}"
              "Not included, no catalog match: 5/30/5 Sean Special, slasher to halo, foam roll.",
        movements=[
            (969, "Sit-Up", 6, "40% of max", "every 90 seconds", "Weighted at 15/25 lb, as fast as possible; the faster you finish, the more rest"),
        ] + blaster(5, "full", "Rest 15 seconds after each round") + [
            (922, "Pull-Up", 5, "40% of max", STEADY, "Inside each blaster round, from the assessed max"),
            (987, "Bench Dip", 6, "40% of max", "every 90 seconds", "From the assessed max"),
            (119, "Turkish Get-Up", 1, "3 per round", GRIND, "15/25 lb dumbbell, alternate hands each round. 15 minute grind"),
            (1171, "Dumbbell Romanian Deadlift", 1, "15 per round", GRIND, "Dumbbell hinge lift at 15/25 lb, mid-shin to full hip extension"),
        ],
    ),
    dict(
        name="Nordic Ski Strength: Leg Blaster, Pull-Up, Sit-Up and Russian Twist Core Grind",
        sports=[XC], credit=NORDIC, phase="build",
        minutes=60, environment="gym", goal="strength",
        notes="Source: the 30k and 50k Nordic Ski Race strength days from week 4 on (session 32 is the last). "
              "Max sit-up, pull-up and bench dip assessments, 6 full leg blaster rounds with 30 seconds rest, "
              "then a 15 minute core grind of 15/15 standing founders, 15 weighted sit-ups at 15/25 lb, 15/15 kneeling founders "
              f"and 15 seated Russian twists at 15/25 lb. Leg blaster rows: {FULL}. {NORDIC_WARM}"
              "Not included, no catalog match: standing and kneeling founders, foam roll.",
        movements=blaster(6, "full") + [
            (922, "Pull-Up", 1, "max", "assessment", "Strict, hang between reps. Assessment before the blaster rounds"),
            (987, "Bench Dip", 1, "max in 2 min", "assessment", "Assessment after the blaster rounds"),
            (969, "Sit-Up", 5, "15", GRIND, "Weighted at 15/25 lb, inside the 15 minute grind"),
            (970, "Russian Twist", 5, "15", GRIND, "Seated, 15/25 lb dumbbell, inside the 15 minute grind"),
        ],
    ),
    dict(
        name="Dryland Ski Strength: Box Jump, Sandbag Clean, Pull-Up, Leg Curl",
        sports=ALL_SKI, credit=DRYLAND, phase="build",
        minutes=55, environment="gym", goal="strength",
        notes="Source: Dryland Ski V6 leg lactate tolerance days (sessions 1, 4, 6, 9, 11 and every other session through week 6). "
              "3 rounds of 10 squats, 5 walking lunges, 10 box jumps at 12 to 15 inches and 5 hand-release push-ups, "
              "a touch jump touch to box assessment (max reps in 2 minutes), 15 to 20 rounds every minute on the minute at 25% of that max "
              "(plus 1 to 2 reps in later weeks), then 4 to 5 rounds of 4 sandbag clean and presses at 40/60 lb, 2/5 pull-ups "
              "(later chin-ups or mixed grip) and 15 to 20 poor man's leg curls, one leg later on. "
              "Later weeks swap in sandbag toss and chase, sandbag burpees, renegade man makers and Mr. Spectacular at 15/25 lb. "
              "Not included, no catalog match: touch jump touch, Mr. Spectacular, sandbag toss and chase, stretches.",
        movements=[
            (49, "Box Jump", 15, "10-25", "every minute on the minute", TJT),
            (786, "Sandbag Stone-to-Shoulder", 5, "4", GRIND, "Substitute for the sandbag clean and press, 40/60 lb: clean the bag to the shoulder, then press it overhead"),
            (922, "Pull-Up", 5, "2-5", GRIND, "2 (women) / 5 (men). Later weeks use chin-ups or mixed grip"),
            (1020, "Glute Bridge", 3, "15-20", GRIND, CURL),
            (373, "Renegade Row", 5, "4-5", GRIND, "Stands in for the renegade man maker at 15/25 lb, in the later weeks"),
        ],
    ),
    dict(
        name="Dryland Ski Strength: Leg Blaster, Sandbag Grind, Good Morning",
        sports=ALL_SKI, credit=DRYLAND, phase="build",
        minutes=55, environment="gym", goal="strength",
        notes="Source: Dryland Ski V6 eccentric leg strength days (sessions 2, 5, 7, 10 and every other session through week 6). "
              "3 rounds of 10 squats, 5 walking lunges and 5 hand-release push-ups, then 5 to 10 rounds of the mini leg blaster, "
              "full in the later weeks, with Scotty Bobs at 15/25 lb, then a 4 to 5 round grind of 5 backwards sandbag drags, "
              "10 kneeling slashers and 10 sandbag good mornings at 40/60 lb (later: dumbbell pass throughs, sandbag cross cleans, "
              f"sandbag getups, dumbbell crawls and 15/15 low back lunges). Leg blaster rows: {MINI}. {FULL}. "
              "Not included, no catalog match: Scotty Bob, backwards sandbag drag, kneeling slasher, dumbbell pass through, low back lunge, stretches.",
        movements=blaster(8, "mixed") + [
            (13, "Push-Up", 3, "5", "warm-up", HAND_RELEASE),
            (921, "Barbell Good Morning", 4, "10", GRIND, "Substitute for the sandbag good morning at 40/60 lb"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, GETUP + ". Stands in for the sandbag cross clean too"),
            (120, "Bear Crawl", 4, "5", GRIND, "Substitute for the dumbbell crawl at 15/25 lb"),
        ],
    ),
    dict(
        name="In Season Ski Strength: Hinge, Floor Press, Sandbag Grind",
        sports=ALL_SKI, credit=INSEASON, phase="maintenance",
        minutes=50, environment="gym", goal="strength",
        notes="Source: In Season Ski Maintenance V2 strength and chassis integrity days with a hinge and a floor press (Tuesdays, sessions 2, 7 and alternate weeks). "
              "5 rounds of 5 hinge lifts and 5 kettlebell floor presses (or 8 kneeling curls to press, or 5 walking lunges) adding load each round until the last set is hard but doable, "
              "then a 12 minute grind of 5 slashers at 12/16 kg, 5 sandbag clean and presses at 40/60 lb and 15/15 standing founders "
              "(other weeks keg lifts, sandbag getups and cleans, and toss and chase). "
              "Warm-up is 3 rounds of 10 hinge lifts at 65/95 lb, 10 push-ups, 10 goblet squats at 12 kg and 10 step-ups. "
              "Not included, no catalog match: toe touch complex, slasher, standing founder, keg lift, Scotty Bobs, stretches.",
        movements=[
            (59, "Conventional Deadlift", 5, "5", HARD, "Hinge lift"),
            (313, "Dumbbell Floor Press", 5, "5", HARD, "Kettlebell floor press in the source"),
            (15, "Dumbbell Overhead Press", 5, "8", HARD, "Stands in for the kneeling curl to press in the weeks that swap it in"),
            (786, "Sandbag Stone-to-Shoulder", 1, "12 min grind", GRIND, "Substitute for the sandbag clean and press and the sandbag getup, 40/60 lb"),
            (60, "Goblet Squat", 3, "10", "warm-up", "12 kg, warm-up circuit"),
        ],
    ),
    dict(
        name="In Season Ski Strength: Squat, Press, Pull-Up, Sandbag Grind",
        sports=ALL_SKI, credit=INSEASON, phase="maintenance",
        minutes=50, environment="gym", goal="strength",
        notes="Source: In Season Ski Maintenance V2 strength and chassis integrity days with a squat and a press (Thursdays, sessions 24 and alternate weeks). "
              "5 rounds of 5 back or front squats and 5 bench or Arnold presses, adding load each round until the last set is hard but doable, "
              "with 2/5 pull-ups, mixed grip pull-ups or 3/6 chin-ups, then a 12 minute grind of 5 sandbag getups, 5 keg lifts and 10 sandbag good mornings at 40/60 lb. "
              "Warm-up is 3 rounds of 10 back squats at 45/65 lb, 5 hand-release push-ups and 4 forty-foot shuttles. "
              "Not included, no catalog match: keg lift, shuttle, shoulder hold lunge, Craig special, Tarzan pull-up, stretches.",
        movements=[
            (57, "Barbell Back Squat", 5, "5", HARD, "Some weeks the front squat (450) or the shoulder hold lunge"),
            (909, "Arnold Press", 5, "5", HARD, "Some weeks the bench press (900) or alligator push-ups"),
            (922, "Pull-Up", 5, "2-5", STEADY, "2 (women) / 5 (men), mixed grip or 3/6 chin-ups in other weeks"),
            (786, "Sandbag Stone-to-Shoulder", 1, "12 min grind", GRIND, GETUP + ". Stands in for the keg lift"),
            (921, "Barbell Good Morning", 1, "10", GRIND, "Substitute for the sandbag good morning at 40/60 lb, inside the grind"),
        ],
    ),
    dict(
        name="In Season Ski Strength: Leg Blaster, Box Jump, Leg Curl",
        sports=ALL_SKI, credit=INSEASON, phase="maintenance",
        minutes=40, environment="gym", goal="strength",
        notes="Source: In Season Ski Maintenance V2 weekend warrior days (objective eccentric leg strength and leg lactate tolerance). "
              "3 rounds of 10 goblet squats at 12 kg, 5 hand-release push-ups and 5 in-place lunges, then 8 rounds of the mini leg blaster with 30 seconds rest, "
              "10 rounds of 15 seconds of 20 inch box jumps with 30 seconds rest, and 3 rounds of 15 poor man's leg curls. "
              f"Leg blaster rows: {MINI}. Not included, no catalog match: foam roll.",
        movements=blaster(8, "mini") + [
            (49, "Box Jump", 10, "max in 15 s", "30 seconds rest", "20 inch box, jump for 15 seconds, rest 30 seconds"),
            (1020, "Glute Bridge", 3, "15", STEADY, CURL),
        ],
    ),
    dict(
        name="Backcountry Ski Strength: Box Jump, Pull-Up, Leg Curl, Sandbag Clean Grind",
        sports=BC_SPORTS, credit=BACKCOUNTRY_PLAN, phase="build",
        minutes=60, environment="gym", goal="strength",
        notes="Source: Backcountry Ski Pre-Season V6 leg lactate tolerance days, weeks 1 to 4 (sessions 2, 4, 8, 10, 14 and 16). "
              "3 rounds of 10 squats, 10 box jumps at 16 to 18 inches and 5 hand-release push-ups, a touch jump touch to box assessment, "
              "15 to 20 rounds every minute on the minute at 25% of that max, then two 4 round grinds: 5 Scotty Bobs at 15/25 lb, 3/5 pull-ups and "
              "15 two-leg poor man's leg curls (week 3: 8 kneeling curls to press, chin-ups and one-leg leg curls), then 5 backwards sandbag drags, "
              "10 kneeling slashers and 5 sandbag clean and presses (or 10 sandbag good mornings with standing and kneeling founders) at 40/60 lb. "
              "Not included, no catalog match: Scotty Bob, backwards sandbag drag, kneeling slasher, founders, stretches.",
        movements=[
            (49, "Box Jump", 15, "10-25", "every minute on the minute", TJT),
            (922, "Pull-Up", 4, "3-5", GRIND, "3 (women) / 5 (men). Chin-ups in the weeks that swap them in"),
            (1020, "Glute Bridge", 4, "15", GRIND, CURL),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, "Substitute for the sandbag clean and press, 40/60 lb: clean the bag to the shoulder, then press it overhead"),
            (921, "Barbell Good Morning", 4, "10", GRIND, "Substitute for the sandbag good morning at 40/60 lb, on the good morning days"),
        ],
    ),
    dict(
        name="Backcountry Ski Strength: Curl to Press, Chin-Up, Sandbag Carry Grind",
        sports=BC_SPORTS, credit=BACKCOUNTRY_PLAN, phase="build",
        minutes=60, environment="gym", goal="strength",
        notes="Source: Backcountry Ski Pre-Season V6 leg lactate tolerance days, weeks 3 to 6 (sessions 14, 16, 20 and 22 on). "
              "The same warm-up and every minute on the minute touch jump touch to box block (20 rounds, plus 1 to 2 reps), "
              "then a 4 round grind of 8 kneeling curls to press at 15/25 lb, 3/5 chin-ups and 10 one-leg poor man's leg curls, "
              "then 6 sandbag getups (alternate shoulders each round), 6 sandbag cross cleans and a 30 second sandbag Zercher carry at 40/60 lb. "
              "Not included, no catalog match: touch jump touch, stretches.",
        movements=[
            (49, "Box Jump", 20, "10-25", "every minute on the minute", TJT),
            (15, "Dumbbell Overhead Press", 4, "8", GRIND, "Stands in for the kneeling curl to press at 15/25 lb"),
            (923, "Chin-Up", 4, "3-5", GRIND, "3 (women) / 5 (men)"),
            (103, "Single-Leg Glute Bridge", 4, "10", GRIND, "Substitute for the one-leg poor man's leg curl: heel on a towel or slider, bridge up and curl the heel in"),
            (786, "Sandbag Stone-to-Shoulder", 4, "6", GRIND, GETUP + ". Stands in for the sandbag cross clean too"),
            (328, "Sandbag Bear Hug Carry", 4, "30 s", GRIND, "Substitute for the sandbag Zercher carry, 40/60 lb"),
        ],
    ),
    dict(
        name="Backcountry Ski Strength: Renegade Row, Hamstring, Sandbag Toss Grind",
        sports=BC_SPORTS, credit=BACKCOUNTRY_PLAN, phase="build",
        minutes=60, environment="gym", goal="strength",
        notes="Source: Backcountry Ski Pre-Season V6 leg lactate tolerance days, final weeks (sessions 32, 34 and 38). "
              "The same warm-up and touch jump touch to box block (a fresh assessment in session 38, then 10 to 20 rounds every minute on the minute), "
              "then a 4 round grind of 5 renegade man makers at 15/25 lb, 3/5 mixed grip pull-ups and 20 hamstring hells, "
              "then 5 sandbag toss and chases, 2 sandbag getup and runs and a 45 second sandbag bear hug walk at 40/60 lb. "
              "Not included, no catalog match: touch jump touch, hamstring hell, sandbag toss and chase, stretches.",
        movements=[
            (49, "Box Jump", 15, "10-25", "every minute on the minute", TJT),
            (373, "Renegade Row", 4, "5", GRIND, "Stands in for the renegade man maker at 15/25 lb"),
            (922, "Pull-Up", 4, "3-5", GRIND, "3 (women) / 5 (men), mixed grip"),
            (103, "Single-Leg Glute Bridge", 4, "20", GRIND, "Substitute for hamstring hell: heel on a towel or slider, bridge up and curl the heel in"),
            (786, "Sandbag Stone-to-Shoulder", 4, "2-5", GRIND, GETUP + ". Stands in for the toss and chase and the getup and run"),
            (328, "Sandbag Bear Hug Carry", 4, "45 s", GRIND, "40/60 lb bear hug walk"),
        ],
    ),
    dict(
        name="Backcountry Ski Strength: Leg Blaster and Loaded Step-Ups",
        sports=BC_SPORTS, credit=BACKCOUNTRY_PLAN, phase="build",
        minutes=60, environment="home", goal="endurance",
        notes="Source: Backcountry Ski Pre-Season V6 eccentric leg strength and uphill endurance days (Mondays and Wednesdays, sessions 1, 3, 7 and alternate days through week 7). "
              "3 rounds of 10 squats, 5 in-place lunges and 5 hand-release push-ups, then 6 to 10 rounds of the mini leg blaster, full in later weeks "
              "(weeks 3 and 4 run 3 full and 4 mini rounds), with 30 seconds rest, then one round of 300 to 700 step-ups wearing a 25 lb backpack on a 16 to 18 inch bench, "
              f"moderate pace. Leg blaster rows: {MINI}. {FULL}. Not included: foam roll.",
        movements=blaster(8, "mixed") + [
            (13, "Push-Up", 3, "5", "warm-up", HAND_RELEASE),
            (238, "Loaded Step-Up", 1, "300-700", MODERATE, "25 lb backpack, 16 to 18 inch bench, each step is a rep. Moderate means comfortable but not easy"),
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
            difficulty="intermediate", phase=spec["phase"],
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
