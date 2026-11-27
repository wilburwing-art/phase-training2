#!/usr/bin/env python3
"""Distill the Mountain Tactical Institute strength plans into coach.db routines.

Backlog 2026-11e 3.11. Sources are four MTI plans: Hypertrophy For Skinny Guys (294, 35
sessions), High Rep Kettlebell Snatch Training Plan (307, 35), Kettlebell Strength - TLU
Progression (301, 20) and Kettlebell Strength - Working Strength (302, 41).

Phase follows `AuthoredRoutine.phaseLabels(for:)`: none of the four plans carries a season
label, so every routine is `build`.

Sport tags: Hypertrophy routines are tagged bodybuilding (639). The three kettlebell plans are
tagged kettlebell-sport (640). The family root strength-fitness-sports (630) is not tagged.

Shapes that repeat across weeks are one routine, written from a mid-cycle session, with the
progression in its notes. Each routine is credited to the plan it comes from.

Not distilled:
- Assessments: the 90 second max snatch tests (307 sessions 1, 16, 31), the one minute max rep
  front squat, floor press, swing and sit-up tests (301 sessions 5 and 20) and the 3 mile run
  tests (302 sessions 4, 19, 34).
- Runs and rucks: the 1 mile intervals (302), the optional ruck or run days (302), the run that
  closes each 307 Wednesday and the 3 mile run of 307 session 32.
- Snatch interval and high rep snatch days (307 Mondays, Tuesdays, Thursdays and Fridays): the
  catalog holds one snatch row and the warm-up adds only the push-up, which is two catalog
  exercises. The snatch work is noted inside the 301 and 302 routines that carry it.
- 307 sessions 33, 34 and 35: total rest.
- Work capacity days built on shuttle sprints, prone to sprints and 200 m runs (301 sessions 2,
  4, 12, 14; 302 sessions 2, 7, 17, 22, 32): fewer than three catalog exercises once the
  sprints, slashers, pass throughs, keg lifts and Mr. Spectaculars are dropped. 302 sessions 12
  and 27 are kept as one routine.
- 301 strength sessions 3, 8 and 13 (military press, Bulgarian split squat, Craig special and
  Mr. Spectacular days): the same press, pull and lunge pattern as the routines kept, with no
  further catalog exercises.
- Hypertrophy session 31 and 32 (unload week): same shapes at fewer rounds, noted in the routines.
- Every stretch, foam roll, hip mobility, shoulder dislocate and instep block.

Idempotent: a routine whose slug already exists is skipped.
Run:  python3 scripts/db/distill_strength.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

BODYBUILDING = (639,)
KETTLEBELL = (640,)

HYPER = "MTI Hypertrophy For Skinny Guys (distilled)"
TLU = "MTI Kettlebell Strength - TLU Progression (distilled)"
WORKING = "MTI Kettlebell Strength - Working Strength (distilled)"
SNATCH = "MTI High Rep Kettlebell Snatch Training Plan (distilled)"

RAMP = "increase load rapidly each round until the last set is hard but doable"
WS = "reach the hard but doable load by round 3 and keep it through round 6"
STEADY = "steady"
GRIND = "work steadily, not frantically"
BW = "bodyweight"
HR = "Hand-release: chest to the floor and hands lifted each rep"
KBSUB = "Substitute for the kettlebell version, no catalog row"


ROUTINES = [
    # Hypertrophy For Skinny Guys (294)
    dict(
        name="Hypertrophy: Lunge and Bench, Front Squat and Press, Back Squat and Chin-Up",
        phase="build", credit=HYPER, sports=BODYBUILDING, minutes=60,
        notes="Source: Hypertrophy For Skinny Guys total body sessions 4, 9, 14, 19 and 24 (week 4 loading shown). Three blocks of "
              "paired lifts. 6 rounds of 8 walking lunges and 8 bench presses, 5 rounds of 12 front squats and 12 presses, 4 rounds "
              "of 15 back squats and a 4 to 8 chin-up ladder. Load rises quickly each round until the target reps are hard but "
              "doable. Squat, lunge and press variations rotate through the weeks. Week 7 is an unload week with fewer rounds. "
              "Not included, no catalog match: the barbell complex warm-up, instep, lat and pec stretches and the kneeling curl to press.",
        movements=[
            (943, "Walking Lunge", 6, "8", RAMP, "Hold dumbbells or a barbell"),
            (900, "Barbell Bench Press", 6, "8", RAMP, "Paired with the lunge each round"),
            (450, "Front Squat (Barbell)", 5, "12", RAMP, "The source also uses dumbbell front squats"),
            (905, "Push Press", 5, "12", RAMP, "Paired with the front squat. Substitute for the kneeling curl to press in sessions 4 and 14"),
            (57, "Barbell Back Squat", 4, "15", RAMP, "Paired with a 4 to 8 chin-up ladder or renegade rows"),
            (923, "Chin-Up", 4, "4-8", STEADY, "Strict. Pull-ups in some sessions"),
        ],
    ),
    dict(
        name="Hypertrophy: Hinge and Floor Press, Back Squat and Arnold Press, Front Squat and Pull-Up",
        phase="build", credit=HYPER, sports=BODYBUILDING, minutes=60,
        notes="Source: Hypertrophy For Skinny Guys total body sessions 1, 6, 11, 16, 21 and 26. Three blocks. 6 rounds of 10 hinge lifts "
              "and 10 floor presses, 5 rounds of 12 back squats and 12 seated Arnold presses, 4 rounds of 15 front squats and a 3 to 6 "
              "pull-up ladder. Reps drop from 12 or 15 to 8 and rise again through the weeks as the load increases each round. "
              "Not included, no catalog match: the barbell complex warm-up, shoulder dislocates, pigeon, hip flexor, instep, lat and pec stretches.",
        movements=[
            (59, "Conventional Deadlift", 6, "10", RAMP, "Substitute for the hinge lift"),
            (313, "Dumbbell Floor Press", 6, "10", RAMP, "Substitute for the kettlebell floor press. Dumbbell bench press in some sessions"),
            (57, "Barbell Back Squat", 5, "12", RAMP, "Box squats in some sessions"),
            (909, "Arnold Press", 5, "12", RAMP, "Seated in the source. Dumbbell military press in some sessions"),
            (450, "Front Squat (Barbell)", 4, "15", RAMP, "Paired with the pull-up ladder"),
            (922, "Pull-Up", 4, "3-6", STEADY, "Strict. Mixed grip 2 to 4 in some sessions"),
        ],
    ),
    dict(
        name="Hypertrophy: Upper Body Press, Curl and Row Supersets",
        phase="build", credit=HYPER, sports=BODYBUILDING, minutes=55,
        notes="Source: Hypertrophy For Skinny Guys upper body sessions 2, 7, 12, 17, 22 and 27 (week 3 shown). Warm-up is 3 rounds of 10 "
              "hand-release push-ups, 3 to 6 chin-ups, 5 push-ups and 1 to 2 pull-ups. Then 6 rounds of 8 military presses and 8 "
              "alternating dumbbell curls, and 4 rounds of 15 bench presses and 10 renegade rows. Load rises each round until the "
              "target reps are hard but doable. Bench press, bent over row, floor press and Arnold press rotate through the weeks. "
              "Not included, no catalog match: gorilla complex, shoulder dislocates, power curl, hip flexor, instep, lat and pec stretches.",
        movements=[
            (13, "Push-Up", 3, "10", STEADY, HR + ". Warm-up, 3 rounds"),
            (923, "Chin-Up", 3, "3-6", STEADY, "Warm-up, 3 rounds. Pull-ups 1 to 2 reps"),
            (1095, "Strict Military Press (Barbell)", 6, "8", RAMP, "Dumbbell military press in some sessions"),
            (948, "Dumbbell Curl", 6, "8", RAMP, "Alternating"),
            (900, "Barbell Bench Press", 4, "15", RAMP, "Dumbbell bench press or kettlebell floor press in some sessions"),
            (373, "Renegade Row", 4, "10", RAMP, "Barbell bent over row in some sessions"),
        ],
    ),
    dict(
        name="Hypertrophy: Chassis Integrity Grind",
        phase="build", credit=HYPER, sports=BODYBUILDING, minutes=35,
        notes="Source: Hypertrophy For Skinny Guys chassis integrity sessions 3, 8, 13, 18, 23 and 28 (twice a week core work). Warm-up is "
              "10 squats, 10 push-ups, 5 in-place lunges and 10 sit-ups. Then an 18 to 20 minute grind of 5 standing Russian twists "
              "at 10 or 25 lb, 5 seated keg lifts, 5 pull-up bar heel taps and 15 kneeling founders each side, steady not frantic, "
              "followed by 2 rounds of stretches. "
              "Not included, no catalog match: seated keg lift, kneeling founder, shoulder dislocates, stretches.",
        movements=[
            (1088, "Squat (Bodyweight)", 1, "10", STEADY, "Warm-up"),
            (13, "Push-Up", 1, "10", STEADY, "Warm-up"),
            (1051, "Lunge (Bodyweight)", 1, "5", STEADY, "Warm-up, in place"),
            (969, "Sit-Up", 1, "10", STEADY, "Warm-up"),
            (970, "Russian Twist", 4, "5", GRIND, "10 or 25 lb. 18 minute grind"),
            (376, "Hanging Leg Raise", 4, "5", GRIND, "Substitute for the pull-up bar heel tap"),
        ],
    ),
    # Kettlebell Strength - TLU Progression (301)
    dict(
        name="Kettlebell TLU: Snatch and Burpee, Pull-Up and Press, Clapping Push-Up Strength",
        phase="build", credit=TLU, sports=KETTLEBELL, minutes=50,
        notes="Source: Kettlebell Strength TLU Progression session 11 (strength, week 3). Warm-up is 3 rounds of 6 snatches, 6 goblet "
              "squats and 2 to 3 pull-ups. Then 8 rounds of 3 two-handed snatches with a burpee, 6 rounds of 3 to 5 weighted "
              "mixed grip pull-ups with 5 one-arm military presses (load rises each round until the reps are hard but doable), 5 "
              "rounds for time of 6 snatches and 3 to 6 clapping push-ups, and a farmer's carry that grows from 60 to 105 seconds "
              "across the cycle. Presses are each arm and snatches alternate. "
              "Not included, no catalog match: shoulder dislocates, shoulder sweep, instep, lat and pec, hip flexor and frog stretches.",
        movements=[
            (60, "Goblet Squat", 3, "6", STEADY, "Warm-up, 8/12 kg"),
            (785, "Kettlebell Snatch Sets", 8, "3", RAMP, "Two-handed in the source. Warm-up 6 reps, then 5 rounds for time of 6"),
            (216, "Burpee", 8, "1", "explosive", "One burpee straight after each set of snatches"),
            (922, "Pull-Up", 6, "3-5", RAMP, "Mixed grip, weighted"),
            (15, "Dumbbell Overhead Press", 6, "5", RAMP, "Substitute for the one-arm kettlebell military press, each arm"),
            (13, "Push-Up", 5, "3-6", "for time", "Clapping in the source"),
            (64, "Farmer's Carry", 1, "60-105 s", STEADY, "24 or 28 kg, time grows across the cycle"),
        ],
    ),
    dict(
        name="Kettlebell TLU: Clean and Thruster, Row, Floor Press and Split Squat Strength",
        phase="build", credit=TLU, sports=KETTLEBELL, minutes=55,
        notes="Source: Kettlebell Strength TLU Progression sessions 6 and 18 (strength). Warm-up is 3 rounds of 5 hang squat clean and "
              "push presses at 8 or 12 kg and 5 walking lunges each leg. Then 8 rounds of 3 hang squat clean and push presses with a "
              "burpee, 6 rounds of 5 one-arm rows with 5 floor presses, and 6 rounds of 8 Bulgarian split squats with 8 one-leg poor "
              "man's leg curls. Load rises each round until the reps are hard but doable. Session 6 swaps the first block for "
              "shoulder hold lunges with a jumping lunge and adds a 25 rep Curtis P for time. "
              "Not included, no catalog match: Curtis P, shoulder dislocates, toe touch complex, foam roll, stretches.",
        movements=[
            (1164, "Kettlebell Walking Lunge", 3, "5", STEADY, "Warm-up, each leg. The shoulder hold lunge in session 6"),
            (1098, "Thruster (Kettlebell)", 8, "3", RAMP, "Substitute for the hang squat clean and push press"),
            (216, "Burpee", 8, "1", "explosive", "One burpee straight after each set"),
            (1125, "Kettlebell Single-Arm Row", 6, "5", RAMP, "Each arm"),
            (313, "Dumbbell Floor Press", 6, "5", RAMP, "Substitute for the kettlebell floor press"),
            (1162, "Kettlebell Bulgarian Split Squat", 6, "8", RAMP, "Each leg"),
            (102, "Nordic Hamstring Curl", 6, "8", BW, "Substitute for the one-leg poor man's leg curl. Use the reps you can control"),
        ],
    ),
    dict(
        name="Kettlebell TLU: Snatch, Front Squat and Floor Press AMRAP with Core Circuit",
        phase="build", credit=TLU, sports=KETTLEBELL, minutes=45,
        notes="Source: Kettlebell Strength TLU Progression sessions 7 and 17 (work capacity and core, week 2 and 4). Warm-up is 3 rounds "
              "of 5 snatches, 10 goblet squats and 10 push-ups at 8 or 12 kg. Then a 10 minute AMRAP of 4 snatches, 4 front squats, 4 "
              "floor presses and 2 to 4 chin-ups (session 17 swaps the front squat for jumping lunges). Then 4 rounds of 15 toes to "
              "sky, a 75 second farmer's carry, 5 kneeling keg lifts and 10 face down back extensions. "
              "Not included, no catalog match: toes to sky (Hanging Leg Raise stands in), kneeling keg lift, stretches, foam roll.",
        movements=[
            (60, "Goblet Squat", 3, "10", STEADY, "Warm-up, 8/12 kg"),
            (785, "Kettlebell Snatch Sets", 3, "4", "AMRAP", "10 minute AMRAP, 8/12 kg. Warm-up 5 reps"),
            (1159, "Dumbbell Front Squat", 3, "4", "AMRAP", KBSUB),
            (313, "Dumbbell Floor Press", 3, "4", "AMRAP", "Substitute for the kettlebell floor press"),
            (923, "Chin-Up", 3, "2-4", "AMRAP", "Strict"),
            (376, "Hanging Leg Raise", 4, "15", STEADY, "Substitute for toes to sky"),
            (64, "Farmer's Carry", 4, "75 s", STEADY, "24 or 28 kg. Grows to 90 and 105 seconds"),
            (983, "Back Extension", 4, "10", BW, "Face down"),
        ],
    ),
    dict(
        name="Kettlebell TLU: Clean and Press Ladder with Sit-Up and Carry Circuit",
        phase="build", credit=TLU, sports=KETTLEBELL, minutes=45,
        notes="Source: Kettlebell Strength TLU Progression sessions 9 and 19 (work capacity). Warm-up is 3 rounds of 5 clean and push "
              "presses at 8 or 12 kg, 10 goblet squats and 10 push-ups. Then a 10 to 1 ladder for time of clean and push press at "
              "12 or 20 kg, 20 inch box jumps, sit-ups, jumping lunges and hand-release push-ups. Then 5 rounds of 5 one-arm sit-ups, a "
              "75 second farmer's carry, 10 slashers and a 30 second side bridge. "
              "Not included, no catalog match: slasher, stretches, foam roll.",
        movements=[
            (60, "Goblet Squat", 3, "10", STEADY, "Warm-up, 8/12 kg"),
            (1098, "Thruster (Kettlebell)", 10, "10-1", "for time", "Substitute for the clean and push press, 12/20 kg. Ladder from 10 down to 1"),
            (49, "Box Jump", 10, "10-1", "for time", "20 inch box"),
            (969, "Sit-Up", 10, "10-1", "for time", "Same ladder. 5 one-arm weighted sit-ups per round in the finisher"),
            (130, "Split Squat Jump", 10, "10-1", "for time", "Jumping lunges"),
            (13, "Push-Up", 10, "10-1", "for time", HR),
            (64, "Farmer's Carry", 5, "75 s", STEADY, "24 or 28 kg"),
        ],
    ),
    dict(
        name="Kettlebell TLU: Working Strength Percentage Day",
        phase="build", credit=TLU, sports=KETTLEBELL, minutes=40,
        notes="Source: Kettlebell Strength TLU Progression sessions 10 and 15 (working strength, week 2 and 3). Warm-up is 3 rounds of 8 "
              "goblet squats, 8 floor presses and 8 swings at 8 or 12 kg for the press and 16 or 20 kg for the swing. The "
              "loading comes from the session 5 one minute max rep tests: 5 rounds every 90 seconds of front squats, then floor "
              "presses, then swings, then sit-ups, each at 35% (session 10) or 40% (session 15) of the max reps scored, with the same "
              "kettlebell as the test. Close with a 75 second farmer's carry. "
              "Not included: the assessments, the stretches.",
        movements=[
            (60, "Goblet Squat", 3, "8", STEADY, "Warm-up, 8/12 kg"),
            (1159, "Dumbbell Front Squat", 5, "35-40% of max reps", "every 90 seconds", KBSUB + ". Use the load from the max rep test"),
            (313, "Dumbbell Floor Press", 5, "35-40% of max reps", "every 90 seconds", "Substitute for the kettlebell floor press"),
            (61, "Kettlebell Swing", 5, "35-40% of max reps", "every 90 seconds", "16/20 kg"),
            (969, "Sit-Up", 5, "35-40% of max reps", "every 90 seconds", "Kettlebell held to the chest"),
            (64, "Farmer's Carry", 1, "75 s", STEADY, "24 or 28 kg"),
        ],
    ),
    # Kettlebell Strength - Working Strength (302)
    dict(
        name="Kettlebell Working Strength: Front Squat, Press, Clean and Getup Circuits",
        phase="build", credit=WORKING, sports=KETTLEBELL, minutes=50,
        notes="Source: Kettlebell Working Strength Monday sessions 1, 6, 11, 16, 21, 26 and 31 (strength). Warm-up is 2 rounds of 10 "
              "goblet squats, 10 hand-release push-ups and 10 swings at 12 kg. Then five circuits of 6 rounds. Front squat with a "
              "pull-up, one-arm press with a chin-up, clean with a renegade row, clean and strict press, and a corrective getup "
              "with a mixed grip pull-up. Reps per round rise from 4 to 6 over three weeks with the same loads, then drop to 3 "
              "and the load goes up a kettlebell size. Reach the hard but doable load by round 3 and hold it through round 6. "
              "Later weeks use a weighted pull-up with a 15 or 25 lb pack. Work through the circuits steadily with no stretch breaks. "
              "Not included, no catalog match: hip flexor, instep, lat and pec stretches.",
        movements=[
            (60, "Goblet Squat", 2, "10", STEADY, "Warm-up, 12 kg"),
            (13, "Push-Up", 2, "10", STEADY, HR + ". Warm-up"),
            (61, "Kettlebell Swing", 2, "10", STEADY, "Warm-up, 12 kg"),
            (1159, "Dumbbell Front Squat", 6, "4-6", WS, KBSUB),
            (922, "Pull-Up", 6, "2-8", STEADY, "Strict, weighted with a 15 or 25 lb pack in later weeks"),
            (15, "Dumbbell Overhead Press", 6, "4-6", WS, "Substitute for the one-arm kettlebell press, each arm"),
            (923, "Chin-Up", 6, "3-8", STEADY, "Strict, weighted in later weeks"),
            (1036, "Kettlebell Clean", 6, "4-6", WS, "Two-handed in the source. Also the clean and strict press circuit"),
            (373, "Renegade Row", 6, "4-6", STEADY, "25/35 lb dumbbells or 12/16 kg kettlebells"),
            (119, "Turkish Get-Up", 6, "1", WS, "Corrective getup in the source"),
        ],
    ),
    dict(
        name="Kettlebell Working Strength: Lunge, Military Press, Snatch and Thruster Circuits",
        phase="build", credit=WORKING, sports=KETTLEBELL, minutes=50,
        notes="Source: Kettlebell Working Strength Wednesday sessions 3, 8, 13, 18, 23, 28 and 33 (strength). Warm-up is 2 rounds of 10 "
              "goblet squats, 10 hand-release push-ups and 10 swings at 12 kg. Then five circuits of 6 rounds. Shoulder hold lunge "
              "with a horizontal pull-up, military press with a kettlebell row, two-handed snatch with a renegade row, hang squat "
              "clean to thruster, and a corrective getup with a mixed grip pull-up. Reps rise from 4 to 6 over three weeks with the "
              "same loads, then drop and the load goes up a kettlebell size. Reach the hard but doable load by round 3 and hold it "
              "through round 6. "
              "Not included, no catalog match: hip flexor, instep, lat and pec stretches.",
        movements=[
            (60, "Goblet Squat", 2, "10", STEADY, "Warm-up, 12 kg"),
            (61, "Kettlebell Swing", 2, "10", STEADY, "Warm-up, 12 kg"),
            (1164, "Kettlebell Walking Lunge", 6, "2-5", WS, "Substitute for the shoulder hold lunge, each leg"),
            (135, "Inverted Row", 6, "3-10", STEADY, "Horizontal pull-up in the source"),
            (15, "Dumbbell Overhead Press", 6, "4-6", WS, "Substitute for the kettlebell military press"),
            (1125, "Kettlebell Single-Arm Row", 6, "4-6", WS, "Horizontal row in the source"),
            (785, "Kettlebell Snatch Sets", 6, "3-5", WS, "Two-handed in the source"),
            (373, "Renegade Row", 6, "4-6", STEADY, "25/35 lb dumbbells or 12/16 kg kettlebells"),
            (1098, "Thruster (Kettlebell)", 6, "3-5", WS, "Hang squat clean to thruster in the source"),
            (119, "Turkish Get-Up", 6, "1", WS, "Corrective getup in the source"),
            (922, "Pull-Up", 6, "2-8", STEADY, "Mixed grip"),
        ],
    ),
    dict(
        name="Kettlebell Working Strength: Pull-Up, Floor Press and Clean Circuits",
        phase="build", credit=WORKING, sports=KETTLEBELL, minutes=50,
        notes="Source: Kettlebell Working Strength Friday sessions 5, 10, 15, 20, 25, 30 and 35 (strength). Warm-up is 2 rounds of 10 "
              "goblet squats, 10 hand-release push-ups and 10 swings at 12 kg. Then five circuits of 6 rounds. Craig special with a "
              "pull-up, floor press with a chin-up, clean with a renegade row, hang squat clean and push press, and a corrective "
              "getup with a mixed grip pull-up. Floor press reps run 8, 10, 12 and back to 8 as the load climbs. Later weeks use "
              "weighted pull-ups with a 15 or 25 lb pack. "
              "Not included, no catalog match: Craig special, hip flexor, instep, lat and pec stretches.",
        movements=[
            (60, "Goblet Squat", 2, "10", STEADY, "Warm-up, 12 kg"),
            (13, "Push-Up", 2, "10", STEADY, HR + ". Warm-up"),
            (61, "Kettlebell Swing", 2, "10", STEADY, "Warm-up, 12 kg"),
            (922, "Pull-Up", 6, "2-8", STEADY, "Strict, weighted in later weeks. Paired with the Craig special"),
            (313, "Dumbbell Floor Press", 6, "8-12", WS, "Substitute for the kettlebell floor press"),
            (923, "Chin-Up", 6, "3-8", STEADY, "Strict, weighted in later weeks"),
            (1036, "Kettlebell Clean", 6, "4-6", WS, "Two-handed in the source"),
            (373, "Renegade Row", 6, "3-6", STEADY, "25/35 lb dumbbells or 12/16 kg kettlebells"),
            (1098, "Thruster (Kettlebell)", 6, "2-4", WS, "Substitute for the hang squat clean and push press"),
            (119, "Turkish Get-Up", 6, "1", WS, "Corrective getup in the source"),
        ],
    ),
    dict(
        name="Kettlebell Working Strength: Lunge, Push-Up and Burpee Grind",
        phase="build", credit=WORKING, sports=KETTLEBELL, minutes=40,
        notes="Source: Kettlebell Working Strength Tuesday sessions 12 and 27 (work capacity and chassis integrity). Warm-up is 3 rounds "
              "of 5 walking lunges, 5 push-ups, 3 jumping lunges and 5 clapping push-ups. Then 10 rounds every 60 seconds of 4 "
              "touch, jump, touch and 5 or 6 burpees. Then a 15 minute grind of 5 dumbbell pass throughs, 10 slasher to halo and 3 "
              "to 5 pull-up bar heel taps, steady not frantic. "
              "Not included, no catalog match: touch, jump, touch, dumbbell pass through, slasher to halo, foam roll complex. The "
              "other Tuesday shapes (prone to sprints, 150 m shuttles) are dropped.",
        movements=[
            (943, "Walking Lunge", 3, "5", STEADY, "Warm-up, 3 rounds"),
            (13, "Push-Up", 3, "5", STEADY, "Warm-up, 3 rounds. Clapping push-ups 5 per round"),
            (130, "Split Squat Jump", 3, "3", STEADY, "Jumping lunge, warm-up"),
            (216, "Burpee", 10, "5-6", "every 60 seconds", "10 rounds"),
            (376, "Hanging Leg Raise", 4, "3-5", GRIND, "Substitute for the pull-up bar heel tap. 15 minute grind"),
        ],
    ),
    # High Rep Kettlebell Snatch Training Plan (307)
    dict(
        name="Kettlebell Snatch Plan: Push-Up, Pull-Up and Lunge Bodyweight Grind",
        phase="build", credit=SNATCH, sports=KETTLEBELL, minutes=40,
        notes="Source: High Rep Kettlebell Snatch plan Wednesday sessions 3, 18 and 32 (bodyweight strength and endurance). Warm-up is 3 "
              "rounds of 5 walking lunges, 5 hand-release push-ups and 1 pull-up. Then a 20 minute grind that repeats 3 push-ups, 3 "
              "hand-release push-ups and 3 clapping push-ups, then 1 to 2 pull-ups, 1 to 2 mixed grip pull-ups and 1 to 2 chin-ups, "
              "then 3 in-place lunges, 3 walking lunges and 3 jumping lunges, steady not frantic. The source follows with a 2 to 3 mile "
              "moderate run, which is dropped. ",
        movements=[
            (943, "Walking Lunge", 3, "5", STEADY, "Warm-up, 3 rounds. Also 3 per grind round"),
            (13, "Push-Up", 3, "5", STEADY, HR + ". Grind also holds standard and clapping push-ups, 3 each"),
            (922, "Pull-Up", 3, "1-2", STEADY, "Grind also holds mixed grip pull-ups, 1 to 2"),
            (923, "Chin-Up", 3, "1-2", STEADY, "Grind only"),
            (1051, "Lunge (Bodyweight)", 3, "3", STEADY, "In place, grind only"),
            (130, "Split Squat Jump", 3, "3", STEADY, "Jumping lunge, grind only"),
        ],
    ),
    dict(
        name="Kettlebell Snatch Plan: Push-Up, Squat Jump and Broad Jump Bodyweight Grind",
        phase="build", credit=SNATCH, sports=KETTLEBELL, minutes=40,
        notes="Source: High Rep Kettlebell Snatch plan Wednesday sessions 8 and 23 (bodyweight strength and endurance). Warm-up is 3 "
              "rounds of 5 walking lunges, 5 hand-release push-ups and 1 pull-up. Then a 20 minute grind that repeats 2 to 4 hand-release "
              "push-ups, 4 alligator push-ups each side, 2 to 4 clapping push-ups, then a 1 to 2 rep rope climb pull-up, then 6 squats, "
              "3 squat jumps and 3 broad jumps, steady not frantic. The source follows with a 2 to 3 mile moderate run, which is dropped. "
              "Not included, no catalog match: alligator push-up, Tarzan pull-up on a rope (Pull-Up stands in).",
        movements=[
            (943, "Walking Lunge", 3, "5", STEADY, "Warm-up, 3 rounds"),
            (13, "Push-Up", 3, "2-4", STEADY, HR + ". Alligator and clapping push-ups also in the grind"),
            (922, "Pull-Up", 3, "1-2", STEADY, "Substitute for the Tarzan pull-up on a rope"),
            (1088, "Squat (Bodyweight)", 3, "6", STEADY, "Grind"),
            (1034, "Jump Squat", 3, "3", STEADY, "Grind"),
            (52, "Broad Jump", 3, "3", STEADY, "Grind"),
        ],
    ),
    dict(
        name="Kettlebell Snatch Plan: Heel Tap and Pull-Up Bodyweight Grind",
        phase="build", credit=SNATCH, sports=KETTLEBELL, minutes=35,
        notes="Source: High Rep Kettlebell Snatch plan Wednesday sessions 13 and 28 (bodyweight strength and endurance). Warm-up is 3 "
              "rounds of 5 walking lunges, 5 hand-release push-ups and 1 pull-up. Then a 20 minute grind of 5 bodyweight Rob Shauls and "
              "3 to 6 pull-up bar heel taps, steady not frantic. The source follows with a 2.5 to 3 mile moderate run, which is "
              "dropped. Not included, no catalog match: bodyweight Rob Shaul, instep stretch.",
        movements=[
            (943, "Walking Lunge", 3, "5", STEADY, "Warm-up, 3 rounds"),
            (13, "Push-Up", 3, "5", STEADY, HR + ". Warm-up, 3 rounds"),
            (922, "Pull-Up", 3, "1", STEADY, "Warm-up, 3 rounds"),
            (376, "Hanging Leg Raise", 5, "3-6", GRIND, "Substitute for the pull-up bar heel tap. 20 minute grind"),
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
