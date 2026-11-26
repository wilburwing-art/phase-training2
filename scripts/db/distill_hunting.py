#!/usr/bin/env python3
"""Distill the Mountain Tactical Institute hunting plans into coach.db routines.

Backlog 2026-11e 3.10. Sources are five MTI plans: Backcountry Hunting Base (204, 35
sessions), Backcountry Hunting Build 1 (205) and Build 2 (206), Backcountry Big Game Hunting
Preseason V5 (203, 48 sessions) and Whitetail Deer Hunting Preseason Training Plan (208, 30
sessions).

Phase follows `AuthoredRoutine.phaseLabels(for:)`: Hunting Base is `base`; Build 1, Build 2,
Big Game Preseason V5 and Whitetail Preseason are `build`.

Every routine is tagged to fishing-hunting (720), backcountry-hunting (724) and bow-hunting
(723). fly-fishing and spearfishing are not tagged.

Shapes that repeat word for word inside a plan are one routine, with the progression in its
notes. Each routine is credited to the plan it comes from.

Not distilled:
- Runs: the moderate pace runs, recovery runs, endurance intervals and running assessments
  (Base sessions 1, 6, 11, 16, 26 and 31, Build 1 and Build 2 running days, Big Game recovery runs).
- Rucks and drags with no strength block: the heavy rucks, the stand approach ruck and the post
  harvest pack out or sled drag days. The PM ruck of the Big Game two a day sessions is dropped
  from the routine that carries the AM strength block.
- Mini events: the 60 to 90 minute events in Whitetail and the 90 to 210 minute events in Big Game.
- Step up days with fewer than three catalog exercises: Build 1 sessions 11, 16 and 21 (step
  ups plus a sandbag circuit of getup run, clean and press, slasher or toss and chase, which
  leaves two catalog matches), Build 2 session 34 (step ups only).
- Base session 35: the warm-up and the step up block only, the same block as the Base weighted step
  up routine, so it is noted there.
- Strength assessments: Build 1 sessions 2, 17 and 32 (1RM back squat and bench press, max
  pull ups), Whitetail sessions 2, 14 and 26 (max rep sandbag squat, push up and pull up in two
  minutes) and the Big Game 30 minute max step up tests (sessions 1, 19 and 37). Their loading
  schemes are noted inside the routine they feed.
- Shuttles and sprints: the 150 m and 300 m shuttles that close the Base work capacity days,
  the prone to 40 ft sprints, 40 ft shuttles and 200 m runs inside the AMRAPs.
- Rest days and every stretch, foam roll, hip mobility and instep block.

Idempotent: a routine whose slug already exists is skipped.
Run:  python3 scripts/db/distill_hunting.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

HUNTING_SPORTS = (720, 724, 723)

BASE = "MTI Backcountry Hunting Base (distilled)"
BUILD1 = "MTI Backcountry Hunting Build 1 (distilled)"
BUILD2 = "MTI Backcountry Hunting Build 2 (distilled)"
BIGGAME = "MTI Backcountry Big Game Hunting Preseason V5 (distilled)"
WHITETAIL = "MTI Whitetail Deer Hunting Preseason Training Plan (distilled)"

HARD = "increase load each round until the last set is hard but doable"
STEADY = "steady"
GRIND = "work through the rounds steadily, not frantically"
BW = "bodyweight"
BAG = "40 lb or 60 lb sandbag"
HAND_RELEASE = "Hand-release: chest to the floor and hands lifted each rep"
KEG = "Substitute for the keg lift"
GETUP = "Substitute for the sandbag getup"
STEPUP = "Backpack at 20 to 40 lb in the source, 16 to 18 inch box or bench. Each step counts as a rep"


def blaster(rounds, size, rest="Rest 30 seconds after each round"):
    """The leg blaster as its catalog parts. `size` is "mini" or "full"."""
    big, small = {"mini": ("10", "5"), "full": ("20", "10")}[size]
    return [
        (1088, "Squat (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 1"),
        (1051, "Lunge (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 2. In place, alternate legs, each step is a rep"),
        (130, "Split Squat Jump", rounds, big, STEADY, "Leg blaster, part 3: jumping lunges"),
        (1034, "Jump Squat", rounds, small, STEADY, f"Leg blaster, part 4. {rest}"),
    ]


ROUTINES = [
    # Backcountry Hunting Base (204), phase base
    dict(
        name="Hunting Base: Leg Blaster, Push-Up and Pull-Up Work Capacity",
        phase="base", credit=BASE, minutes=40,
        notes="Source: Backcountry Hunting Base sessions 2, 7, 12, 17, 22, 27 and 32 (strength and work capacity). Each round is a leg "
              "blaster (squats, in-place lunges, jumping lunges, squat jumps), hand-release push-ups and pull-ups. Early sessions run 8 "
              "then 10 rounds of the mini blaster with 5 push-ups and a 1 to 3 pull-up ladder. Sessions 12 and 17 mix 3 to 5 full "
              "blaster rounds with mini rounds. Sessions 27 and 32 run 6 rounds of the full blaster with 9 to 11 push-ups and 3 to 7 "
              "pull-ups. Not included: the 150 m and 300 m shuttle intervals that close each session, and the stretches.",
        movements=blaster(8, "mini") + [
            (13, "Push-Up", 8, "5", STEADY, HAND_RELEASE + ". Rises to 9 to 11 in later sessions"),
            (922, "Pull-Up", 8, "1-3", STEADY, "Strict. The ladder rises to 3 to 7 reps in later sessions"),
        ],
    ),
    dict(
        name="Hunting Base: Leg Blaster, Chin-Up and Sandbag Getup Grind",
        phase="base", credit=BASE, minutes=45,
        notes="Source: Backcountry Hunting Base sessions 4, 9 and 14 (strength and chassis integrity). 8 then 10 rounds of the mini "
              "blaster, 5 hand-release push-ups and a 3 to 5 chin-up ladder, then a 12 to 15 minute grind of 5 sandbag getups "
              "(alternating shoulders), 5 sandbag keg lifts and a 60 second sandbag Zercher carry at 40 or 60 lb. Session 14 raises the "
              "chin-ups to 4 to 6 and splits the blaster into 3 full rounds then 4 mini rounds. "
              "Not included, no catalog match: toe touch complex, shoulder dislocates, stretches.",
        movements=blaster(8, "mini") + [
            (13, "Push-Up", 8, "5", STEADY, HAND_RELEASE),
            (923, "Chin-Up", 8, "3-5", STEADY, "Strict ladder, higher in later sessions"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, GETUP + " and the keg lift, 40/60 lb. 12 to 15 minute grind"),
            (328, "Sandbag Bear Hug Carry", 4, "60 s", GRIND, "Substitute for the sandbag Zercher carry, 40/60 lb"),
        ],
    ),
    dict(
        name="Hunting Base: Leg Blaster, Chin-Up and Sandbag Clean and Press Grind",
        phase="base", credit=BASE, minutes=50,
        notes="Source: Backcountry Hunting Base sessions 19, 24 and 29 (strength and chassis integrity). 5 to 6 rounds of the full "
              "leg blaster, 9 to 10 hand-release push-ups and a 5 to 8 chin-up ladder, then a 15 to 18 minute grind of 5 sandbag clean "
              "and presses, 5 sandbag clean and runs and a 60 second sandbag bear hug walk at 40 or 60 lb. "
              "Not included, no catalog match: toe touch complex, shoulder dislocates, stretches.",
        movements=blaster(5, "full") + [
            (13, "Push-Up", 5, "9", STEADY, HAND_RELEASE + ". 10 in later sessions"),
            (923, "Chin-Up", 5, "5-7", STEADY, "Strict ladder, 6 to 8 in later sessions"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, "Substitute for the sandbag clean and press and clean and run, 40/60 lb"),
            (328, "Sandbag Bear Hug Carry", 4, "60 s", GRIND, "Bear hug walk, 40/60 lb"),
        ],
    ),
    dict(
        name="Hunting Base: Weighted Step-Up Hike, Founder and Good Morning Circuit",
        phase="base", credit=BASE, minutes=55,
        notes="Source: Backcountry Hunting Base sessions 5, 10, 15, 20, 25 and 30 (uphill endurance under load with chassis work). "
              "Warm-up is 4 rounds of 10 squats and 10 push-ups with a set of step-ups. Then 300 step-ups, rising to 450 over the "
              "block, in a 20 to 30 lb backpack at a moderate pace. Then 2 to 3 rounds of standing founders, 5 sandbag cross cleans, "
              "10 sandbag good mornings and 10 face down back extensions. Session 35 repeats the warm-up and the step-up block at 500 "
              "reps with no circuit. "
              "Not included, no catalog match: standing founder, stretches and foam roll.",
        movements=[
            (1088, "Squat (Bodyweight)", 4, "10", STEADY, "Warm-up, 4 rounds"),
            (13, "Push-Up", 4, "10", STEADY, "Warm-up, 4 rounds"),
            (238, "Loaded Step-Up", 1, "300-450", "moderate pace", STEPUP),
            (786, "Sandbag Stone-to-Shoulder", 2, "5", STEADY, "Substitute for the sandbag cross clean, 40/60 lb"),
            (921, "Barbell Good Morning", 2, "10", "light", "Substitute for the sandbag good morning, 40/60 lb"),
            (983, "Back Extension", 2, "10", BW, "Face down"),
        ],
    ),
    # Backcountry Hunting Build 1 (205), phase build
    dict(
        name="Hunting Build 1: Step-Up Hike and Sandbag Getup, Burpee Grind",
        phase="build", credit=BUILD1, minutes=65,
        notes="Source: Backcountry Hunting Build 1 sessions 1 and 6 (uphill endurance under load, chassis integrity). 400 step-ups in "
              "a 25 to 35 lb backpack on a 16 to 18 inch box at a moderate pace, then an 18 minute grind of 5 sandbag getups, 5 sandbag "
              "keg lifts and 5 sandbag burpees at 40 or 60 lb, aiming for 4 or more rounds.",
        movements=[
            (238, "Loaded Step-Up", 1, "400", "moderate pace", STEPUP),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, GETUP + " and the keg lift, 40/60 lb. Aim for 4 or more rounds in 18 minutes"),
            (216, "Burpee", 4, "5", GRIND, "Sandbag burpee in the source. Burpee with the bag on the ground"),
        ],
    ),
    dict(
        name="Hunting Build 1: Back Squat, Bench Press, Pull-Up Percentage Day",
        phase="build", credit=BUILD1, minutes=60,
        notes="Source: Backcountry Hunting Build 1 sessions 4, 7, 9, 12, 14, 19, 22, 24, 27 and 29 (strength and work capacity). Warm-up is 3 rounds "
              "of 10 back squats and 5 Scotty Bobs. Back squat: 8 reps at 50% 1RM, 5 at 75%, then 5 rounds every 90 seconds of 4 "
              "reps at 80%, 85% and then 90% as the block progresses. Bench press: the same ladder. Then 5 rounds every 90 "
              "seconds of pull-ups at 30%, 35% or 40% of max reps. The 1RM and max pull-up sessions (2, 17, 32) set the percentages. "
              "Finisher changes by session: an 18 minute sandbag grind, a 15 minute AMRAP of 5 sandbag clean and presses with 40 "
              "step-ups, or a 15 minute AMRAP of power clean and push press or renegade man makers with a run. "
              "Not included, no catalog match: Scotty Bob, hug hip mobility drill, shoulder dislocates, toe touch complex.",
        movements=[
            (57, "Barbell Back Squat", 7, "4", "8 at 50%, 5 at 75%, then 5 rounds every 90 seconds at 80 to 90% 1RM", "Percentage of the athlete's 1RM"),
            (900, "Barbell Bench Press", 7, "4", "8 at 50%, 5 at 75%, then 5 rounds every 90 seconds at 80 to 90% 1RM", "Percentage of the athlete's 1RM"),
            (922, "Pull-Up", 5, "30-40% of max reps", "every 90 seconds", "Strict, no kipping"),
            (786, "Sandbag Stone-to-Shoulder", 3, "5", GRIND, "Finisher, substitute for the sandbag getup and clean and press, 40/60 lb"),
        ],
    ),
    # Backcountry Hunting Build 2 (206), phase build
    dict(
        name="Hunting Build 2: Floor Press, Chin-Up, One-Leg Deadlift Grind",
        phase="build", credit=BUILD2, minutes=55,
        notes="Source: Backcountry Hunting Build 2 sessions 2, 17 and 32 (strength and chassis integrity). Warm-up is 3 rounds of a "
              "dumbbell complex. Then 5 rounds of 3 Craig specials, 8 kettlebell floor presses (load rises each round until 8 is hard "
              "but doable) and 4 to 8 chin-ups. Session 2 closes with a 3 round grind of 5 one-sided deadlifts, 5 sandbag keg lifts and "
              "10 good mornings. Session 17 swaps the grind for kneeling plate half moons, kneeling keg lifts and 15 swings. Session 32 "
              "has no grind. "
              "Not included, no catalog match: Craig special, dumbbell complex, kneeling plate half moon, stretches.",
        movements=[
            (313, "Dumbbell Floor Press", 5, "8", HARD, "Substitute for the kettlebell floor press"),
            (923, "Chin-Up", 5, "4-8", STEADY, "Strict"),
            (108, "Single-Leg Romanian Deadlift", 3, "5", HARD, "Substitute for the one-sided deadlift, each side"),
            (786, "Sandbag Stone-to-Shoulder", 3, "5", GRIND, KEG + ", 40/60 lb"),
            (921, "Barbell Good Morning", 3, "10", HARD, "Start near 45 to 65 lb"),
        ],
    ),
    dict(
        name="Hunting Build 2: Walking Lunge, Curl to Press, Pull-Up Grind",
        phase="build", credit=BUILD2, minutes=55,
        notes="Source: Backcountry Hunting Build 2 sessions 7 and 22 (strength and chassis integrity). Warm-up is 3 rounds of a dumbbell "
              "complex. Then 5 rounds of 5 walking lunges and 8 kneeling curl to presses (load rises each round) with a 3 to 6 pull-up "
              "ladder. Then a 4 round grind: session 7 uses 5 one-sided deadlifts, 5 sandbag keg lifts and 10 good mornings, session 22 "
              "uses 5 dumbbell crawls, 5 seated keg lifts and 10 hinge lifts from 65 lb. "
              "Not included, no catalog match: kneeling curl to press (Dumbbell Overhead Press stands in), dumbbell crawl, dumbbell "
              "complex, stretches.",
        movements=[
            (943, "Walking Lunge", 5, "5", HARD, "Hold dumbbells or kettlebells"),
            (15, "Dumbbell Overhead Press", 5, "8", HARD, "Substitute for the kneeling curl to press"),
            (922, "Pull-Up", 5, "3-6", STEADY, "Strict ladder"),
            (59, "Conventional Deadlift", 4, "10", HARD, "Substitute for the hinge lift, from 65 lb. Session 7 uses good mornings"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, KEG + ", 40/60 lb"),
        ],
    ),
    dict(
        name="Hunting Build 2: Front Squat, Mixed Grip Pull-Up, Swing Grind",
        phase="build", credit=BUILD2, minutes=55,
        notes="Source: Backcountry Hunting Build 2 session 12 and session 27 (strength and chassis integrity). Warm-up is 3 rounds of a "
              "dumbbell complex. Then 5 rounds of 3 Mr. Spectaculars, 3 to 6 mixed grip pull-ups and 5 dumbbell or kettlebell front "
              "squats (load rises each round until 5 is hard but doable). Then a 4 round grind: session 12 uses 5 kneeling plate half "
              "moons, 5 kneeling keg lifts at 16 kg and 15 swings, session 27 uses 5 dumbbell crawls, 5 seated keg lifts and 10 hinge "
              "lifts. "
              "Not included, no catalog match: Mr. Spectacular, kneeling plate half moon, dumbbell crawl, dumbbell complex, stretches.",
        movements=[
            (922, "Pull-Up", 5, "3-6", STEADY, "Mixed grip in the source"),
            (1159, "Dumbbell Front Squat", 5, "5", HARD, "Substitute for the dumbbell or kettlebell front squat"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, KEG + ". Kneeling keg lift at 16 kg in the source"),
            (61, "Kettlebell Swing", 4, "15", GRIND, "12 to 16 kg, start light. Session 27 swaps the swings for hinge lifts"),
        ],
    ),
    dict(
        name="Hunting Build 2: Goblet Squat, Step-Up and Renegade Row AMRAP",
        phase="build", credit=BUILD2, minutes=50,
        notes="Source: Backcountry Hunting Build 2 sessions 4 and 9 (work capacity). Warm-up is 3 rounds of 10 goblet squats at 12 kg, "
              "5 Scotty Bobs and 15 step-ups. Then a 40 minute AMRAP of 5 renegade man makers at 15 or 25 lb, 4 prone to 40 ft sprints "
              "and 30 step-ups. "
              "Not included, no catalog match: Scotty Bob, prone to 40 ft sprint, stretches and foam roll.",
        movements=[
            (60, "Goblet Squat", 3, "10", STEADY, "12 kg. Warm-up, 3 rounds"),
            (238, "Loaded Step-Up", 3, "15", STEADY, "16 to 18 inch box. 30 step-ups per round in the AMRAP"),
            (373, "Renegade Row", 8, "5", GRIND, "Substitute for the renegade man maker, 15/25 lb. 40 minute AMRAP"),
        ],
    ),
    dict(
        name="Hunting Build 2: Goblet Squat, Step-Up and Sandbag Getup AMRAP",
        phase="build", credit=BUILD2, minutes=55,
        notes="Source: Backcountry Hunting Build 2 session 19 (work capacity). Warm-up is 3 rounds of 10 goblet squats at 12 kg, 5 "
              "Scotty Bobs and 15 step-ups. Then a 40 minute AMRAP of 5 sandbag getups (alternating shoulders), 5 sandbag clean and "
              "presses at 40 or 60 lb and a 200 m run. "
              "Not included, no catalog match: Scotty Bob, stretches and foam roll. The 200 m run is skipped.",
        movements=[
            (60, "Goblet Squat", 3, "10", STEADY, "12 kg. Warm-up, 3 rounds"),
            (238, "Loaded Step-Up", 3, "15", STEADY, "16 to 18 inch box. Warm-up, 3 rounds"),
            (786, "Sandbag Stone-to-Shoulder", 8, "5", GRIND, GETUP + " and the clean and press, 40/60 lb. 40 minute AMRAP"),
        ],
    ),
    dict(
        name="Hunting Build 2: Goblet Squat, Step-Up and Keg Lift AMRAP",
        phase="build", credit=BUILD2, minutes=55,
        notes="Source: Backcountry Hunting Build 2 sessions 24 and 29 (work capacity). Warm-up is 3 rounds of 10 goblet squats at 12 kg, "
              "5 Scotty Bobs and 15 step-ups. Then a 40 minute AMRAP of 2 sandbag clean and runs, 4 sandbag keg lifts at 40 or 60 lb "
              "and 40 step-ups. "
              "Not included, no catalog match: Scotty Bob, stretches and foam roll.",
        movements=[
            (60, "Goblet Squat", 3, "10", STEADY, "12 kg. Warm-up, 3 rounds"),
            (238, "Loaded Step-Up", 6, "40", GRIND, "16 to 18 inch box or bench. 40 minute AMRAP"),
            (786, "Sandbag Stone-to-Shoulder", 6, "4", GRIND, "Substitute for the keg lift and the clean and run, 40/60 lb"),
        ],
    ),
    dict(
        name="Hunting Build 2: Step-Up Hike with One-Leg Deadlift Circuit",
        phase="build", credit=BUILD2, minutes=70,
        notes="Source: Backcountry Hunting Build 2 sessions 5 and 10 (uphill endurance under load, chassis integrity). 600 step-ups "
              "in a 30 to 40 lb backpack on a 16 to 18 inch box at a moderate pace, then a 3 then 4 round grind of 5 one-sided "
              "deadlifts, 5 sandbag keg lifts and 10 good mornings. Not included: toe touch complex, foam roll.",
        movements=[
            (238, "Loaded Step-Up", 1, "600", "moderate pace", STEPUP),
            (108, "Single-Leg Romanian Deadlift", 4, "5", HARD, "Substitute for the one-sided deadlift"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, KEG + ", 40/60 lb"),
            (921, "Barbell Good Morning", 4, "10", HARD, "Start near 45 to 65 lb"),
        ],
    ),
    dict(
        name="Hunting Build 2: Step-Up Hike with Keg Lift and Swing Circuit",
        phase="build", credit=BUILD2, minutes=70,
        notes="Source: Backcountry Hunting Build 2 sessions 15 and 20 (uphill endurance under load, chassis integrity). 650 step-ups "
              "in a 30 to 40 lb backpack on a 16 to 18 inch box at a moderate pace, then a 4 round grind of 5 kneeling plate half "
              "moons, 5 kneeling keg lifts at 16 kg and 15 swings. "
              "Not included, no catalog match: kneeling plate half moon, toe touch complex, foam roll.",
        movements=[
            (238, "Loaded Step-Up", 1, "650", "moderate pace", STEPUP),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, KEG + ". Kneeling keg lift at 16 kg in the source"),
            (61, "Kettlebell Swing", 4, "15", GRIND, "12 to 16 kg, start light"),
        ],
    ),
    dict(
        name="Hunting Build 2: Step-Up Hike with Seated Keg Lift and Hinge Lift Circuit",
        phase="build", credit=BUILD2, minutes=70,
        notes="Source: Backcountry Hunting Build 2 sessions 25 and 30 (uphill endurance under load, chassis integrity). 700 step-ups "
              "in a 30 to 40 lb backpack on a 16 to 18 inch box at a moderate pace, then a 4 round grind of 5 dumbbell crawls, 5 "
              "seated keg lifts at 16 or 20 kg and 10 hinge lifts from 65 or 95 lb. "
              "Not included, no catalog match: dumbbell crawl, toe touch complex, foam roll.",
        movements=[
            (238, "Loaded Step-Up", 1, "700", "moderate pace", STEPUP),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, "Substitute for the seated keg lift"),
            (59, "Conventional Deadlift", 4, "10", HARD, "Substitute for the hinge lift, start at 65 to 95 lb"),
        ],
    ),
    # Backcountry Big Game Hunting Preseason V5 (203), phase build
    dict(
        name="Big Game Preseason: Leg Blaster, Goblet Squat and Nordic Curl Strength",
        phase="build", credit=BIGGAME, minutes=40,
        notes="Source: Backcountry Big Game Hunting Preseason V5 sessions 2, 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35, 38 and 41 "
              "(strength, heavy ruck two a day). Warm-up is 3 rounds of 10 goblet squats, 5 hand-release push-ups and 5 in-place "
              "lunges. The strength block is 8 to 10 rounds of the mini blaster with 2 to 3 Scotty Bobs, rising to 5 to 6 rounds of "
              "the full blaster with up to 6 Scotty Bobs, then 2 rounds of 10 to 20 one-leg poor man's leg curls. The PM ruck is "
              "dropped. "
              "Not included, no catalog match: Scotty Bob, stretches and foam roll.",
        movements=[
            (60, "Goblet Squat", 3, "10", STEADY, "Warm-up, 3 rounds, 15 or 25 lb dumbbell"),
            (13, "Push-Up", 3, "5", STEADY, HAND_RELEASE + ". Warm-up, 3 rounds"),
        ] + blaster(8, "mini") + [
            (102, "Nordic Hamstring Curl", 2, "10", BW, "Substitute for the one-leg poor man's leg curl, 10 to 20 reps in the source. Use the reps you can control"),
        ],
    ),
    dict(
        name="Big Game Preseason: Goblet Squat, Step-Up Hike and Sandbag Grind",
        phase="build", credit=BIGGAME, minutes=60,
        notes="Source: Backcountry Big Game Hunting Preseason V5 sessions 4, 10, 16, 22, 28, 34, 40 and 43 (loaded uphill hiking, "
              "chassis integrity). 3 rounds of 10 goblet squats, 10 step-ups and 5 hand-release push-ups, then 500 to 1,000 "
              "step-ups in a 30 to 40 lb backpack at a moderate pace. Sessions 4, 10 and 43 finish with a 10 to 15 minute grind of "
              "sandbag getups, keg lifts and sandbag good mornings. Sessions 16, 22 and 28 use clean and presses, founders and keg "
              "lifts. Sessions 34 and 40 have no grind. "
              "Not included, no catalog match: standing and kneeling founder, toe touch complex, foam roll.",
        movements=[
            (60, "Goblet Squat", 3, "10", STEADY, "15 or 25 lb dumbbell. 3 rounds"),
            (13, "Push-Up", 3, "5", STEADY, HAND_RELEASE),
            (238, "Loaded Step-Up", 3, "10", STEADY, "16 to 18 inch box. Then the 500 to 1,000 step hike in the source. " + STEPUP),
            (786, "Sandbag Stone-to-Shoulder", 3, "5", GRIND, GETUP + " and the keg lift, 40/60 lb"),
            (921, "Barbell Good Morning", 3, "10", "light", "Substitute for the sandbag good morning"),
        ],
    ),
    dict(
        name="Big Game Preseason: Step-Up Intervals with Sandbag Grind",
        phase="build", credit=BIGGAME, minutes=60,
        notes="Source: Backcountry Big Game Hunting Preseason V5 sessions 7, 13, 25 and 31 (step up intervals, chassis integrity). 3 "
              "rounds of 10 goblet squats, 10 step-ups and 5 hand-release push-ups, then 2 rounds every 10 minutes of step-ups at "
              "40% or 45% of the max rep step-up test, in a 30 to 40 lb backpack. Then a 12 to 20 minute grind of sandbag getups or "
              "getup and runs, keg lifts and sandbag good mornings or founders. "
              "Not included, no catalog match: standing and kneeling founder, stretches and foam roll.",
        movements=[
            (60, "Goblet Squat", 3, "10", STEADY, "15 or 25 lb dumbbell. 3 rounds"),
            (13, "Push-Up", 3, "5", STEADY, HAND_RELEASE),
            (238, "Loaded Step-Up", 5, "10", STEADY, "16 to 18 inch box. Plus 2 rounds every 10 minutes at 40 to 45% of max reps. " + STEPUP),
            (786, "Sandbag Stone-to-Shoulder", 3, "5", GRIND, GETUP + " and the keg lift, 40/60 lb"),
            (921, "Barbell Good Morning", 3, "10", "light", "Substitute for the sandbag good morning"),
        ],
    ),
    # Whitetail Deer Hunting Preseason (208), phase build
    dict(
        name="Whitetail Preseason: Squat, Push-Up and Pull-Up Every 80 Seconds",
        phase="build", credit=WHITETAIL, minutes=45,
        notes="Source: Whitetail Deer Hunting Preseason sessions 5, 8, 11, 17, 20 and 23 (strength progression), with the same grind "
              "in assessment sessions 2, 14 and 26. Warm-up is 4 rounds of 10 squats, 10 push-ups and 10 sit-ups. The loading is "
              "33% of the max rep results from the 2 minute assessment: 6 rounds every 80 seconds of sandbag back squats at "
              "40 or 60 lb, then the same for hand-release push-ups, then pull-ups. The faster a round ends the more rest before the "
              "next. Close with 3 rounds of a max effort front bridge, resting 60 seconds between efforts. "
              "Not included, no catalog match: instep complex, stretches.",
        movements=[
            (57, "Barbell Back Squat", 6, "33% of max reps", "every 80 seconds", "Substitute for the sandbag back squat at 40/60 lb. Keep the load light so the reps match the source"),
            (13, "Push-Up", 6, "33% of max reps", "every 80 seconds", HAND_RELEASE),
            (922, "Pull-Up", 6, "33% of max reps", "every 80 seconds", "Strict"),
            (974, "Front Plank", 3, "max", "rest 60 seconds", "Front bridge. Hold as long as possible each round. 5 to 6 rounds in assessment sessions"),
        ],
    ),
    dict(
        name="Whitetail Preseason: Sandbag Getup Grind with Lunge and Back Extension",
        phase="build", credit=WHITETAIL, minutes=40,
        notes="Source: Whitetail Deer Hunting Preseason sessions 3, 9, 15, 21 and 27 (work capacity, chassis integrity, stamina). "
              "Warm-up is 3 rounds of 5 in-place lunges, 10 push-ups and 10 face down back extensions. Then a 20 minute grind of 5 "
              "sandbag getups (alternating shoulders), 5 sandbag clean and presses at 40 or 60 lb and a 200 m run. Close with 3 "
              "rounds of kneeling founders and 10 face down back extensions. "
              "Not included, no catalog match: kneeling founder, stretches. The 200 m run is skipped.",
        movements=[
            (1051, "Lunge (Bodyweight)", 3, "5", STEADY, "In place. Warm-up, 3 rounds"),
            (13, "Push-Up", 3, "10", STEADY, "Warm-up, 3 rounds"),
            (983, "Back Extension", 6, "10", BW, "Face down. 3 rounds in the warm-up and 3 rounds to finish"),
            (786, "Sandbag Stone-to-Shoulder", 4, "5", GRIND, GETUP + " and the clean and press, 40/60 lb. 20 minute grind"),
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
        for sport in HUNTING_SPORTS:
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
