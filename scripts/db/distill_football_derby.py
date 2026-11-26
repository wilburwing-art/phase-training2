#!/usr/bin/env python3
"""Distill the Mountain Tactical Institute football and roller derby plans into coach.db routines.

Backlog 2026-11e 3.8. Sources are five MTI plans: Football Base (409), Football Build (410),
Football Pre-Season Peak (412), Football In-Season Strength Training Plan (411) and Roller
Derby Pre-Season Training Plan (406). Every plan runs five sessions a week, two to four of them
in the weight room.

Phase follows `AuthoredRoutine.phaseLabels(for:)`: Football Base is `base`, Football Build
and Pre-Season Peak are `build`, Football In-Season is `maintenance`, Roller Derby
Pre-Season is `build`.

Football routines are tagged to flag-football (543), roller derby routines to roller-derby
(587). The family roots (team-rec-sports 530, skating-wheeled 580) are not tagged, matching
3.5 to 3.7.

Not distilled:
- Football speed and conditioning days (sessions 2 and 4 of Base, 2 and 4 of Build, 2 and 4
  of Pre-Season Peak): prone and three point sprints, 300 m and 150 m shuttles, down/back/down
  shuttles, burpee box jump drills, gassers, touch/jump/touch to a box. The weight room tail
  of the Build speed days (sandbag, dumbbell crawl, good morning and one-sided dead lift
  rounds) is a finisher on a sprint day and is not split out.
- Strength assessment sessions (Build 1, 16, 31; Pre-Season Peak 1, 16, 31 lower body and
  3, 18, 33 upper body; Roller Derby hinge lift 1RM sessions 1, 13, 31). Their loading
  schemes are noted inside the routine they match.
- Football In-Season sessions 4, 5, 7, 8 and 9 and their repeats. Each has fewer than three
  catalog matches (walking lunge and push press, power clean and Scotty Bob, bench press and
  Craig special, Craig special and curl to press, dumbbell pass through, slasher to halo and
  sandbag getup and run), so they cannot clear the three exercise floor honestly.
- The Roller Derby 60 minute recovery run, the 15 to 40 second jingle jangle and skater hop
  interval blocks inside the work capacity days, and all stretch and foam roll blocks.
- The final Build and Pre-Season Peak sessions that are total rest.

Idempotent: a routine whose slug already exists is skipped.
Run:  python3 scripts/db/distill_football_derby.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

FLAG_FOOTBALL = 543
ROLLER_DERBY = 587

BASE = "MTI Football Base (distilled)"
BUILD = "MTI Football Build (distilled)"
PEAK = "MTI Football Pre-Season Peak (distilled)"
INSEASON = "MTI Football In-Season Strength Training Plan (distilled)"
DERBY = "MTI Roller Derby Pre-Season Training Plan (distilled)"

HARD = "increase load each round until the last set is hard but doable"
STEADY = "steady"
GRIND = "work steadily through the rounds"
HAND_RELEASE = "Hand-release: chest to the floor and hands lifted each rep"
BAG = "Substitute for the sandbag keg lift, getup and clean and press, 40 to 80 lb in the source"
CIRCUIT = "Part 3 chassis circuit, 4 rounds"
MINI = "Mini leg blaster round, done as its parts: 10 squats, 10 in-place lunges, 10 jumping lunges, 5 squat jumps"
FULL = "Full leg blaster round, done as its parts: 20 squats, 20 in-place lunges, 20 jumping lunges, 10 squat jumps"


def blaster(rounds, size, rest="Rest 30 seconds after each round"):
    """The leg blaster as its catalog parts. `size` is "mini", "full" or "mixed"."""
    big, small = {"mini": ("10", "5"), "full": ("20", "10"), "mixed": ("10-20", "5-10")}[size]
    return [
        (1088, "Squat (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 1"),
        (1051, "Lunge (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 2. In place, alternate legs, each step is a rep"),
        (130, "Split Squat Jump", rounds, big, STEADY, "Leg blaster, part 3: jumping lunges"),
        (1034, "Jump Squat", rounds, small, STEADY, f"Leg blaster, part 4. {rest}"),
    ]


ROUTINES = [
    # Football Base (409), phase base
    dict(
        name="Football Base: Front Squat, Walking Lunge, Chin-Up, Chassis Circuit",
        sport=FLAG_FOOTBALL, phase="base", credit=BASE, minutes=50,
        notes="Source: Football Base sessions 1, 6, 11, 16, 21, 26 and 31 (strength, hypertrophy and chassis integrity). "
              "Part 1: 4 rounds of 12 front squats building to a hard 12, with 6 Scotty Bobs. Part 2: 4 rounds of 12 walking lunges "
              "building to a hard 12, with 8 chin-ups (negative chin-ups if the 8 cannot be done). Part 3: 4 rounds of a chassis "
              "circuit of kneeling plate half moons, a 40 lb sandbag keg lift and 10 good mornings with an empty bar. "
              "Sessions 11 to 26 go to 5 and then 6 rounds of 10 and then 8 reps on parts 1 and 2 and swap the circuit for sandbag getups, "
              "kneeling slashers to halo and standing founders (session 21 on: dumbbell pass throughs, slashers and 15 swings). "
              "Warm-up is 3 rounds of a Bronc complex, 5 hand-release push-ups and an instep stretch. "
              "Not included, no catalog match: Scotty Bob, Bronc complex, kneeling plate half moon, slasher to halo, standing founder, "
              "dumbbell pass through, stretches.",
        movements=[
            (450, "Front Squat (Barbell)", 4, "12", HARD, "Sessions 11 to 26 run 5 then 6 rounds of 10 then 8"),
            (943, "Walking Lunge", 4, "12", HARD, "Dumbbells or barbell"),
            (923, "Chin-Up", 4, "8", "bodyweight", "Negative chin-ups on a 5 second count if the 8 cannot be done"),
            (921, "Barbell Good Morning", 4, "10", "empty 45 lb bar", CIRCUIT),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", "40 lb sandbag", "Substitute for the standing keg lift (sandbag getup in sessions 11 to 20)"),
        ],
    ),
    dict(
        name="Football Base: Back Squat, Hinge Lift, Pull-Up, Chassis Circuit",
        sport=FLAG_FOOTBALL, phase="base", credit=BASE, minutes=50,
        notes="Source: Football Base sessions 3, 8, 13, 18, 23, 28 and 33. Part 1: 4 rounds of 12 back squats building to a hard 12, "
              "with 12 kneeling curl to presses and a toe touch complex. Part 2: 4 rounds of 12 hinge lifts building to a hard 12, "
              "with 6 pull-ups (negative pull-ups if the 6 cannot be done). Part 3 is the same chassis circuit as the front squat day. "
              "Sessions 13 to 28 go to 5 and then 6 rounds of 10 and then 8 reps and swap the circuit for sandbag getups and slashers. "
              "Not included, no catalog match: kneeling curl to press (Dumbbell Overhead Press stands in), toe touch complex, kneeling "
              "plate half moon, slasher to halo, standing founder, stretches.",
        movements=[
            (57, "Barbell Back Squat", 4, "12", HARD, "Sessions 13 to 28 run 5 then 6 rounds of 10 then 8"),
            (15, "Dumbbell Overhead Press", 4, "12", HARD, "Substitute for the kneeling curl to press"),
            (59, "Conventional Deadlift", 4, "12", HARD, "Substitute for the hinge lift"),
            (922, "Pull-Up", 4, "6", "bodyweight", "Negative pull-ups on a 5 second count if the 6 cannot be done"),
            (921, "Barbell Good Morning", 4, "10", "empty 45 lb bar", CIRCUIT),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", "40 lb sandbag", "Substitute for the standing keg lift"),
        ],
    ),
    dict(
        name="Football Base: Box Squat, Renegade Row, Hang Clean, Pull-Up, Chassis Circuit",
        sport=FLAG_FOOTBALL, phase="base", credit=BASE, minutes=50,
        notes="Source: Football Base sessions 5, 10, 15, 20 and 25. Part 1: 4 rounds of 12 box squats and 12 renegade rows, each building "
              "to a hard 12. Part 2: 4 rounds of 8 hang squat cleans building to a hard 8, with 6 mixed grip pull-ups. Part 3 is the same "
              "chassis circuit. Sessions 15 and 25 go to 5 and then 6 rounds of 10 then 8 reps (hang squat cleans 5 then 4). "
              "Not included, no catalog match: hang squat clean (Hang Power Clean stands in), kneeling plate half moon, slasher to halo, "
              "standing founder, 3rd world squat stretch, frog stretch.",
        movements=[
            (920, "Box Squat", 4, "12", HARD, "Sessions 15 and 25 run 5 then 6 rounds of 10 then 8"),
            (373, "Renegade Row", 4, "12", HARD, "Row each side"),
            (540, "Hang Power Clean", 4, "8", HARD, "Substitute for the hang squat clean. 5 then 4 reps in sessions 15 and 25"),
            (922, "Pull-Up", 4, "6", "bodyweight", "Mixed grip in the source. Negative pull-ups if the 6 cannot be done"),
            (921, "Barbell Good Morning", 4, "10", "empty 45 lb bar", CIRCUIT),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", "40 lb sandbag", "Substitute for the standing keg lift"),
        ],
    ),
    dict(
        name="Football Base: Back Squat, Chin-Up, Cauldron Grind, Nordic Curl",
        sport=FLAG_FOOTBALL, phase="base", credit=BASE, minutes=40,
        notes="Source: Football Base session 32 (strength and chassis integrity). Part 1: 6 rounds of 5 back squats building to a hard 5, "
              "with 8 chin-ups. Part 2: a 4 round grind of 5 cauldrons at 15 lb, 5 seated keg lifts at 20 kg and 20/20 low back lunges. "
              "Part 3: 2 rounds of 5 Nordic hamstring curls. Warm-up is 4 rounds of a Bronc complex at 65 lb and 5 hand-release push-ups. "
              "Not included, no catalog match: cauldron, low back lunge, Bronc complex, stretches.",
        movements=[
            (57, "Barbell Back Squat", 6, "5", HARD, "Part 1"),
            (923, "Chin-Up", 6, "8", "bodyweight", "Alternates with the squats"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, "Substitute for the seated keg lift, 20 kg in the source"),
            (102, "Nordic Hamstring Curl", 2, "5", "bodyweight", "Part 3"),
        ],
    ),
    # Football Build (410), phase build
    dict(
        name="Football Build: Front Squat, Bench Press, Power Clean, Pull-Up Percentage Day",
        sport=FLAG_FOOTBALL, phase="build", credit=BUILD, minutes=60,
        notes="Source: Football Build sessions 3, 5, 6, 8, 10, 11, 13, 15, 18, 20, 21, 23, 25, 26, 28 and 30 (strength). For each of front squat, "
              "bench press and power clean: 4 reps at 50% 1RM, 4 reps at 75% 1RM, then 5 rounds every 90 seconds of 4 reps at 80% "
              "(sessions 3 and 5), 85% (sessions 6, 8, 10) or 90% (sessions 11, 13, 15). Then 6 rounds every 90 seconds of pull-ups at "
              "30%, 35% or 40% of max reps, and 2 rounds of 5 shoulder dislocates. The 1RM and max rep pull-up sessions (1, 16, 31) set the "
              "percentages. Warm-up is 3 rounds of a 65 lb barbell complex. "
              "Not included, no catalog match: barbell complex, shoulder dislocate, stretches.",
        movements=[
            (450, "Front Squat (Barbell)", 7, "4", "4 at 50%, 4 at 75%, then 5 rounds every 90 seconds at 80 to 90% 1RM", "Percentage of the athlete's 1RM"),
            (900, "Barbell Bench Press", 7, "4", "4 at 50%, 4 at 75%, then 5 rounds every 90 seconds at 80 to 90% 1RM", "Percentage of the athlete's 1RM"),
            (217, "Power Clean", 7, "4", "4 at 50%, 4 at 75%, then 5 rounds every 90 seconds at 80 to 90% 1RM", "Percentage of the athlete's 1RM"),
            (922, "Pull-Up", 6, "30-40% of max reps", "every 90 seconds", "Strict, no kipping"),
        ],
    ),
    # Football Pre-Season Peak (412), phase build
    dict(
        name="Football Peak: Back Squat, Walking Lunge, Deadlift Lower Body Day",
        sport=FLAG_FOOTBALL, phase="build", credit=PEAK, minutes=55,
        notes="Source: Football Pre-Season Peak sessions 5, 6, 10, 11, 15, 20, 21, 25, 26 and 30 (lower and total body strength), plus the "
              "hinge lift from the assessment sessions 1, 16 and 31. Part 1: 8 rounds of 3 back squats. Part 2: 8 rounds of 3 kettlebell or "
              "dumbbell walking lunges. Part 3: 9 rounds of 2 Craig specials. Rounds 1 to 3 are 65%, 75% and 85% of the finishing load "
              "from the session 1 assessment, rounds 4 to 8 (4 to 9 for part 3) are that finishing load less 10 lb (5 lb in later "
              "blocks). The assessment weeks work up to a hard 3 back squat, 2 Craig special and 3 hinge lift over 8 or 9 rounds. "
              "Warm-up is 3 rounds of a 65 to 75 lb barbell complex. "
              "Not included, no catalog match: Craig special, barbell complex, stretches.",
        movements=[
            (57, "Barbell Back Squat", 8, "3", "65%, 75%, 85% of the finishing load, then the finishing load less 10 lb", "Finishing load comes from the assessment"),
            (1164, "Kettlebell Walking Lunge", 8, "3", "65%, 75%, 85% of the finishing load, then the finishing load less 10 lb", "Kettlebell or dumbbell"),
            (59, "Conventional Deadlift", 8, "3", HARD, "Substitute for the hinge lift, done in the assessment sessions 1, 16 and 31"),
        ],
    ),
    dict(
        name="Football Peak: Bench Press, Push Press, Pull-Up, Chassis Circuit",
        sport=FLAG_FOOTBALL, phase="build", credit=PEAK, minutes=55,
        notes="Source: Football Pre-Season Peak sessions 8, 13, 23 and 28 (upper body strength and chassis integrity), with the assessment "
              "versions in sessions 3, 18 and 33. Part 1: 8 rounds of 3 bench presses with pull-ups at 30% then 35% of max reps. Part 2: "
              "9 rounds of 2 push presses. Loading is 65%, 75% and 85% of the assessment finishing load for rounds 1 to 3, then that load "
              "less 10 lb. Part 4: 4 rounds of 5 sandbag getups at 60 lb, 5 sandbag keg lifts and 10 good mornings at 55 lb (sessions 23 and "
              "28: 5 sandbag toss and chases, 5 kneeling keg lifts and 15/15 standing founders). Warm-up is 3 rounds of 8 bench presses at "
              "95 lb, 1 pull-up, 8 dumbbell push presses and 5 shoulder dislocates. "
              "Not included, no catalog match: sandbag toss and chase, standing founder, shoulder dislocate, stretches and foam roll.",
        movements=[
            (900, "Barbell Bench Press", 8, "3", "65%, 75%, 85% of the finishing load, then the finishing load less 10 lb", "Finishing load comes from the assessment"),
            (922, "Pull-Up", 8, "30-35% of max reps", "after each bench press round", "Max reps in the assessment are done with a 15 lb backpack"),
            (905, "Push Press", 9, "2", "65%, 75%, 85% of the finishing load, then the finishing load less 10 lb", "Finishing load comes from the assessment"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", "60 lb sandbag", "Substitute for the sandbag getup and keg lift. " + CIRCUIT),
            (921, "Barbell Good Morning", 4, "10", "55 lb", CIRCUIT),
        ],
    ),
    # Football In-Season (411), phase maintenance
    dict(
        name="Football In-Season: Back Squat, Floor Press, Push-Up",
        sport=FLAG_FOOTBALL, phase="maintenance", credit=INSEASON, minutes=30,
        notes="Source: Football In-Season sessions 1, 10 and 19 (strength). 6 rounds of 5 back squats and 5 kettlebell floor presses, each "
              "building to a hard 5. Warm-up is 3 rounds of 8 back squats at 95 lb and 8 hand-release push-ups. "
              "Not included, no catalog match: stretches. Kettlebell floor press is done as Dumbbell Floor Press.",
        movements=[
            (57, "Barbell Back Squat", 6, "5", HARD, "Warm-up is 3 rounds of 8 at 95 lb"),
            (313, "Dumbbell Floor Press", 6, "5", HARD, "Substitute for the kettlebell floor press"),
            (13, "Push-Up", 3, "8", STEADY, HAND_RELEASE + ". Warm-up, 3 rounds"),
        ],
    ),
    dict(
        name="Football In-Season: Thruster, Pull-Up, Push-Up",
        sport=FLAG_FOOTBALL, phase="maintenance", credit=INSEASON, minutes=30,
        notes="Source: Football In-Season sessions 2, 11 and 20 (strength). 6 rounds of 3 thrusters building to a hard 3, with 6 pull-ups. "
              "Warm-up is 3 rounds of 8 thrusters at 65 lb and 8 hand-release push-ups. "
              "Not included, no catalog match: stretches.",
        movements=[
            (1097, "Thruster (Barbell)", 6, "3", HARD, "Warm-up is 3 rounds of 8 at 65 lb"),
            (922, "Pull-Up", 6, "6", "bodyweight", "Alternates with the thrusters"),
            (13, "Push-Up", 3, "8", STEADY, HAND_RELEASE + ". Warm-up, 3 rounds"),
        ],
    ),
    dict(
        name="Football In-Season: Sandbag Keg Lift, Good Morning Chassis Grind",
        sport=FLAG_FOOTBALL, phase="maintenance", credit=INSEASON, minutes=35,
        notes="Source: Football In-Season sessions 3, 12 and 21 (chassis integrity). A 20 minute grind of 5 kneeling plate half moons at 25/35 lb, "
              "5 sandbag keg lifts at 60 lb, 5 sandbag getups alternating shoulders and 10 good mornings at 65 lb. Warm-up is 3 rounds of a "
              "65 lb barbell complex and 5 hand-release push-ups. "
              "Not included, no catalog match: kneeling plate half moon, barbell complex, stretches.",
        movements=[
            (786, "Sandbag Stone-to-Shoulder", 5, "10", GRIND, "Substitute for the sandbag keg lift and the sandbag getup, 5 of each per round, 60 lb"),
            (921, "Barbell Good Morning", 5, "10", GRIND, "65 lb. The 20 minute grind is about 5 rounds"),
            (13, "Push-Up", 3, "5", STEADY, HAND_RELEASE + ". Warm-up, 3 rounds"),
        ],
    ),
    dict(
        name="Football In-Season: One-Sided Deadlift, Sandbag Burpee Chassis Grind",
        sport=FLAG_FOOTBALL, phase="maintenance", credit=INSEASON, minutes=35,
        notes="Source: Football In-Season sessions 6, 15 and 24 (chassis integrity). A 20 minute grind of 5 one-sided dead lifts at 25 lb, "
              "5 seated keg lifts at 16/20 kg, 5 sandbag burpees at 60 lb and 20/20 standing founders. Warm-up is 3 rounds of a 65 lb barbell "
              "complex and 5 hand-release push-ups. "
              "Not included, no catalog match: standing founder, barbell complex, stretches.",
        movements=[
            (108, "Single-Leg Romanian Deadlift", 5, "5", GRIND, "Substitute for the one-sided dead lift, 25 lb"),
            (786, "Sandbag Stone-to-Shoulder", 5, "5", GRIND, "Substitute for the seated keg lift, 16 to 20 kg"),
            (216, "Burpee", 5, "5", GRIND, "Substitute for the sandbag burpee, 60 lb in the source"),
            (13, "Push-Up", 3, "5", STEADY, HAND_RELEASE + ". Warm-up, 3 rounds"),
        ],
    ),
    # Roller Derby Pre-Season (406), phase build
    dict(
        name="Roller Derby: Hinge Lift, Bench Press, Row, Leg Blaster",
        sport=ROLLER_DERBY, phase="build", credit=DERBY, minutes=60,
        notes="Source: Roller Derby Pre-Season sessions 1, 7, 13, 19, 25 and 31 (strength). 5 rounds every 90 seconds of 4 hinge lifts at "
              "85% 1RM (90% in session 25), then 5 rounds of 8 bench presses and 8 barbell bent over rows building to a hard 8 by round 3 "
              "(4 rounds of 12 in sessions 13 and 19, 3 rounds of 15 in sessions 25 and 31). Then the leg blaster: 10 mini rounds in "
              "session 1, falling to 1 full and 8 mini, then 2 full and 6 mini, 3 full and 4 mini, 4 full and 2 mini, and 5 full rounds by "
              "session 31. Sessions 1, 13 and 31 are hinge lift 1RM assessments instead of the 85% work. Warm-up is 3 rounds of 8 hinge lifts "
              f"and 10 push-ups. Leg blaster rows are the mini round: {MINI}. Not included, no catalog match: foam roll complex, stretches.",
        movements=[
            (59, "Conventional Deadlift", 5, "4", "85% 1RM, every 90 seconds", "Substitute for the hinge lift. Session 25 is 90% 1RM"),
            (900, "Barbell Bench Press", 5, "8", HARD, "Hard 8 by round 3. 4 rounds of 12 then 3 rounds of 15 in later sessions"),
            (8, "Barbell Bent-Over Row", 5, "8", HARD, "Hard 8 by round 3. 4 rounds of 12 then 3 rounds of 15 in later sessions"),
            (13, "Push-Up", 3, "10", STEADY, "Warm-up, 3 rounds"),
        ] + blaster(10, "mini"),
    ),
    dict(
        name="Roller Derby: Hinge Lift, Arnold Press, Renegade Row, Leg Blaster",
        sport=ROLLER_DERBY, phase="build", credit=DERBY, minutes=60,
        notes="Source: Roller Derby Pre-Season sessions 4, 10, 16, 22 and 28 (strength). 5 rounds every 90 seconds of 4 hinge lifts at 80% 1RM "
              "(85% in sessions 10 and 22, 90% in session 28), then 5 rounds of 8 Arnold presses and 8 renegade rows building to a hard 8 by "
              "round 3 (4 rounds of 12 in sessions 16 and 22, 3 rounds of 15 in session 28). Then the leg blaster: 10 mini rounds, falling to "
              "1 full and 8 mini, 2 full and 6 mini, 3 full and 4 mini, and 4 full and 2 mini rounds. Warm-up is 3 rounds of 8 hinge lifts "
              f"and 10 push-ups. Leg blaster rows are the mini round: {MINI}. Not included, no catalog match: foam roll complex, stretches.",
        movements=[
            (59, "Conventional Deadlift", 5, "4", "80% 1RM, every 90 seconds", "Substitute for the hinge lift. 85% then 90% in later sessions"),
            (909, "Arnold Press", 5, "8", HARD, "Hard 8 by round 3. 4 rounds of 12 then 3 rounds of 15 in later sessions"),
            (373, "Renegade Row", 5, "8", HARD, "Hard 8 by round 3. 4 rounds of 12 then 3 rounds of 15 in later sessions"),
            (13, "Push-Up", 3, "10", STEADY, "Warm-up, 3 rounds"),
        ] + blaster(10, "mini"),
    ),
    dict(
        name="Roller Derby: Lunge, Good Morning, Sandbag Carry Chassis Grind",
        sport=ROLLER_DERBY, phase="build", credit=DERBY, minutes=50,
        notes="Source: Roller Derby Pre-Season sessions 2, 8, 14, 20, 26 and 32 (work capacity and chassis integrity). Warm-up is 4 rounds of 5 walking "
              "lunges and 10 push-ups. A 20 minute grind of 5 standing Russian twists at 15/25 lb, 5 sandbag good mornings at 40/60 lb (60/80 lb "
              "if possible) and a 60 second sandbag Zercher carry switching shoulders each round. Each session also runs 20 rounds of 15 to 25 "
              "second jingle jangles with 30 seconds rest (session 32 adds 10 rounds of 40 second skater hops), which are not distilled. "
              "Not included, no catalog match: jingle jangle, skater hop, stretches. Sandbag Bear Hug Carry stands in for the Zercher carry "
              "and Barbell Good Morning for the sandbag good morning.",
        movements=[
            (943, "Walking Lunge", 4, "5", STEADY, "Warm-up, 4 rounds"),
            (13, "Push-Up", 4, "10", STEADY, "Warm-up, 4 rounds"),
            (970, "Russian Twist", 5, "5", GRIND, "15/25 lb. The 20 minute grind is about 5 rounds"),
            (921, "Barbell Good Morning", 5, "5", GRIND, "Substitute for the sandbag good morning, 40/60 lb in the source"),
            (328, "Sandbag Bear Hug Carry", 5, "60 s", GRIND, "Substitute for the sandbag Zercher carry, 40/60 lb. Switch shoulders every round in the source"),
        ],
    ),
    dict(
        name="Roller Derby: One-Sided Deadlift, Sandbag Clean and Carry Chassis Grind",
        sport=ROLLER_DERBY, phase="build", credit=DERBY, minutes=50,
        notes="Source: Roller Derby Pre-Season sessions 5, 11, 17, 23 and 29 (work capacity and chassis integrity). Warm-up is 4 rounds of 5 walking "
              "lunges and 10 push-ups. A 20 minute grind of 5 one-sided dead lifts at 55/70 lb, 5 kneeling plate half moons at 25/35 lb, a 60 second "
              "sandbag shoulder carry switching shoulders each round and 5 sandbag clean and presses at 40/60 lb (60/80 lb if possible). Each session "
              "also runs 20 rounds of 30 to 40 second skater hops with 30 seconds rest, which are not distilled. "
              "Not included, no catalog match: skater hop, kneeling plate half moon, stretches.",
        movements=[
            (943, "Walking Lunge", 4, "5", STEADY, "Warm-up, 4 rounds"),
            (13, "Push-Up", 4, "10", STEADY, "Warm-up, 4 rounds"),
            (108, "Single-Leg Romanian Deadlift", 5, "5", GRIND, "Substitute for the one-sided dead lift, 55/70 lb"),
            (571, "Sandbag Shoulder Carry", 5, "60 s", GRIND, "Switch shoulders every round, 40/60 lb, 60/80 lb if possible"),
            (786, "Sandbag Stone-to-Shoulder", 5, "5", GRIND, "Substitute for the sandbag clean and press, 40/60 lb"),
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
        routine_sports.append({"routine_id": rid, "sport_id": spec["sport"]})

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
