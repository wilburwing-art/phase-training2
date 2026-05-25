#!/usr/bin/env python3
"""Draft new exercise rows from the gap_classification.csv NEW bucket.

Produces TWO artifacts:
  - proposed_new_exercises.csv  — one row per new exercise, in the same shape
                                  export_exercises.py emits so import_exercises.py
                                  can consume it directly.
  - proposed_aliases.json       — a list of {exercise_id, alias} rows for the
                                  source-app names that should resolve to the
                                  existing DB rows.
  - proposed_equipment.json     — new equipment rows that need to land in
                                  db/source/equipment.json before import.

This is the BIG mechanical pass. Each new exercise gets a structured draft
keyed by source name. Defaults inherit from a "family" the exercise belongs
to (e.g. "bench press family", "curl family") with per-variant overrides.

Review the resulting CSV before committing — many descriptions / cues are
plausible-but-generic placeholders that benefit from a human pass.
"""

import csv
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "db" / "source"
CLASSIFICATION_CSV = REPO_ROOT / "gap_classification.csv"

# Columns matching export_exercises.py output so the round-trip works.
COLUMNS = [
    "id", "name", "slug",
    "category", "equipment", "muscles_primary", "muscles_secondary",
    "movement_patterns", "aliases",
    "difficulty", "modality", "environment",
    "default_sets", "default_reps", "default_rest", "default_tempo", "default_duration",
    "is_compound", "is_unilateral",
    "movement_plane", "energy_system", "contraction_type",
    "recovery_demand", "cns_load", "intensity_category", "fatigue_type",
    "low_energy_suitable", "pre_event_safe", "warmup_compatible",
    "swap_group",
    "description", "instructions", "cues",
    "regression", "progression",
    "time_efficient_variation", "home_variation", "age_considerations",
    "desk_worker_notes",
    "injury_prevention_notes", "contraindications",
    "pt_rehab_relevance", "common_compensations",
    "image_url", "thumbnail_url", "video_url",
    "image_source", "image_license", "image_attribution",
    "source_name", "source_url", "source_type", "source_year",
    "source_video_attribution",
    "tags",
    "created_at", "updated_at",
]


TODAY = "2026-05-22 00:00:00"

# Per-difficulty defaults — match the patterns in the existing exercises.json
# (Side Plank=beginner@2/2/low, Single-Leg RDL=intermediate@4/3/moderate,
#  Hang Power Clean=advanced+power@6/7/high).
DEFAULTS_BY_DIFFICULTY = {
    "beginner":     dict(recovery_demand=2, cns_load=2, intensity_category="low",
                         low_energy_suitable=1, pre_event_safe=1, warmup_compatible=1),
    "intermediate": dict(recovery_demand=4, cns_load=3, intensity_category="moderate",
                         low_energy_suitable=0, pre_event_safe=1, warmup_compatible=0),
    "advanced":     dict(recovery_demand=6, cns_load=6, intensity_category="high",
                         low_energy_suitable=0, pre_event_safe=0, warmup_compatible=0),
    "elite":        dict(recovery_demand=7, cns_load=7, intensity_category="high",
                         low_energy_suitable=0, pre_event_safe=0, warmup_compatible=0),
}

# Modality-specific bumps applied on top of difficulty.
DEFAULTS_BY_MODALITY = {
    "power":     dict(cns_load=7),
    "endurance": dict(recovery_demand=2, cns_load=2, intensity_category="moderate"),
    "flexibility": dict(recovery_demand=1, cns_load=1, intensity_category="low",
                        low_energy_suitable=1, pre_event_safe=1, warmup_compatible=1),
}

# fatigue_type tags per family — JSON-encoded list on insert.
FATIGUE_BY_FAMILY = {
    "bench_press":         ["chest", "triceps", "shoulders"],
    "incline_bench_press": ["upper_chest", "shoulders", "triceps"],
    "decline_bench_press": ["lower_chest", "triceps"],
    "chest_fly":           ["chest"],
    "chest_press_machine": ["chest", "triceps"],
    "dip":                 ["chest", "triceps"],
    "tricep_extension":    ["triceps"],
    "skullcrusher":        ["triceps", "elbow"],
    "tricep_pushdown":     ["triceps"],
    "bicep_curl":          ["biceps"],
    "reverse_curl":        ["forearms", "biceps"],
    "row_bb":              ["upper_back", "lats", "biceps"],
    "row_machine":         ["upper_back", "lats", "biceps"],
    "lat_pulldown":        ["lats", "biceps"],
    "pull_up_variant":     ["lats", "biceps", "grip"],
    "shrug":               ["traps", "grip"],
    "deadlift":            ["posterior_chain", "grip", "cns"],
    "rdl":                 ["hamstrings", "glutes"],
    "squat":               ["legs", "glutes", "cns"],
    "single_leg_squat":    ["legs", "glutes", "balance"],
    "lunge":               ["legs", "glutes"],
    "calf_raise":          ["calves"],
    "ohp":                 ["shoulders", "triceps"],
    "front_raise":         ["front_delts"],
    "lateral_raise":       ["lateral_delts"],
    "reverse_fly":         ["rear_delts"],
    "core_crunch":         ["core"],
    "core_oblique":        ["obliques", "core"],
    "core_rotation":       ["obliques"],
    "core_hanging":        ["core", "grip"],
    "side_bend":           ["obliques"],
    "olympic":             ["posterior_chain", "traps", "legs", "cns"],
    "cardio_machine":      ["aerobic"],
    "conditioning":        ["aerobic", "conditioning"],
    "iso_lateral":         ["chest", "triceps"],
    "smith":               ["legs", "glutes"],
    "shrug_machine":       ["traps"],
}

# Generic regression / progression suggestions per family. These get applied
# only when the per-exercise override doesn't set them.
PROG_BY_FAMILY = {
    "bench_press":         ("Push-up", "Pause bench press at the chest"),
    "incline_bench_press": ("Lower the incline angle to 15-30°", "Add a pause at the chest"),
    "decline_bench_press": ("Switch to flat bench", "Add a pause at the chest"),
    "chest_fly":           ("Lighter DBs, slower tempo", "Cable fly with constant tension"),
    "chest_press_machine": ("Reduce the load", "Switch to dumbbell bench press"),
    "dip":                 ("Bench dips or band-assisted dips", "Weighted dips with a weight belt"),
    "tricep_extension":    ("Lighter weight with strict form", "Add a pause at full extension"),
    "skullcrusher":        ("Lighter dumbbell skullcrusher", "JM press or heavier load"),
    "tricep_pushdown":     ("Reduce weight, slow tempo", "Single-arm cable pushdown"),
    "bicep_curl":          ("Lower the load, slow eccentric", "Add a pause at the top"),
    "reverse_curl":        ("Lower the load", "Switch to fat-grip or thick-bar reverse curl"),
    "row_bb":              ("Inverted row at higher bar height", "Pendlay row or weighted vest"),
    "row_machine":         ("Reduce weight, focus on squeeze", "Increase weight or add a pause"),
    "lat_pulldown":        ("Lighter weight, slow eccentric", "Strict pull-ups"),
    "pull_up_variant":     ("Inverted row or band-assisted pull-up", "Weighted pull-up"),
    "shrug":               ("Lower the load, control tempo", "Pause at the top of each rep"),
    "deadlift":            ("Romanian deadlift or trap-bar deadlift", "Deficit deadlift or chains"),
    "rdl":                 ("Reduce ROM", "Single-leg RDL or deficit RDL"),
    "squat":               ("Goblet squat or box squat", "Pause squat or tempo squat"),
    "single_leg_squat":    ("Box-assisted pistol or split squat", "Weighted pistol squat"),
    "lunge":               ("Static lunge or shorter step", "Walking lunge with weight"),
    "calf_raise":          ("Bodyweight calf raise", "Single-leg weighted calf raise"),
    "ohp":                 ("Seated DB shoulder press", "Heavier press or strict press"),
    "front_raise":         ("Lighter weight, slow tempo", "1.5-rep front raise"),
    "lateral_raise":       ("Lighter DBs, partial range", "Cable lateral raise"),
    "reverse_fly":         ("Lighter DBs", "Cable reverse fly with isolated tempo"),
    "core_crunch":         ("Crunch", "Add weight or extend the lever"),
    "core_oblique":        ("Lighter side bend", "Cable wood chop"),
    "core_rotation":       ("Half-kneeling rotation with band", "Heavier cable rotation"),
    "core_hanging":        ("Knee tucks lying down", "Toes-to-bar"),
    "side_bend":           ("Bodyweight side bend", "Heavier weight, slower tempo"),
    "olympic":             ("Hang variation or kettlebell version", "Increase load, work from the floor"),
    "cardio_machine":      ("Reduce intensity / shorter intervals", "Add interval work or longer duration"),
    "conditioning":        ("Reduce intensity or work-to-rest ratio", "Add load (weighted vest, heavier ball)"),
    "iso_lateral":         ("Reduce load", "Add a pause or slower eccentric"),
    "smith":               ("Reduce load", "Switch to free-weight version"),
    "shrug_machine":       ("Lower the load", "Pause at the top"),
}

# Time-efficient / home-friendly substitutions per family. These match the
# 86%-population rate in the existing DB — they're useful programming hints
# the planner uses when budget or equipment is constrained.
ALT_BY_FAMILY = {
    # family: (time_efficient, home_variation)
    "bench_press":         ("Drop sets on the last set for compressed volume.", "Push-up variations at home."),
    "incline_bench_press": ("Run incline DB press as a giant set with push-ups.", "Hand-elevated push-ups."),
    "decline_bench_press": ("Pair with incline work as an antagonist superset.", "Decline push-ups with feet on a couch."),
    "chest_fly":           ("Slow eccentric only sets — half the volume, same stimulus.", "Band pec fly anchored to door."),
    "chest_press_machine": ("Cluster sets — 3×3 with 15s intra-set rest.", "Band chest press at home."),
    "dip":                 ("Run dips as a finisher on push days.", "Bench dips between chairs."),
    "tricep_extension":    ("Superset with biceps curls for arm-day efficiency.", "Resistance band overhead extension."),
    "skullcrusher":        ("Run with close-grip bench in a giant set.", "DB skullcrusher works at home."),
    "tricep_pushdown":     ("EMOM 10s of 6 reps for grease-the-groove triceps work.", "Band pushdown anchored overhead."),
    "bicep_curl":          ("Mechanical drop set: BB curl → reverse curl.", "DB curl or band curl at home."),
    "reverse_curl":        ("Pair with bicep curls for forearm + bicep finisher.", "Band reverse curl at home."),
    "row_bb":              ("Superset with bench press for upper-body balance.", "Inverted row at home with a sturdy bar."),
    "row_machine":         ("Use as a finisher with high-rep volume.", "Band row anchored at hip height."),
    "lat_pulldown":        ("Strict tempo (3-sec eccentric) reduces volume need.", "Band pulldown anchored overhead."),
    "pull_up_variant":     ("Daily greasing-the-groove sets at home or office.", "Doorway pull-up bar."),
    "shrug":               ("Combine with grip work or carries.", "Heavy DB shrugs work at home."),
    "deadlift":            ("Top-set + 3 backoff sets keeps it under 30 min.", "Trap-bar or DB deadlift at home."),
    "rdl":                 ("Pair with pulls in an antagonist superset.", "DB RDL or banded RDL at home."),
    "squat":               ("Top-set + 2 backoff sets is enough stimulus.", "Goblet squat or bodyweight squat at home."),
    "single_leg_squat":    ("Cycle through unilateral patterns for a fast finisher.", "Pistol or split squat at home."),
    "lunge":               ("Run walking lunges as a leg-day finisher.", "Bodyweight or DB lunges at home."),
    "calf_raise":          ("EMOM 1-minute sets for grease-the-groove calf work.", "Step or stair raises at home."),
    "ohp":                 ("Strict press + push press as a complex.", "DB or band overhead press."),
    "front_raise":         ("Run with lateral and rear delts as a finisher.", "Band front raise."),
    "lateral_raise":       ("Mechanical drop set: leaning → standing → seated.", "Band or DB lateral raise."),
    "reverse_fly":         ("Pair with face pulls for rear delt focus.", "Bent-over band reverse fly."),
    "core_crunch":         ("Run as a finisher (AMRAP 5 min).", "All variants are bodyweight."),
    "core_oblique":        ("Run as part of a core circuit.", "Bodyweight at home."),
    "core_rotation":       ("Quick warm-up before any rotational sport.", "Band rotation at home."),
    "core_hanging":        ("Pair with grip work for a compact finisher.", "Doorway pull-up bar + knee raise."),
    "side_bend":           ("Run as a finisher with high reps.", "Single DB side bend at home."),
    "olympic":             ("Complexes — 3+3+3 clean/jerk/clean.", "Kettlebell or DB versions at home."),
    "cardio_machine":      ("Sprint intervals: 30s on / 30s off × 10.", "Outdoor running or jumping rope."),
    "conditioning":        ("EMOM or AMRAP formats compress volume.", "Bodyweight versions need no equipment."),
    "iso_lateral":         ("Drop sets are easy and effective on these machines.", "Single-arm DB row or press."),
    "smith":               ("Tempo work + close-grip variants.", "Free-weight version at home."),
    "shrug_machine":       ("Use as a finisher with carries.", "DB shrugs at home."),
}

# Common technique compensations to watch for — used to populate
# common_compensations as a JSON list. Per family.
COMPENSATIONS_BY_FAMILY = {
    "bench_press":         ["bar bouncing off chest", "wrist flexion", "elbows flaring 90°"],
    "incline_bench_press": ["shoulders rolling forward", "rib flare"],
    "decline_bench_press": ["short ROM", "hip lifting off bench"],
    "chest_fly":           ["elbow bend changing through ROM", "shoulders rolling forward"],
    "dip":                 ["shoulder shrug", "partial ROM"],
    "tricep_extension":    ["elbow flare", "upper arm moving instead of forearm"],
    "skullcrusher":        ["elbow flare", "shoulder extending"],
    "tricep_pushdown":     ["elbow drifting forward", "body lean for momentum"],
    "bicep_curl":          ["body swing", "elbow drift forward", "shrugging"],
    "reverse_curl":        ["wrist flexion at top", "elbow drift"],
    "row_bb":              ["rounding lower back", "shrugging instead of rowing", "torso rising mid-rep"],
    "row_machine":         ["shoulders rolling forward", "partial ROM"],
    "lat_pulldown":        ["body lean for momentum", "bar to forehead instead of chest"],
    "pull_up_variant":     ["partial ROM", "kipping for non-kip reps", "shoulder shrug instead of pull"],
    "shrug":               ["rolling shoulders", "rapid concentric"],
    "deadlift":            ["rounded lower back", "bar drifting from body", "hips rising too fast"],
    "rdl":                 ["rounded back", "squatting instead of hinging"],
    "squat":               ["knees caving in", "heel lifting", "early hip-shoot"],
    "single_leg_squat":    ["knee caving in", "torso collapsing forward", "balance loss"],
    "lunge":               ["front knee caving", "torso leaning forward"],
    "calf_raise":          ["partial ROM", "bouncing reps"],
    "ohp":                 ["lower-back hyperextension", "neck craning forward"],
    "front_raise":         ["body swing", "raising too high"],
    "lateral_raise":       ["shrugging up", "leading with thumb up"],
    "reverse_fly":         ["body sway", "elbow bend changing"],
    "core_crunch":         ["neck pull", "hip flexor dominance"],
    "core_oblique":        ["rotating instead of side-bending", "neck pull"],
    "core_rotation":       ["arms doing the work", "no hip rotation"],
    "core_hanging":        ["swinging or kipping", "shoulder shrug"],
    "side_bend":           ["rotation instead of pure lateral flexion"],
    "olympic":             ["bar drifting away from body", "early arm bend"],
    "cardio_machine":      ["leaning on rails", "uneven cadence"],
    "conditioning":        ["sloppy form when fatigued"],
    "iso_lateral":         ["asymmetric loading", "shoulders rolling forward"],
    "smith":               ["over-reliance on the fixed path"],
    "shrug_machine":       ["partial ROM", "rolling shoulders"],
}

# Equipment slugs we need that don't exist yet. Will be appended to
# equipment.json by the import step (handled separately for clarity).
NEW_EQUIPMENT = [
    {"id": 101, "slug": "smith-machine",         "name": "Smith Machine"},
    {"id": 102, "slug": "chest-press-machine",   "name": "Chest Press Machine"},
    {"id": 103, "slug": "shoulder-press-machine","name": "Shoulder Press Machine"},
    {"id": 104, "slug": "iso-lateral-machine",   "name": "Iso-Lateral Plate Loaded Machine"},
    {"id": 105, "slug": "preacher-bench",        "name": "Preacher Bench"},
    {"id": 106, "slug": "captains-chair",        "name": "Captain's Chair"},
    {"id": 107, "slug": "stair-climber",         "name": "Stair Climber"},
    {"id": 108, "slug": "elliptical",            "name": "Elliptical"},
    {"id": 109, "slug": "assault-bike",          "name": "Assault Bike / Air Bike"},
    {"id": 110, "slug": "treadmill",             "name": "Treadmill"},
    {"id": 111, "slug": "ab-wheel",              "name": "Ab Wheel"},
    {"id": 112, "slug": "torso-rotation-machine","name": "Torso Rotation Machine"},
    {"id": 113, "slug": "shrug-machine",         "name": "Shrug Machine"},
    {"id": 114, "slug": "glute-kickback-machine","name": "Glute Kickback Machine"},
    {"id": 115, "slug": "back-extension-machine","name": "Back Extension Machine"},
    {"id": 116, "slug": "bicep-curl-machine",    "name": "Bicep Curl Machine"},
    {"id": 117, "slug": "tricep-extension-machine","name": "Triceps Extension Machine"},
    {"id": 118, "slug": "pec-deck",              "name": "Pec Deck Machine"},
]

# Families share default fields. Per-exercise drafts then override specifics.
FAMILIES = {
    "bench_press": dict(
        category="Chest",
        muscles_primary=["pec-major-sternal"],
        muscles_secondary=["triceps", "delt-anterior"],
        movement_patterns=["horizontal-push"],
        difficulty="intermediate",
        modality="strength",
        environment="gym",
        default_sets=4, default_reps="6-10", default_rest="90-180s",
        is_compound=1, is_unilateral=0,
        movement_plane="sagittal", energy_system="phosphagen",
        contraction_type="concentric", swap_group="horizontal_push",
    ),
    "incline_bench_press": dict(
        category="Chest",
        muscles_primary=["pec-major-clav"],
        muscles_secondary=["delt-anterior", "triceps"],
        movement_patterns=["horizontal-push"],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=4, default_reps="6-10", default_rest="90-180s",
        is_compound=1, is_unilateral=0,
        movement_plane="sagittal", swap_group="incline_push",
    ),
    "decline_bench_press": dict(
        category="Chest",
        muscles_primary=["pec-major-sternal"],
        muscles_secondary=["triceps", "delt-anterior"],
        movement_patterns=["horizontal-push"],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=4, default_reps="6-10", default_rest="90-180s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="horizontal_push",
    ),
    "chest_fly": dict(
        category="Chest",
        muscles_primary=["pec-major-sternal"],
        muscles_secondary=["delt-anterior"],
        movement_patterns=["horizontal-push"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-15", default_rest="60-90s",
        is_compound=0, is_unilateral=0, movement_plane="transverse",
        swap_group="chest_isolation",
    ),
    "chest_press_machine": dict(
        category="Chest",
        muscles_primary=["pec-major-sternal"],
        muscles_secondary=["triceps", "delt-anterior"],
        movement_patterns=["horizontal-push"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="horizontal_push",
    ),
    "dip": dict(
        category="Chest",
        muscles_primary=["pec-major-sternal", "triceps"],
        muscles_secondary=["delt-anterior"],
        movement_patterns=["vertical-push"],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=3, default_reps="6-10", default_rest="90-120s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="dip",
    ),
    "tricep_extension": dict(
        category="Arms",
        muscles_primary=["triceps"],
        muscles_secondary=[],
        movement_patterns=["elbow-extension"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-12", default_rest="60-90s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="tricep_isolation",
    ),
    "skullcrusher": dict(
        category="Arms",
        muscles_primary=["triceps"],
        muscles_secondary=[],
        movement_patterns=["elbow-extension"],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="tricep_isolation",
    ),
    "tricep_pushdown": dict(
        category="Arms",
        muscles_primary=["triceps"],
        muscles_secondary=[],
        movement_patterns=["elbow-extension"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-15", default_rest="60s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="tricep_isolation",
    ),
    "bicep_curl": dict(
        category="Arms",
        muscles_primary=["biceps"],
        muscles_secondary=["brachialis", "brachioradialis"],
        movement_patterns=["elbow-flexion"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="bicep_isolation",
    ),
    "reverse_curl": dict(
        category="Arms",
        muscles_primary=["brachioradialis"],
        muscles_secondary=["biceps", "forearm-extensors"],
        movement_patterns=["elbow-flexion"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-12", default_rest="60s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="forearm_isolation",
    ),
    "row_bb": dict(
        category="Back",
        muscles_primary=["lats", "mid-traps", "rhomboids"],
        muscles_secondary=["biceps", "delt-posterior"],
        movement_patterns=["horizontal-pull"],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=4, default_reps="6-10", default_rest="90-120s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="horizontal_pull",
    ),
    "row_machine": dict(
        category="Back",
        muscles_primary=["lats", "mid-traps", "rhomboids"],
        muscles_secondary=["biceps", "delt-posterior"],
        movement_patterns=["horizontal-pull"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="horizontal_pull",
    ),
    "lat_pulldown": dict(
        category="Back",
        muscles_primary=["lats"],
        muscles_secondary=["biceps", "mid-traps", "rhomboids"],
        movement_patterns=["vertical-pull"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="vertical_pull",
    ),
    "pull_up_variant": dict(
        category="Back",
        muscles_primary=["lats"],
        muscles_secondary=["biceps", "mid-traps", "grip-crush"],
        movement_patterns=["vertical-pull"],
        difficulty="advanced", modality="strength", environment="home",
        default_sets=3, default_reps="3-8", default_rest="120-180s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="vertical_pull_bw",
    ),
    "shrug": dict(
        category="Back",
        muscles_primary=["upper-traps"],
        muscles_secondary=["mid-traps", "grip-crush"],
        movement_patterns=["scapular-retraction"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-15", default_rest="60s",
        is_compound=0, is_unilateral=0, movement_plane="frontal",
        swap_group="shrug",
    ),
    "deadlift": dict(
        category="Back",
        muscles_primary=["glutes", "hamstrings", "erector-lumbar"],
        muscles_secondary=["lats", "upper-traps", "forearm-flexors"],
        movement_patterns=["hip-hinge"],
        difficulty="advanced", modality="strength", environment="gym",
        default_sets=4, default_reps="3-6", default_rest="2-3 min",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="hip_hinge_max",
    ),
    "rdl": dict(
        category="Legs",
        muscles_primary=["hamstrings", "glutes"],
        muscles_secondary=["erector-lumbar", "lats"],
        movement_patterns=["hip-hinge"],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=4, default_reps="6-8", default_rest="2 min",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="hip_hinge",
    ),
    "squat": dict(
        category="Legs",
        muscles_primary=["quadriceps", "glutes"],
        muscles_secondary=["hamstrings", "adductors", "core"],
        movement_patterns=["squat"],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=4, default_reps="5-8", default_rest="2-3 min",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="squat_bilateral",
    ),
    "single_leg_squat": dict(
        category="Legs",
        muscles_primary=["quadriceps", "glutes"],
        muscles_secondary=["hamstrings", "adductors", "glute-med"],
        movement_patterns=["single-leg-squat"],
        difficulty="intermediate", modality="strength", environment="anywhere",
        default_sets=3, default_reps="6-10", default_rest="90-120s",
        is_compound=1, is_unilateral=1, movement_plane="sagittal",
        swap_group="single_leg",
    ),
    "lunge": dict(
        category="Legs",
        muscles_primary=["quadriceps", "glutes"],
        muscles_secondary=["hamstrings", "adductors"],
        movement_patterns=["single-leg-squat"],
        difficulty="beginner", modality="strength", environment="anywhere",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        is_compound=1, is_unilateral=1, movement_plane="sagittal",
        swap_group="lunge",
    ),
    "calf_raise": dict(
        category="Legs",
        muscles_primary=["gastrocnemius", "soleus"],
        muscles_secondary=[],
        movement_patterns=["calf-raise"],
        difficulty="beginner", modality="strength", environment="anywhere",
        default_sets=3, default_reps="12-20", default_rest="45-60s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="calf",
    ),
    "ohp": dict(
        category="Shoulders",
        muscles_primary=["delt-anterior", "delt-lateral"],
        muscles_secondary=["triceps", "upper-traps"],
        movement_patterns=["vertical-push"],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=4, default_reps="5-8", default_rest="90-180s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="vertical_push",
    ),
    "front_raise": dict(
        category="Shoulders",
        muscles_primary=["delt-anterior"],
        muscles_secondary=[],
        movement_patterns=["scapular-protraction"],
        difficulty="beginner", modality="strength", environment="anywhere",
        default_sets=3, default_reps="10-15", default_rest="45-60s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="front_delt",
    ),
    "lateral_raise": dict(
        category="Shoulders",
        muscles_primary=["delt-lateral"],
        muscles_secondary=[],
        movement_patterns=["scapular-protraction"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-15", default_rest="45-60s",
        is_compound=0, is_unilateral=0, movement_plane="frontal",
        swap_group="lateral_delt",
    ),
    "reverse_fly": dict(
        category="Shoulders",
        muscles_primary=["delt-posterior"],
        muscles_secondary=["mid-traps", "rhomboids"],
        movement_patterns=["scapular-retraction"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-15", default_rest="45-60s",
        is_compound=0, is_unilateral=0, movement_plane="transverse",
        swap_group="rear_delt",
    ),
    "core_crunch": dict(
        category="Core",
        muscles_primary=["rectus-abdominis"],
        muscles_secondary=["external-obliques"],
        movement_patterns=["anti-extension"],
        difficulty="beginner", modality="strength", environment="anywhere",
        default_sets=3, default_reps="12-20", default_rest="45-60s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="anti_extension",
    ),
    "core_oblique": dict(
        category="Core",
        muscles_primary=["external-obliques", "internal-obliques"],
        muscles_secondary=["rectus-abdominis"],
        movement_patterns=["anti-lateral-flexion"],
        difficulty="beginner", modality="strength", environment="anywhere",
        default_sets=3, default_reps="10-15", default_rest="45-60s",
        is_compound=0, is_unilateral=1, movement_plane="frontal",
        swap_group="oblique",
    ),
    "core_rotation": dict(
        category="Core",
        muscles_primary=["external-obliques", "internal-obliques"],
        muscles_secondary=["rectus-abdominis"],
        movement_patterns=["trunk-rotation"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-12", default_rest="45-60s",
        is_compound=0, is_unilateral=0, movement_plane="transverse",
        swap_group="rotation",
    ),
    "core_hanging": dict(
        category="Core",
        muscles_primary=["rectus-abdominis", "hip-flexors"],
        muscles_secondary=["external-obliques", "grip-crush"],
        movement_patterns=["anti-extension", "hip-flexion"],
        difficulty="intermediate", modality="strength", environment="home",
        default_sets=3, default_reps="8-15", default_rest="60-90s",
        is_compound=0, is_unilateral=0, movement_plane="sagittal",
        swap_group="hanging_core",
    ),
    "side_bend": dict(
        category="Core",
        muscles_primary=["external-obliques", "internal-obliques"],
        muscles_secondary=["quadratus-lumborum"],
        movement_patterns=["anti-lateral-flexion"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="10-15", default_rest="45s",
        is_compound=0, is_unilateral=1, movement_plane="frontal",
        swap_group="lateral_core",
    ),
    "olympic": dict(
        category="Olympic",
        muscles_primary=["full-body"],
        muscles_secondary=["glutes", "quadriceps", "upper-traps"],
        movement_patterns=["olympic-derivative"],
        difficulty="advanced", modality="power", environment="gym",
        default_sets=5, default_reps="2-3", default_rest="2-3 min",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="olympic",
    ),
    "cardio_machine": dict(
        category="Cardio",
        muscles_primary=["full-body"],
        muscles_secondary=[],
        movement_patterns=["locomotion"],
        difficulty="beginner", modality="endurance", environment="gym",
        default_sets=1, default_reps=None, default_rest=None,
        default_duration="20-40 min",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
        swap_group="cardio_steady",
    ),
    "conditioning": dict(
        category="Full Body",
        muscles_primary=["full-body"],
        muscles_secondary=[],
        movement_patterns=["locomotion"],
        difficulty="beginner", modality="endurance", environment="anywhere",
        default_sets=3, default_reps="30s", default_rest="30-60s",
        is_compound=1, is_unilateral=0, movement_plane="multi_plane",
        swap_group="conditioning",
    ),
    "iso_lateral": dict(
        category="Chest",  # default; overridden for row variant
        muscles_primary=["pec-major-sternal"],
        muscles_secondary=["triceps", "delt-anterior"],
        movement_patterns=["horizontal-push"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        is_compound=1, is_unilateral=1, movement_plane="sagittal",
        swap_group="horizontal_push",
    ),
    "smith": dict(
        category="Legs",  # overridden per variant
        muscles_primary=[],
        muscles_secondary=[],
        movement_patterns=[],
        difficulty="intermediate", modality="strength", environment="gym",
        default_sets=4, default_reps="6-10", default_rest="90-180s",
        is_compound=1, is_unilateral=0, movement_plane="sagittal",
    ),
    "shrug_machine": dict(
        category="Back",
        muscles_primary=["upper-traps"],
        muscles_secondary=["mid-traps"],
        movement_patterns=["scapular-retraction"],
        difficulty="beginner", modality="strength", environment="gym",
        default_sets=3, default_reps="12-15", default_rest="60s",
        is_compound=0, is_unilateral=0, movement_plane="frontal",
        swap_group="shrug",
    ),
}


# Map each of the 133 NEW source names to (family, overrides).
# Overrides specify equipment + a 1-sentence description and optional cues.
# For variants that just change equipment, overrides=dict(equipment=[...]).
DRAFTS = {
    # === Bench Press variants ===
    "Bench Press (Cable)": ("bench_press", dict(
        equipment=["cable-machine", "flat-bench"],
        description="Cable bench press — constant tension throughout the press, easier on shoulders than barbell.",
        instructions="Set cables to chest height with handles. Lie on a flat bench between the stacks, palms facing forward. Press the handles up and slightly together until arms extend. Lower under control until handles are level with chest. Maintain tight scapular retraction.",
        cues=["constant cable tension", "press up and in", "drive elbows under hands"],
    )),
    "Bench Press (Smith Machine)": ("bench_press", dict(
        equipment=["smith-machine", "flat-bench"],
        description="Smith machine bench press — fixed bar path; useful for novices learning the press groove or training to failure safely.",
        instructions="Position a flat bench under the Smith bar so the bar lands mid-chest. Unrack with a slight wrist twist. Lower to the chest, pause briefly, drive back to lockout. Re-rack between sets.",
        cues=["bar to mid-chest", "twist to unrack", "elbows tracking 45° from torso"],
    )),
    # === Wide / close grip + 1-arm rows ===
    "Bench Press - Wide Grip (Barbell)": ("bench_press", dict(
        equipment=["barbell", "flat-bench"],
        description="Wide-grip barbell bench — emphasizes chest over triceps via a shorter range and external rotation bias.",
        instructions="Grip the bar 1.5x shoulder-width or wider. Unrack, lower under control to the lower chest, drive up and slightly back. Keep shoulder blades pinned to the bench.",
        cues=["wider than shoulder-width", "bar to lower chest", "elbows out 70-80°"],
    )),
    "Bent Over One Arm Row (Dumbbell)": ("row_bb", dict(
        equipment=["dumbbells"],
        is_unilateral=1,
        description="Single-arm bent-over row — emphasizes mid-back unilaterally; useful for addressing left/right imbalances.",
        instructions="Hinge at the hips with a flat back, one hand braced on a bench. Hold the dumbbell with a neutral grip. Row to the lower ribs, leading with the elbow. Pause briefly at the top.",
        cues=["elbow drives back", "row to lower ribs", "neutral spine"],
    )),
    "Bent Over Row - Underhand (Barbell)": ("row_bb", dict(
        equipment=["barbell"],
        description="Underhand-grip barbell row (Yates row) — more biceps and lower-lat involvement than overhand row, less stress on shoulders.",
        instructions="Grip the bar shoulder-width, palms up. Hinge to ~45°, keep a flat back. Row to the lower abs, driving elbows back behind the torso.",
        cues=["palms up grip", "elbows tucked, drive back", "to lower abs"],
    )),

    # === Curls ===
    "Bicep Curl (Machine)": ("bicep_curl", dict(
        equipment=["bicep-curl-machine"],
        description="Machine curl — fixed strength curve, easier to push to failure safely; good finisher.",
        instructions="Adjust seat so upper arms rest flat on the pad. Grip handles, curl up until forearms are vertical, lower under control.",
        cues=["elbows pinned to pad", "full extension at bottom", "slow eccentric"],
    )),
    "Reverse Curl (Band)": ("reverse_curl", dict(
        equipment=["band-medium"],
        description="Band reverse curl — overhand grip emphasizes brachioradialis + forearm extensors; band provides accommodating resistance.",
        instructions="Stand on the band, grip with palms down at hip width. Curl up to shoulder height keeping elbows pinned. Lower with control.",
        cues=["palms stay down", "elbows pinned", "no wrist break"],
    )),
    "Reverse Curl (Barbell)": ("reverse_curl", dict(
        equipment=["barbell"],
        description="Barbell reverse curl — overhand grip biases brachioradialis and forearm extensors; underrated for grip strength.",
        instructions="Grip the bar shoulder-width with palms down. Curl up to shoulder level keeping elbows pinned. Pause, lower under control.",
        cues=["palms down throughout", "no shrug or sway", "controlled tempo"],
    )),
    "Reverse Curl (Dumbbell)": ("reverse_curl", dict(
        equipment=["dumbbells"],
        description="Dumbbell reverse curl — same as barbell version but lets each arm work independently; spares wrist discomfort some get from a fixed bar.",
        instructions="Hold dumbbells with palms down. Curl up to shoulder height with elbows pinned to your sides. Lower slowly.",
        cues=["palms stay rotated down", "elbows static", "full ROM"],
    )),
    "Reverse Grip Concentration Curl (Dumbbell)": ("reverse_curl", dict(
        equipment=["dumbbells", "flat-bench"],
        is_unilateral=1,
        description="Seated reverse-grip concentration curl — isolates brachialis with a pronated grip and braced elbow.",
        instructions="Sit on a bench, elbow braced against the inside of the thigh. Hold the DB palm-down. Curl up to shoulder height, lower with control.",
        cues=["palm down throughout", "elbow stays braced", "no swing"],
    )),

    # === Cable / row variants ===
    "Cable Kickback": ("tricep_extension", dict(
        equipment=["cable-machine"],
        is_unilateral=1,
        description="Cable tricep kickback — long-head triceps isolation with smooth tension from the cable stack.",
        instructions="Set cable to low. Grip the handle, hinge ~45°, brace upper arm parallel to torso. Extend at the elbow only, locking out triceps. Return under control.",
        cues=["upper arm doesn't move", "lock out triceps", "no swing"],
    )),
    "Cable Row (Single Arm)": ("row_machine", dict(
        equipment=["cable-machine"],
        is_unilateral=1,
        muscles_primary=["lats", "mid-traps"],
        description="Single-arm cable row — unilateral horizontal pull; allows rotation through the trunk for slightly more lat activation.",
        instructions="Stand or kneel facing a low cable. Grip the handle, retract the shoulder, then row to the rib cage with elbow tracking back.",
        cues=["pull with the elbow", "feel mid-back squeeze", "control the return"],
    )),
    "Cable Twist": ("core_rotation", dict(
        equipment=["cable-machine"],
        description="Cable rotation (high-to-low or horizontal) — strong oblique work with continuous tension; foundation for rotational athletes.",
        instructions="Set cable at chest height. Stand sideways, arms extended. Rotate through the hips and core away from the stack, return slowly.",
        cues=["rotate from hips", "ribs over hips", "no arm chop"],
    )),
    "Cross Body Crunch": ("core_oblique", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        description="Cross-body crunch — couples a rectus crunch with rotation; effective oblique work with no equipment.",
        instructions="Lie supine, knees bent. Bring opposite elbow to opposite knee, crunching diagonally. Alternate sides each rep.",
        cues=["elbow to opposite knee", "no neck strain", "exhale on contraction"],
    )),

    # === Olympic / power ===
    "Clean (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        muscles_primary=["glutes", "hamstrings", "upper-traps"],
        muscles_secondary=["quadriceps", "delt-anterior", "forearm-flexors"],
        description="Barbell clean — full lift from floor to racked position via a front squat catch; foundational Olympic lift.",
        instructions="Start with the bar over mid-foot, shoulders over the bar. Extend hips and knees explosively, shrug, pull yourself under into a front squat. Stand up.",
        cues=["bar close to body", "triple extension", "fast elbows around"],
    )),
    "Clean and Jerk (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        muscles_primary=["full-body"],
        muscles_secondary=["delt-anterior", "triceps", "glutes"],
        description="Barbell clean and jerk — clean to front rack, then jerk overhead. The full competition Olympic lift.",
        instructions="Clean the bar to the front rack. Dip and drive the bar overhead, splitting feet (split jerk) or driving straight up (push jerk). Recover to standing with bar locked out.",
        cues=["dip is vertical", "drive then catch", "elbows lock fast"],
    )),
    "Deadlift High Pull (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        muscles_primary=["upper-traps", "delt-lateral", "glutes"],
        muscles_secondary=["hamstrings", "biceps"],
        difficulty="intermediate",
        description="Barbell deadlift high pull — explosive deadlift transitioning into an upright row; conditioning + posterior chain power.",
        instructions="Conventional deadlift setup. Stand up explosively, then continue the pull upward with high elbows to chin level. Lower under control.",
        cues=["fast off the floor", "elbows high and outside", "bar to chin"],
    )),
    "Hang Snatch (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        description="Hang snatch — Olympic snatch initiated from above the knee. Skips the floor pull; teaches the second pull and turnover.",
        instructions="Start with the bar at hang (above knee), snatch grip. Triple-extend explosively, shrug, pull yourself under into an overhead squat or power-snatch catch.",
        cues=["jump and shrug", "punch under the bar", "fast turnover"],
    )),
    "Jump Shrug (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        muscles_primary=["upper-traps", "glutes"],
        muscles_secondary=["hamstrings", "calves"],
        difficulty="intermediate",
        description="Barbell jump shrug — Olympic accessory teaching triple extension; bar stays low, focus is on aggressive hip drive.",
        instructions="Deadlift setup, snatch- or clean-width grip. Extend hips and knees explosively, finishing on the balls of the feet with a hard shrug. Bar travels minimally upward.",
        cues=["extend explosively", "high pull stops at hips", "land softly"],
    )),
    "Press Under (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        muscles_primary=["delt-anterior", "triceps"],
        muscles_secondary=["upper-traps", "core"],
        difficulty="advanced",
        description="Barbell press under (drop snatch) — Olympic teaching drill for the turnover. Trains the active receiving position in the snatch.",
        instructions="Bar in a back- or front-rack position with snatch grip. Dip slightly, then drop into an overhead squat catching the bar at lockout.",
        cues=["punch up as you drop", "land in deep squat", "bar locked overhead"],
    )),
    "Snatch (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        description="Barbell snatch — full lift from floor to overhead in one motion via an overhead squat catch.",
        instructions="Snatch-width grip over mid-foot. Pull the bar past the knees, extend explosively, pull under into a deep overhead squat. Stand up.",
        cues=["bar over the eyes overhead", "fast pull under", "punch and lock"],
    )),
    "Split Jerk (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        muscles_primary=["delt-anterior", "triceps", "glutes"],
        muscles_secondary=["quadriceps", "core"],
        description="Barbell split jerk — overhead lift from front rack, splitting feet in a lunge stance to catch.",
        instructions="Bar in front rack. Dip vertically, drive the bar overhead while splitting feet forward and back. Recover to standing.",
        cues=["dip is vertical", "drive then split", "bar locks before split lands"],
    )),
    "Sumo Deadlift High Pull (Barbell)": ("olympic", dict(
        equipment=["barbell"],
        muscles_primary=["upper-traps", "glutes", "delt-lateral"],
        muscles_secondary=["adductors", "quadriceps", "biceps"],
        difficulty="intermediate",
        description="Sumo deadlift high pull (SDHP) — CrossFit staple; conditioning movement combining sumo deadlift with an upright row finish.",
        instructions="Wide stance, bar between feet. Deadlift to extension, then pull bar to chin with high elbows. Reverse the motion smoothly.",
        cues=["wide stance, narrow grip", "elbows lead the pull", "bar to chin"],
    )),

    # === Chest dips ===
    "Chest Dip": ("dip", dict(
        equipment=["dip-station"],
        description="Chest dip — leaning forward biases the pectorals; a top-tier chest builder without a bench.",
        instructions="Mount the bars with arms straight. Lean torso forward ~30°, knees bent. Lower until upper arms are parallel to the floor, drive back to lockout.",
        cues=["torso leaned forward", "elbows flare 45°", "depth to parallel"],
    )),
    "Chest Dip (Assisted)": ("dip", dict(
        equipment=["dip-station", "band-medium"],
        difficulty="beginner",
        description="Band-assisted chest dip — band supports body weight, letting beginners build pressing strength through full range.",
        instructions="Loop a band across the dip handles and place a knee on it. Lean forward and lower under control, drive back to lockout.",
        cues=["knee on band", "lean forward through the rep", "full lockout"],
    )),

    # === Chest flies and presses ===
    "Chest Fly": ("chest_fly", dict(
        equipment=["pec-deck"],
        description="Pec-deck or machine chest fly — isolated horizontal adduction with safe shoulder mechanics.",
        instructions="Sit on the machine with handles at chest height. Bring handles together in front of the chest in an arc, pause and squeeze, return slowly.",
        cues=["squeeze chest at top", "slight elbow bend", "control the stretch"],
    )),
    "Chest Fly (Band)": ("chest_fly", dict(
        equipment=["band-medium"],
        environment="anywhere",
        description="Band chest fly — accommodating-resistance pec fly; great travel option.",
        instructions="Anchor a band behind you at chest height. Hold both ends, step forward to tension. Bring hands together in an arc, return under control.",
        cues=["arc the hands together", "small elbow bend", "feel pec stretch"],
    )),
    "Chest Press (Band)": ("chest_press_machine", dict(
        equipment=["band-medium"],
        environment="anywhere",
        difficulty="beginner",
        description="Band chest press — travel-friendly horizontal push with accommodating resistance.",
        instructions="Anchor a band behind you at chest height. Grip both ends, step forward to load. Press handles forward to extension, return under control.",
        cues=["press up and slightly in", "elbows tracking 45°", "tension at extension"],
    )),
    "Chest Press (Machine)": ("chest_press_machine", dict(
        equipment=["chest-press-machine"],
        description="Machine chest press — fixed plane chest press; easy to push to failure safely.",
        instructions="Set the seat so handles align with mid-chest. Press handles forward to extension, lower under control.",
        cues=["handles at mid-chest", "press through the palms", "slow eccentric"],
    )),

    # === Decline bench ===
    "Decline Bench Press (Barbell)": ("decline_bench_press", dict(
        equipment=["barbell", "adjustable-bench"],
        description="Decline barbell bench — emphasizes lower pec fibers; shorter range than flat bench.",
        instructions="Anchor feet on the decline bench pads. Unrack, lower to lower chest, drive up to lockout. Spotter recommended.",
        cues=["bar to lower chest", "drive elbows under bar", "stay tight on the bench"],
    )),
    "Decline Bench Press (Dumbbell)": ("decline_bench_press", dict(
        equipment=["dumbbells", "adjustable-bench"],
        description="Decline dumbbell bench — same lower-pec bias as barbell version but with independent arm work and deeper stretch.",
        instructions="Set bench to decline. Anchor feet, sit back with DBs. Press up to lockout, lower until DBs are at lower-chest level.",
        cues=["DBs press together at top", "control the stretch", "feet locked"],
    )),
    "Decline Bench Press (Smith Machine)": ("decline_bench_press", dict(
        equipment=["smith-machine", "adjustable-bench"],
        description="Decline Smith Machine press — fixed bar path, useful for solo training to failure.",
        instructions="Set a decline bench in the Smith rack so the bar lands at the lower chest. Press to lockout, lower under control.",
        cues=["align bar with lower chest", "lock feet", "twist to rack"],
    )),
    "Decline Crunch": ("core_crunch", dict(
        equipment=["adjustable-bench"],
        description="Decline crunch — increases ROM and load on rectus by adding bodyweight against gravity.",
        instructions="Set bench to decline, anchor feet. Lie back, hands at temples. Crunch up by curling shoulders toward hips, lower with control.",
        cues=["curl spine, don't sit up", "exhale on the crunch", "no neck pull"],
    )),

    # === Curls / pulldown machine ===
    "Drag Curl": ("bicep_curl", dict(
        equipment=["barbell"],
        description="Drag curl — pull the bar straight up along the torso by sliding elbows back; minimizes front-delt involvement.",
        instructions="Stand with a shoulder-width grip on the bar. Curl up by sliding elbows back, dragging the bar along your torso. Reverse the motion under control.",
        cues=["elbows slide back", "bar against torso", "no front-delt swing"],
    )),
    "Dragon Flag": ("core_crunch", dict(
        equipment=["flat-bench"],
        muscles_primary=["rectus-abdominis"],
        muscles_secondary=["external-obliques", "hip-flexors"],
        difficulty="advanced",
        default_sets=3, default_reps="5-8", default_rest="90s",
        description="Dragon flag — full-body lever core hold popularized by Bruce Lee. Elite-level anterior core strength.",
        instructions="Lie on a bench, grip an anchor behind your head. Brace hard, then lift legs and lower body together until vertical. Lower to horizontal as slowly as possible without letting hips sag.",
        cues=["rigid plank from shoulders down", "ribs down throughout", "slow eccentric"],
    )),

    # === Cardio machines / activities ===
    "Elliptical Machine": ("cardio_machine", dict(
        equipment=["elliptical"],
        description="Elliptical — low-impact cross-training cardio with synced upper and lower body work.",
        instructions="Adjust resistance and incline. Push with the legs while pulling with the arms. Maintain steady cadence.",
        cues=["upright posture", "push and pull through cycle", "smooth cadence"],
    )),
    "Jump Rope": ("conditioning", dict(
        equipment=["jump-rope"],
        environment="anywhere",
        movement_patterns=["jumping-landing"],
        default_sets=3, default_reps="60s", default_rest="60s",
        description="Jump rope — calf endurance, coordination, low-load conditioning. Foundational athletic skill.",
        instructions="Hold rope handles, wrists relaxed. Jump just high enough to clear the rope, landing softly on the balls of the feet.",
        cues=["wrists do the work", "stay on balls of feet", "small bounce"],
    )),
    "Jumping Jack": ("conditioning", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        movement_patterns=["jumping-landing"],
        default_sets=3, default_reps="30-60s", default_rest="30s",
        description="Jumping jacks — full-body warm-up and conditioning; raises heart rate and warms the shoulders.",
        instructions="Stand tall. Simultaneously jump feet out wide while raising arms overhead, then return. Maintain rhythm.",
        cues=["arms reach overhead", "land softly", "stay relaxed"],
    )),
    "Mountain Climber": ("conditioning", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["hip-flexors", "rectus-abdominis"],
        muscles_secondary=["delt-anterior", "quadriceps"],
        movement_patterns=["anti-extension", "hip-flexion"],
        default_sets=3, default_reps="30s", default_rest="30s",
        description="Mountain climber — dynamic plank with alternating knee drive; core endurance + conditioning.",
        instructions="Start in a push-up position. Drive one knee toward the chest, switch quickly to the other. Keep hips low and steady.",
        cues=["hips stay low", "fast knee drive", "no bouncing pelvis"],
    )),
    "High Knee Skips": ("conditioning", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        movement_patterns=["jumping-landing", "locomotion"],
        default_sets=3, default_reps="30m", default_rest="60s",
        description="High knee skips — running drill combining a skip with explosive knee drive; foundational for sprint mechanics.",
        instructions="Skip forward, driving one knee up toward chest height with each cycle. Stay tall, arms swing opposite to legs.",
        cues=["knee to chest height", "stay tall", "land on balls of feet"],
    )),
    "Rowing (Machine)": ("cardio_machine", dict(
        equipment=["rowing-erg"],
        muscles_primary=["lats", "glutes", "quadriceps"],
        muscles_secondary=["hamstrings", "rhomboids", "biceps"],
        movement_patterns=["horizontal-pull", "hip-hinge"],
        default_duration="20-30 min",
        description="Rowing erg — full-body cardio + posterior chain work; one of the best low-impact aerobic options.",
        instructions="Sit with feet strapped. Drive with the legs first, then hinge back, then pull the handle to the lower ribs. Reverse the order on the recovery.",
        cues=["legs, hips, arms", "drive heels through floor", "smooth slide back"],
    )),
    "Running (Treadmill)": ("cardio_machine", dict(
        equipment=["treadmill"],
        muscles_primary=["quadriceps", "calves", "glutes"],
        muscles_secondary=["hamstrings", "core"],
        movement_patterns=["locomotion"],
        default_duration="20-40 min",
        description="Treadmill running — controlled-pace cardio; useful for tempo work and intervals in any weather.",
        instructions="Set speed and incline. Maintain upright posture, midfoot strike, relaxed arms.",
        cues=["upright posture", "midfoot strike", "relaxed shoulders"],
    )),
    "Stair Climber": ("cardio_machine", dict(
        equipment=["stair-climber"],
        muscles_primary=["glutes", "quadriceps", "calves"],
        muscles_secondary=["hamstrings", "core"],
        movement_patterns=["step-up", "locomotion"],
        default_duration="15-30 min",
        description="Stair climber — sustained lower-body cardio with strong glute and quad emphasis.",
        instructions="Step up at a steady cadence, full foot on each step, hands off rails for harder work.",
        cues=["full foot on each step", "stand tall", "no leaning on rails"],
    )),
    "Assault Bike": ("cardio_machine", dict(
        equipment=["assault-bike"],
        muscles_primary=["full-body"],
        muscles_secondary=[],
        movement_patterns=["pedal-stroke"],
        default_duration="10-20 min",
        default_reps="30s on / 30s off",
        description="Assault bike / air bike — fan-resistance bike that scales with effort; brutally effective for HIIT and conditioning.",
        instructions="Sit upright, grip handles. Push and pull arms while pedaling, output scales with effort.",
        cues=["full body engagement", "drive through arms and legs", "settle breathing on rest"],
    )),

    # === Front raises ===
    "Front Raise (Band)": ("front_raise", dict(
        equipment=["band-medium"],
        environment="anywhere",
        description="Band front raise — anterior delt isolation with smooth resistance, easy to travel with.",
        instructions="Stand on the band, hold ends with palms down. Raise arms forward to shoulder height, lower with control.",
        cues=["thumbs up at top", "no swing", "slow eccentric"],
    )),
    "Front Raise (Barbell)": ("front_raise", dict(
        equipment=["barbell"],
        description="Barbell front raise — anterior delt isolation with both arms loaded together; useful when DB sizes are limited.",
        instructions="Hold a barbell with an overhand grip, hands shoulder-width. Raise to shoulder height with arms straight, lower under control.",
        cues=["no torso swing", "raise to chin level", "control the descent"],
    )),
    "Front Raise (Cable)": ("front_raise", dict(
        equipment=["cable-machine"],
        description="Cable front raise — constant tension on the anterior delt through the full range.",
        instructions="Set cable to low. Stand facing away, grip handle. Raise arm to shoulder height, lower under control.",
        cues=["face away from cable", "constant tension", "no shrug"],
    )),

    # === Front squat is CONFIRMED already, skip ===

    # === Back / glutes ===
    "Glute Kickback (Machine)": ("rdl", dict(
        equipment=["glute-kickback-machine"],
        muscles_primary=["glute-max"],
        muscles_secondary=["hamstrings"],
        movement_patterns=["hip-flexion"],
        difficulty="beginner",
        is_unilateral=1,
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="Glute kickback machine — single-leg hip extension with consistent loading; isolates glute max.",
        instructions="Position foot pad behind one leg. Extend the leg back by driving the heel, squeeze glutes at end-range.",
        cues=["drive heel back, not up", "squeeze at top", "no lower-back arch"],
    )),

    # === Push-up variants ===
    "Handstand Push Up": ("ohp", dict(
        equipment=["wall"],
        environment="anywhere",
        muscles_primary=["delt-anterior", "delt-lateral", "triceps"],
        muscles_secondary=["upper-traps", "core"],
        difficulty="advanced",
        default_sets=4, default_reps="3-8", default_rest="2-3 min",
        is_unilateral=0,
        description="Handstand push-up — bodyweight vertical press, premier shoulder strength + skill demonstration.",
        instructions="Kick up to a handstand against a wall. Lower until head taps the floor, press back to lockout.",
        cues=["full body line", "elbows track 45°", "tight core throughout"],
    )),
    "Kipping Pull Up": ("pull_up_variant", dict(
        equipment=["pull-up-bar"],
        difficulty="intermediate",
        description="Kipping pull-up — uses a coordinated hip drive to perform faster, higher-volume reps. CrossFit staple, not a strict strength exercise.",
        instructions="Hang from the bar with shoulders engaged. Swing into hollow → arch position. Use hip drive to pop the chin over the bar.",
        cues=["hollow → arch", "hip drive launches", "chin over bar"],
    )),
    "Push Up (Knees)": ("dip", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["pec-major-sternal", "triceps", "delt-anterior"],
        muscles_secondary=["core"],
        movement_patterns=["horizontal-push"],
        difficulty="beginner",
        default_sets=3, default_reps="8-15", default_rest="60s",
        description="Knee push-up — regression for the standard push-up; bears ~50% of body weight.",
        instructions="Plank position from the knees, hands shoulder-width. Lower chest to within a fist's distance of the floor, press up.",
        cues=["straight line shoulders to knees", "elbows 45°", "full ROM"],
    )),

    # === Knee / leg / hanging raises ===
    "Flat Knee Raise": ("core_hanging", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        default_sets=3, default_reps="12-15", default_rest="60s",
        difficulty="beginner",
        description="Lying knee raise — supine hip flexion + lower abdominal work; foundational core movement.",
        instructions="Lie supine, hands at sides for support. Bring knees toward chest by rolling hips up, lower with control.",
        cues=["curl pelvis up", "exhale at the top", "no leg drop momentum"],
    )),
    "Flat Leg Raise": ("core_hanging", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        default_sets=3, default_reps="10-15", default_rest="60s",
        difficulty="intermediate",
        description="Lying leg raise — supine straight-leg variant; loads hip flexors and rectus abdominis through a longer lever.",
        instructions="Lie supine. Raise straight legs to vertical, then lower without touching the floor. Press low back into the floor throughout.",
        cues=["press low back to floor", "slow on the way down", "no bouncing"],
    )),
    "Hanging Knee Raise": ("core_hanging", dict(
        equipment=["pull-up-bar"],
        difficulty="intermediate",
        default_sets=3, default_reps="10-15", default_rest="60-90s",
        description="Hanging knee raise — bring knees to chest from a dead hang. Builds anti-extension strength and grip endurance.",
        instructions="Hang from the bar with shoulders engaged. Bring knees to chest in a controlled arc, lower without swinging.",
        cues=["no swing or kip", "rib cage stays down", "controlled descent"],
    )),
    "Knee Raise (Captain's Chair)": ("core_hanging", dict(
        equipment=["captains-chair"],
        difficulty="beginner",
        default_sets=3, default_reps="12-20", default_rest="60s",
        description="Captain's chair knee raise — forearm-supported variant; easier on the grip than hanging versions.",
        instructions="Position forearms on the pads. Bring knees to chest by curling the pelvis up, lower under control.",
        cues=["curl pelvis up, not hip flex", "no shoulder shrug", "no swing"],
    )),
    "Toes To Bar Wait": ("core_hanging", dict(  # placeholder for matched draft
        equipment=["pull-up-bar"],
    )),
    "Knees to Elbows": ("core_hanging", dict(
        equipment=["pull-up-bar"],
        difficulty="advanced",
        default_sets=3, default_reps="5-10", default_rest="90-120s",
        description="Knees-to-elbows — hanging knee raise variant where the knees touch the elbows; CrossFit gymnastic skill.",
        instructions="Hang. Drive knees up and forward to touch the elbows. Control the descent without swinging.",
        cues=["pull knees through, not up", "compress hard at top", "no swing"],
    )),

    # === Iso-lateral machines ===
    "Iso-Lateral Chest Press (Machine)": ("iso_lateral", dict(
        equipment=["iso-lateral-machine"],
        description="Iso-lateral (plate-loaded) chest press — independent arm levers; useful for unilateral loading and addressing imbalances.",
        instructions="Set seat so handles align with mid-chest. Press each side independently or together. Lower under control.",
        cues=["even pressure both sides", "control the eccentric", "scap retracted"],
    )),
    "Iso-Lateral Row (Machine)": ("iso_lateral", dict(
        equipment=["iso-lateral-machine"],
        category="Back",
        muscles_primary=["lats", "mid-traps", "rhomboids"],
        muscles_secondary=["biceps", "delt-posterior"],
        movement_patterns=["horizontal-pull"],
        is_unilateral=1,
        swap_group="horizontal_pull",
        description="Iso-lateral (plate-loaded) row — chest-supported single-arm row; great for direct lat work with no spinal load.",
        instructions="Chest pressed into the pad. Row each handle to the rib cage, leading with the elbow. Squeeze at end-range.",
        cues=["lead with elbows", "squeeze at end-range", "no torso rotation"],
    )),
    "Incline Chest Fly (Dumbbell)": ("chest_fly", dict(
        equipment=["dumbbells", "adjustable-bench"],
        muscles_primary=["pec-major-clav"],
        muscles_secondary=["delt-anterior"],
        description="Incline DB fly — emphasizes the upper pec fibers through arc-of-motion adduction.",
        instructions="Set bench to 30-45°. Hold DBs above chest with slight elbow bend. Lower out wide in an arc, return to top.",
        cues=["slight elbow bend stays fixed", "stretch then squeeze", "controlled arc"],
    )),
    "Incline Chest Press (Machine)": ("chest_press_machine", dict(
        equipment=["chest-press-machine"],
        muscles_primary=["pec-major-clav"],
        muscles_secondary=["delt-anterior", "triceps"],
        description="Incline machine chest press — upper-chest emphasis with fixed plane; good failure work.",
        instructions="Adjust seat so handles align with upper chest. Press to extension, lower under control.",
        cues=["handles at clavicle", "drive elbows forward", "no shoulder shrug"],
    )),
    "Incline Row (Dumbbell)": ("row_bb", dict(
        equipment=["dumbbells", "adjustable-bench"],
        difficulty="beginner",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        description="Incline chest-supported DB row — supported variant removes lower-back demand, isolates the back.",
        instructions="Set bench to ~30°. Lie chest-down. Row DBs with elbows tracking past torso, squeeze mid-back.",
        cues=["chest stays on bench", "elbows back, not up", "pause at top"],
    )),
    "Inverted Row (Bodyweight)": ("row_bb", dict(
        equipment=["barbell", "squat-rack"],
        difficulty="beginner",
        default_sets=3, default_reps="6-15", default_rest="60-90s",
        description="Inverted row (Australian pull-up) — bodyweight horizontal pull; foundational rowing pattern for beginners.",
        instructions="Set a bar at hip height. Lie under it, grip overhand. Pull chest to bar in a straight body line, lower with control.",
        cues=["straight line head to heel", "pull chest to bar", "no hip sag"],
    )),

    # === Crunch / sit-up family ===
    "Crunch (Machine)": ("core_crunch", dict(
        equipment=["captains-chair"],  # often a generic ab crunch machine
        difficulty="beginner",
        description="Machine crunch — loaded rectus work with consistent tension; lets you push to failure safely.",
        instructions="Sit in the machine with handles over shoulders. Curl spine to crunch; control the return.",
        cues=["curl, don't bend", "exhale on crunch", "slow eccentric"],
    )),
    "Crunch (Stability Ball)": ("core_crunch", dict(
        equipment=["stability-ball"],
        environment="anywhere",
        description="Stability ball crunch — larger ROM than a floor crunch; the ball lets you extend over the back.",
        instructions="Lie back on a ball with low back supported. Crunch by curling shoulders toward hips, return to a slight back-extended position.",
        cues=["full extension over ball", "exhale on contraction", "no neck pull"],
    )),
    "Jackknife Sit Up": ("core_crunch", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["rectus-abdominis", "hip-flexors"],
        difficulty="intermediate",
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="V-up / jackknife — simultaneous reach of arms and legs to meet over the body; demanding flexion movement.",
        instructions="Lie supine, arms overhead. In one motion, raise legs and torso to meet, reaching hands toward feet. Reverse with control.",
        cues=["meet in the middle", "control descent", "no momentum"],
    )),
    "Oblique Crunch": ("core_oblique", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        description="Oblique crunch — side-lying or rotational crunch targeting the obliques.",
        instructions="Lie supine with knees bent and dropped to one side. Crunch up while keeping legs to the side. Switch sides each set.",
        cues=["knees stay dropped", "lift shoulder off floor", "exhale on contraction"],
    )),
    "Reverse Plank": ("core_crunch", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["glutes", "erector-thoracic", "delt-posterior"],
        muscles_secondary=["hamstrings", "triceps"],
        movement_patterns=["anti-extension"],
        default_sets=3, default_reps="20-45s", default_rest="60s",
        description="Reverse plank — supine plank hold supporting body weight on hands and heels; posterior chain isometric.",
        instructions="Sit with legs extended. Place hands behind hips. Lift body to a straight line from heels to chin, hold.",
        cues=["chest up, hips high", "squeeze glutes", "press through palms"],
    )),
    "Russian Twist Wait": ("core_rotation", dict(  # placeholder
        equipment=["medicine-ball"],
    )),

    # === Lat pulldown variants ===
    "Lat Pulldown (Cable)": ("lat_pulldown", dict(
        equipment=["cable-machine", "lat-pulldown"],
        description="Cable lat pulldown — vertical pulling staple; scaled by stack weight.",
        instructions="Grip bar wider than shoulder-width. Pull bar to upper chest by driving elbows down and back. Control the return.",
        cues=["drive elbows down", "chest up to bar", "no lean back"],
    )),
    "Lat Pulldown (Machine)": ("lat_pulldown", dict(
        equipment=["lat-pulldown"],
        description="Machine lat pulldown (selectorized) — same movement as cable but with a fixed-frame machine.",
        instructions="Set thigh pads. Grip the bar, pull to upper chest, control the return.",
        cues=["full lat stretch at top", "elbows down and back", "slow eccentric"],
    )),
    "Lat Pulldown (Single Arm)": ("lat_pulldown", dict(
        equipment=["cable-machine"],
        is_unilateral=1,
        description="Single-arm cable lat pulldown — unilateral pulling, lets the lat fully shorten without contralateral interference.",
        instructions="Stand or kneel. Grip a single handle, pull elbow down and back to the ribs. Switch sides each set.",
        cues=["pull elbow to ribs", "rotate slightly at end-range", "full stretch at top"],
    )),
    "Lat Pulldown - Underhand (Band)": ("lat_pulldown", dict(
        equipment=["band-heavy", "pull-up-bar"],
        environment="anywhere",
        difficulty="beginner",
        description="Band underhand pulldown — supinated grip biases lower lats and biceps; portable lat work.",
        instructions="Anchor band overhead. Kneel, grip palms-up, pull to chest. Control the return.",
        cues=["palms up", "elbows tucked", "to chest"],
    )),
    "Lat Pulldown - Underhand (Cable)": ("lat_pulldown", dict(
        equipment=["cable-machine", "lat-pulldown"],
        description="Underhand cable pulldown — supinated grip emphasizes lower lats + biceps.",
        instructions="Grip bar palms-up, shoulder-width. Pull to upper chest with elbows tucked. Control the return.",
        cues=["palms up grip", "elbows close to ribs", "squeeze at chest"],
    )),

    # === Lunges ===
    "Lunge (Barbell)": ("lunge", dict(
        equipment=["barbell"],
        description="Barbell forward lunge — loaded unilateral squat pattern; great single-leg builder.",
        instructions="Bar on traps. Step forward with one leg, lower until back knee almost touches floor. Drive through front heel to stand.",
        cues=["torso upright", "front knee tracks toes", "drive through heel"],
    )),
    "Lunge (Bodyweight)": ("lunge", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        difficulty="beginner",
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="Bodyweight forward lunge — accessible single-leg pattern; foundational movement quality work.",
        instructions="Step forward, lower until back knee nears floor. Stand back to start. Alternate or work one side at a time.",
        cues=["torso upright", "control depth", "step back to start"],
    )),
    "Lunge (Dumbbell)": ("lunge", dict(
        equipment=["dumbbells"],
        description="Dumbbell forward lunge — loaded lunge with goblet or hands-at-side carry.",
        instructions="Hold DBs at sides. Step forward, lower under control until back knee approaches floor. Drive through front heel to stand.",
        cues=["DBs at sides", "front knee tracks toes", "smooth stand-up"],
    )),

    # === Misc movements ===
    "Ab Wheel": ("core_crunch", dict(
        equipment=["ab-wheel"],
        environment="anywhere",
        muscles_primary=["rectus-abdominis"],
        muscles_secondary=["external-obliques", "lats"],
        movement_patterns=["anti-extension"],
        difficulty="intermediate",
        default_sets=3, default_reps="6-12", default_rest="60-90s",
        description="Ab wheel rollout (kneeling) — anti-extension core work; the floor presses on the abs as the body extends.",
        instructions="Kneel, grip the wheel. Roll forward as far as you can while keeping ribs down and hips locked. Pull back to start.",
        cues=["ribs stay down", "no hip sag", "exhale on the roll-out"],
    )),
    "Around the World": ("chest_fly", dict(
        equipment=["dumbbells", "flat-bench"],
        muscles_primary=["pec-major-clav", "delt-anterior"],
        difficulty="beginner",
        default_sets=3, default_reps="10-12", default_rest="60s",
        description="Around-the-world — semi-circular DB fly variation that hits clavicular pec + front delt through a continuous arc.",
        instructions="Lie on a flat bench, DBs at hip level palms-up. Arc DBs out and overhead in a wide semicircle; reverse the arc back.",
        cues=["wide arc, not lift", "soft elbows", "smooth tempo"],
    )),
    "Back Extension": ("rdl", dict(
        equipment=["ghd"],
        muscles_primary=["erector-lumbar", "glutes"],
        muscles_secondary=["hamstrings"],
        difficulty="beginner",
        default_sets=3, default_reps="10-15", default_rest="60-90s",
        description="Back extension — hyperextension work on a 45° or 90° pad; isolates lumbar erectors and glutes.",
        instructions="Anchor feet on the pad, hips against the rest. Lower torso under control, then extend to a neutral spine. Don't hyperextend at the top.",
        cues=["finish at neutral, not hyperextended", "squeeze glutes", "smooth tempo"],
    )),
    "Back Extension (Machine)": ("rdl", dict(
        equipment=["back-extension-machine"],
        muscles_primary=["erector-lumbar", "glutes"],
        muscles_secondary=["hamstrings"],
        difficulty="beginner",
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="Seated back extension machine — loaded lumbar extension; useful for isolating the erectors when the GHD isn't an option.",
        instructions="Set the seat so the pad sits on the upper back. Press back into a slight extension, control the return.",
        cues=["small ROM at end-range", "no jerking", "exhale on the press"],
    )),
    "Ball Slams": ("conditioning", dict(
        equipment=["slam-ball"],
        environment="anywhere",
        muscles_primary=["lats", "core", "glutes"],
        muscles_secondary=["shoulders"],
        movement_patterns=["throwing-casting"],
        default_sets=3, default_reps="10", default_rest="60s",
        description="Medicine ball / slam-ball slams — full-body conditioning, anti-extension via overhead pull-down power.",
        instructions="Hold the ball overhead. Slam it down hard between your feet, hinge at the hips and let the ball's bounce die.",
        cues=["full extension overhead", "slam through the floor", "exhale hard on slam"],
    )),
    "Battle Ropes": ("conditioning", dict(
        equipment=["battle-ropes"],
        muscles_primary=["shoulders", "core"],
        muscles_secondary=["upper-traps", "biceps"],
        movement_patterns=["scapular-protraction"],
        default_sets=3, default_reps="30s", default_rest="30-60s",
        description="Battle ropes — alternating-wave or double-wave conditioning; full upper body + core.",
        instructions="Grip the rope ends. In a quarter squat, drive waves alternately or together up and down the rope.",
        cues=["small quarter squat", "drive from shoulders", "consistent waves"],
    )),
    "Bench Dip": ("dip", dict(
        equipment=["flat-bench"],
        environment="anywhere",
        muscles_primary=["triceps", "pec-major-sternal"],
        muscles_secondary=["delt-anterior"],
        difficulty="beginner",
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="Bench dip — beginner dip variant; less shoulder demand than parallel bar dip.",
        instructions="Sit on the edge of a bench, hands beside hips. Walk feet out, lower body until elbows reach ~90°, press back up.",
        cues=["elbows track back", "no shoulder shrug", "press through palms"],
    )),
    "Bicep Curl (Barbell)": ("bicep_curl", dict(
        equipment=["barbell"],
        description="Barbell biceps curl — bilateral biceps loading with maximal mechanical advantage; foundational arm work.",
        instructions="Stand with feet hip-width, grip the bar palms-up at shoulder width. Curl up to chest level, lower with control.",
        cues=["elbows pinned to sides", "no body sway", "full extension at bottom"],
    )),
    "Bicep Curl (Cable)": ("bicep_curl", dict(
        equipment=["cable-machine"],
        description="Cable curl — continuous tension throughout the lift; great for biceps hypertrophy work.",
        instructions="Stand facing a low cable with a straight or EZ bar attachment. Curl up keeping elbows pinned. Lower under control.",
        cues=["elbows static", "tension at top and bottom", "no swing"],
    )),
    "Bicep Curl (Dumbbell)": ("bicep_curl", dict(
        equipment=["dumbbells"],
        description="Dumbbell curl — independent arm work; can be done alternating or simultaneous.",
        instructions="Hold DBs palm-in. Curl up rotating to palms-up at the top. Lower under control to fully extended.",
        cues=["supinate as you curl", "no elbow drift", "squeeze at top"],
    )),
    "Wrist Roller Wait": ("front_raise", dict(  # placeholder
        equipment=["barbell"],
    )),

    # === Calf raises / calf press ===
    "Calf Press on Leg Press": ("calf_raise", dict(
        equipment=["leg-press"],
        description="Calf press on the leg-press machine — heavy loadable calf work without spinal compression.",
        instructions="Position balls of feet on the lower edge of the press platform. Press up through the toes to full plantarflexion, lower under control.",
        cues=["full stretch at bottom", "press through balls of feet", "knees stay slightly bent"],
    )),
    "Calf Press on Seated Leg Press": ("calf_raise", dict(
        equipment=["leg-press"],
        description="Seated leg-press calf press — same movement as standard leg-press calf raise but on the seated variant.",
        instructions="Balls of feet at lower edge of plate. Press through the toes, return slowly to a stretch.",
        cues=["control the stretch", "press through big toe", "no knee bounce"],
    )),
    "Standing Calf Raise (Barbell)": ("calf_raise", dict(
        equipment=["barbell"],
        description="Barbell standing calf raise — old-school heavy calf loading with the bar on the traps.",
        instructions="Bar on traps. Stand with balls of feet on a block. Press up to full plantarflexion, lower under control to stretch.",
        cues=["full ROM both directions", "knees straight", "pause at top"],
    )),
    "Standing Calf Raise (Bodyweight)": ("calf_raise", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        difficulty="beginner",
        default_sets=3, default_reps="20-30", default_rest="30s",
        description="Bodyweight standing calf raise — basic calf endurance work, can be done anywhere.",
        instructions="Stand with balls of feet on the edge of a step. Press up through the toes, lower into a deep stretch.",
        cues=["balls of feet only", "full stretch at bottom", "no bounce"],
    )),
    "Standing Calf Raise (Dumbbell)": ("calf_raise", dict(
        equipment=["dumbbells"],
        description="Dumbbell standing calf raise — single- or double-DB variant; can be done one-leg-at-a-time for added load.",
        instructions="Hold DBs at sides. Stand with balls of feet on a block. Press up, lower under control.",
        cues=["one-leg variant for more load", "pause at top", "deep stretch"],
    )),
    "Standing Calf Raise (Machine)": ("calf_raise", dict(
        equipment=["leg-press"],  # generic standing calf raise machine
        description="Standing calf raise machine — pad-on-traps calf work, easy to load heavy.",
        instructions="Position shoulders under the pads, balls of feet on the platform. Press up, lower into a stretch.",
        cues=["full ROM", "no knee bend", "pause at top"],
    )),
    "Standing Calf Raise (Smith Machine)": ("calf_raise", dict(
        equipment=["smith-machine"],
        description="Smith machine calf raise — fixed bar path, easy to add heavy load on the traps.",
        instructions="Bar on traps. Balls of feet on a small block. Press up to full plantarflexion, lower into a stretch.",
        cues=["bar drives straight up", "feet on block for stretch", "no knee bend"],
    )),

    # === Side bends ===
    "Side Bend (Band)": ("side_bend", dict(
        equipment=["band-medium"],
        environment="anywhere",
        description="Banded side bend — lateral flexion against accommodating resistance; oblique work.",
        instructions="Stand on the band, hold one end at the hip. Bend laterally toward the band side, return upright. Switch sides.",
        cues=["pure lateral motion", "no twisting", "controlled tempo"],
    )),
    "Side Bend (Cable)": ("side_bend", dict(
        equipment=["cable-machine"],
        description="Cable side bend — constant tension lateral flexion; reliable oblique loading.",
        instructions="Set low cable. Grip handle at side, bend away from the stack, return upright.",
        cues=["face squarely forward", "no rotation", "full but small ROM"],
    )),
    "Side Bend (Dumbbell)": ("side_bend", dict(
        equipment=["dumbbells"],
        description="DB side bend — classic oblique loading; one DB per side held at arm's length.",
        instructions="Hold a DB at one side. Bend at the waist toward the DB side, return to upright. Switch sides.",
        cues=["DB stays close to body", "no twist", "controlled descent"],
    )),

    # === Squat variants ===
    "Pistol Squat": ("single_leg_squat", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        difficulty="advanced",
        default_sets=3, default_reps="5-8", default_rest="90-120s",
        description="Pistol squat — full single-leg squat to depth with the other leg extended forward. Premier bodyweight leg builder.",
        instructions="Stand on one leg, arms forward for balance. Lower into a deep squat, free leg extending forward. Stand back up without the foot touching down.",
        cues=["heel stays planted", "free leg stays parallel", "torso leans for balance"],
    )),
    "Squat (Band)": ("squat", dict(
        equipment=["band-medium"],
        environment="anywhere",
        difficulty="beginner",
        default_sets=3, default_reps="12-20", default_rest="60s",
        description="Band squat — air squat with a band loaded across the shoulders or under the feet; portable progressive resistance.",
        instructions="Loop band over shoulders and stand on it. Squat to depth, return to standing.",
        cues=["band loaded but not slack at top", "knees track toes", "full depth"],
    )),
    "Squat (Barbell)": ("squat", dict(
        equipment=["barbell", "squat-rack"],
        description="Barbell back squat — the foundational compound leg lift. Bar on traps, full-depth squat.",
        instructions="Unrack the bar onto the upper traps or rear delts. Step back, set stance. Squat to at-or-below parallel, drive through the floor to stand.",
        cues=["chest up, brace hard", "knees track toes", "drive floor away"],
    )),
    "Squat (Bodyweight)": ("squat", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        difficulty="beginner",
        default_sets=3, default_reps="15-25", default_rest="60s",
        description="Bodyweight squat — foundational movement quality and endurance work.",
        instructions="Stand feet shoulder-width. Squat to at-or-below parallel keeping the chest up. Drive through the floor to stand.",
        cues=["sit back and down", "knees out", "full depth"],
    )),
    "Squat (Dumbbell)": ("squat", dict(
        equipment=["dumbbells"],
        description="Dumbbell squat — DBs at sides or goblet-held; accessible loaded squat option.",
        instructions="Hold DBs at sides or at the chest. Squat to depth, drive through the floor to stand.",
        cues=["chest up", "knees out", "DBs steady"],
    )),
    "Squat (Machine)": ("squat", dict(
        equipment=["hack-squat"],
        description="Machine squat (hack squat or leg-press squat variant) — squat pattern with reduced spinal load.",
        instructions="Set shoulder pads, place feet shoulder-width. Squat to depth, press through the floor to stand.",
        cues=["heels stay down", "full depth", "drive into the pad"],
    )),
    "Squat (Smith Machine)": ("squat", dict(
        equipment=["smith-machine"],
        description="Smith machine squat — fixed bar path. Useful for novices learning the squat groove or for training to failure solo.",
        instructions="Position bar on traps. Step feet slightly forward of the bar line. Squat to depth, drive up.",
        cues=["feet slightly forward of bar", "rotate to unrack", "full depth"],
    )),
    "Overhead Squat (Barbell)": ("squat", dict(
        equipment=["barbell"],
        muscles_primary=["quadriceps", "glutes", "delt-anterior"],
        muscles_secondary=["upper-traps", "core", "lats"],
        difficulty="advanced",
        description="Overhead squat — squat with the bar locked out overhead. Demanding mobility + stability test; Olympic accessory.",
        instructions="Hold a snatch-grip bar locked out overhead. Squat to depth keeping the bar over the heels. Stand up.",
        cues=["bar over the heels", "active shoulders", "elbows locked"],
    )),
    "Zercher Squat (Barbell)": ("squat", dict(
        equipment=["barbell"],
        muscles_primary=["quadriceps", "glutes", "biceps"],
        muscles_secondary=["upper-traps", "core"],
        difficulty="advanced",
        description="Zercher squat — bar held in the crooks of the elbows; demands a strong upper back and brace.",
        instructions="Cradle the bar in the elbow crooks. Squat to depth keeping the bar tight to the body. Stand up.",
        cues=["bar tight to chest", "elbows up", "full depth"],
    )),

    # === Deadlift variants ===
    "Deadlift (Band)": ("deadlift", dict(
        equipment=["band-heavy"],
        environment="anywhere",
        difficulty="beginner",
        default_sets=3, default_reps="10-15", default_rest="60-90s",
        description="Band deadlift — accommodating resistance hip hinge; great for grooving the pattern.",
        instructions="Stand on the band, grip with both hands at the hips. Hinge forward, then drive hips through to stand.",
        cues=["push floor away", "hips and shoulders rise together", "lock out at top"],
    )),
    "Deadlift (Dumbbell)": ("deadlift", dict(
        equipment=["dumbbells"],
        description="Dumbbell deadlift — DBs at sides; foundational hinge with reduced setup demands vs. barbell.",
        instructions="Hold DBs at sides. Hinge at the hips while bending the knees, lower DBs along the legs, drive through the floor to stand.",
        cues=["bar replaced by DB path along legs", "brace hard", "lock out hips"],
    )),
    "Deadlift (Smith Machine)": ("deadlift", dict(
        equipment=["smith-machine"],
        description="Smith machine deadlift — fixed bar path. Easier setup but limits the hinge mechanics; better suited as accessory.",
        instructions="Set bar at mid-shin. Grip overhand, drive through the floor to lock out. Lower under control.",
        cues=["fixed path forces vertical pull", "brace hard", "lock out hips"],
    )),
    "Rack Pull (Barbell)": ("deadlift", dict(
        equipment=["barbell", "squat-rack"],
        difficulty="intermediate",
        default_sets=4, default_reps="3-5", default_rest="2-3 min",
        description="Rack pull — partial deadlift from blocks or pins, usually starting at the knees. Heavy lockout work + traps.",
        instructions="Set pins at the knee. Grip the bar, brace, pull from pins to lockout. Lower under control.",
        cues=["heavy lockout", "drive hips through", "stay over the bar"],
    )),
    "Stiff Leg Deadlift (Dumbbell)": ("rdl", dict(
        equipment=["dumbbells"],
        description="DB stiff-leg deadlift — straight-knee hinge, deep hamstring stretch.",
        instructions="Hold DBs in front of thighs. Hinge at the hips with minimal knee bend, lower DBs along the legs to a stretch. Reverse to standing.",
        cues=["small knee bend, fixed", "feel hamstring stretch", "neutral spine"],
    )),
    "Straight Leg Deadlift (Band)": ("rdl", dict(
        equipment=["band-heavy"],
        environment="anywhere",
        description="Band straight-leg deadlift — straight-knee hinge with band resistance; great hip-hinge primer.",
        instructions="Stand on the band, grip with both hands. With minimal knee bend, hinge to a stretch in the hamstrings, reverse to standing.",
        cues=["hinge from hips", "straight knees throughout", "stretch then drive"],
    )),

    # === Hip thrust variants are CONFIRMED already; skip ===

    # === OHP variants ===
    "Overhead Press (Smith Machine)": ("ohp", dict(
        equipment=["smith-machine"],
        description="Smith machine overhead press — fixed bar path; good for solo training and progressive overload.",
        instructions="Set bench upright if seated. Position bar at clavicle. Press to lockout, lower under control.",
        cues=["bar over crown of head at top", "no shoulder shrug", "full lockout"],
    )),
    "Seated Overhead Press (Barbell)": ("ohp", dict(
        equipment=["barbell", "adjustable-bench"],
        description="Seated barbell OHP — removes leg drive, isolating the shoulders; great strict pressing work.",
        instructions="Sit on an upright bench. Press bar from clavicle to lockout overhead. Lower under control.",
        cues=["braced against bench", "no back arch", "lock out elbows"],
    )),
    "Seated Overhead Press (Dumbbell)": ("ohp", dict(
        equipment=["dumbbells", "adjustable-bench"],
        description="Seated dumbbell OHP — independent arm work, shorter ROM than barbell, no risk of bar in the face.",
        instructions="Sit upright. Hold DBs at shoulder height, palms forward. Press to lockout, lower under control.",
        cues=["press to lockout", "no body sway", "control the eccentric"],
    )),
    "Strict Military Press (Barbell)": ("ohp", dict(
        equipment=["barbell"],
        description="Strict military press — bar from clean rack, feet together, no leg drive. Old-school standing press.",
        instructions="Bar in front rack, feet together. Press strictly overhead, no knee bend or hip drive. Lower under control.",
        cues=["feet together", "no leg drive", "strict press"],
    )),
    "Shoulder Press (Machine)": ("ohp", dict(
        equipment=["shoulder-press-machine"],
        difficulty="beginner",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        description="Machine shoulder press — fixed-plane pressing; good for high-volume shoulder work and failure training.",
        instructions="Sit with handles at shoulder height. Press up to lockout, lower under control.",
        cues=["handles at shoulder height", "full lockout", "controlled tempo"],
    )),
    "Shoulder Press (Plate Loaded)": ("ohp", dict(
        equipment=["iso-lateral-machine"],
        difficulty="beginner",
        default_sets=3, default_reps="8-12", default_rest="60-90s",
        description="Plate-loaded shoulder press — usually iso-lateral plate-loaded press. Strong, fixed-path overhead work.",
        instructions="Sit with handles at shoulders. Press to lockout, lower under control.",
        cues=["press evenly both sides", "no shrug", "lockout"],
    )),

    # === Misc isolation / niche ===
    "Bench Press (Cable)Wait": ("bench_press", dict(equipment=["cable-machine"])),  # placeholder
    "Cuban Press": ("ohp", dict(
        equipment=["dumbbells"],
        muscles_primary=["delt-posterior", "rotator-cuff"],
        muscles_secondary=["delt-anterior", "upper-traps"],
        difficulty="intermediate",
        default_sets=3, default_reps="8-12", default_rest="60s",
        description="Cuban press — upright row into external rotation into overhead press; rotator-cuff prehab + posterior delt work.",
        instructions="Hold light DBs at hip. Pull elbows up (upright row) to shoulder height, then rotate forearms up to ear height, then press overhead. Reverse the sequence.",
        cues=["light load", "control rotation phase", "all three positions smooth"],
    )),
    "External Rotation": ("ohp", dict(
        equipment=["band-light"],
        environment="anywhere",
        muscles_primary=["rotator-cuff", "infraspinatus", "teres-minor"],
        muscles_secondary=["delt-posterior"],
        movement_patterns=["scapular-retraction"],
        difficulty="beginner",
        is_unilateral=1,
        default_sets=3, default_reps="12-15", default_rest="45s",
        description="Banded external rotation — rotator-cuff prehab; one of the most prescribed shoulder-health exercises.",
        instructions="Anchor a light band at elbow height. Grip with the far hand, elbow pinned at 90° to your side. Rotate the forearm outward away from your body, control the return.",
        cues=["elbow stays pinned", "rotate from shoulder, not wrist", "slow eccentric"],
    )),
    "L-Sit": ("core_crunch", dict(
        equipment=["parallettes"],
        environment="anywhere",
        muscles_primary=["rectus-abdominis", "hip-flexors"],
        muscles_secondary=["triceps", "delt-anterior", "quadriceps"],
        movement_patterns=["anti-extension"],
        difficulty="advanced",
        default_sets=4, default_reps="10-20s", default_rest="60-90s",
        description="L-Sit — gymnastic core hold with legs out parallel to floor while supported on hands. Brutal compression strength.",
        instructions="Press up on parallettes (or floor) with arms straight. Lift legs to horizontal, hold without letting hips drop.",
        cues=["depress shoulders", "compress hips", "toes pointed"],
    )),
    "Landmine RDL": ("rdl", dict(
        equipment=["barbell", "landmine"],
        muscles_primary=["hamstrings", "glutes"],
        muscles_secondary=["erector-lumbar"],
        description="Landmine RDL — hip hinge with one end of the bar anchored; smoother path than a barbell RDL.",
        instructions="Anchor one end of the bar in a landmine. Stand at the free end, hold the bar in both hands. Hinge to a stretch, drive hips through to stand.",
        cues=["hinge from hips", "knees slightly bent", "drive hips forward"],
    )),
    "Landmine Row": ("row_bb", dict(
        equipment=["barbell", "landmine"],
        is_unilateral=1,
        description="Landmine T-bar row — landmine-anchored barbell rowed bent-over; strong horizontal pull with reduced spinal load.",
        instructions="Anchor one end of the bar. Straddle the free end, hinge to ~45°. Grip the bar (V-handle or hands). Row to the sternum.",
        cues=["row to sternum", "elbows tucked", "chest up"],
    )),
    "Landmine Squat": ("squat", dict(
        equipment=["barbell", "landmine"],
        description="Landmine squat — bar held at chest with one end anchored; provides a stable arc, useful for novices and rehab.",
        instructions="Hold the free end of the bar at the chest. Squat to depth, drive up. The bar follows a slight arc; allow this naturally.",
        cues=["bar at chest", "let the arc happen", "full depth"],
    )),

    # === Box squat (alias) is in Aliases; we have Box Squat (Barbell)? Check classification CSV ===
    # NEW list also includes the borderline NEW items the user opted to keep.
    # We add Box Squat Barbell from the source list:
    "Box Squat (Barbell)Wait": ("squat", dict(equipment=["barbell", "plyo-box"])),  # placeholder

    # === Misc ===
    "Cable Crossover Wait": ("chest_fly", dict(equipment=["cable-crossover"])),  # placeholder
    "Decline Crunch Wait": ("core_crunch", dict(equipment=["adjustable-bench"])),  # placeholder
    "Glute Ham Raise Wait": ("rdl", dict(equipment=["ghd"])),  # placeholder

    # === Power, Snatch, etc ===
    "Hang Power Clean Wait": ("olympic", dict(equipment=["barbell"])),  # placeholder

    # === Curl variants from above with extra mapping ===
    "Hammer Curl (Band)Wait": ("bicep_curl", dict(equipment=["band-medium"])),  # placeholder
    "Hammer Curl (Cable)Wait": ("bicep_curl", dict(equipment=["cable-machine"])),  # placeholder

    # === Pull-up assisted variants ===
    "Pull Up (Assisted)Wait": ("pull_up_variant", dict(equipment=["pull-up-bar", "band-heavy"])),  # placeholder
    "Pull Up (Band)Wait": ("pull_up_variant", dict(equipment=["pull-up-bar", "band-heavy"])),  # placeholder

    # === Sit Up variants ===
    "Sit Up Wait": ("core_crunch", dict(equipment=["bodyweight"])),  # placeholder

    # === Push Up variants ===
    "Push Up (Band)Wait": ("dip", dict(equipment=["band-medium", "bodyweight"])),  # placeholder

    # === Misc Olympic ===
    "Power Clean Wait": ("olympic", dict(equipment=["barbell"])),  # placeholder
    "Power Snatch (Barbell)Wait": ("olympic", dict(equipment=["barbell"])),  # placeholder
    "Push Press Wait": ("ohp", dict(equipment=["barbell"])),  # placeholder

    # === Misc Tricep ===
    "Tricep Rope Pushdown Wait": ("tricep_pushdown", dict(equipment=["cable-machine"])),  # placeholder
    "Triceps Dip": ("dip", dict(
        equipment=["dip-station"],
        category="Arms",
        muscles_primary=["triceps", "pec-major-sternal"],
        muscles_secondary=["delt-anterior"],
        description="Triceps dip — upright torso bias on parallel bars; emphasizes triceps over chest vs. the chest dip variant.",
        instructions="Mount the bars, arms straight, torso upright. Lower until upper arms reach parallel, drive back to lockout.",
        cues=["torso upright", "elbows track straight back", "lockout fully"],
    )),
    "Triceps Dip (Assisted)": ("dip", dict(
        equipment=["dip-station", "band-medium"],
        category="Arms",
        muscles_primary=["triceps"],
        muscles_secondary=["pec-major-sternal", "delt-anterior"],
        difficulty="beginner",
        description="Band-assisted triceps dip — band supports body weight, lets beginners build lockout strength.",
        instructions="Loop band across dip handles, kneel into the band. Lower torso upright, drive back to lockout.",
        cues=["torso upright", "band assists evenly", "lockout"],
    )),
    "Triceps Extension": ("tricep_extension", dict(
        equipment=["dumbbells"],
        is_unilateral=1,
        description="Single-arm overhead triceps extension — long-head emphasis with a fully stretched starting position.",
        instructions="Hold a DB overhead with one arm. Lower behind the head by bending the elbow only, extend back to lockout.",
        cues=["upper arm vertical", "elbow next to ear", "full stretch"],
    )),
    "Triceps Extension (Barbell)": ("tricep_extension", dict(
        equipment=["barbell"],
        description="Overhead barbell triceps extension — bilateral long-head work; demanding shoulder mobility.",
        instructions="Hold a barbell or EZ-bar overhead. Lower behind the head by bending elbows, extend to lockout.",
        cues=["elbows in", "full stretch at bottom", "lock out triceps"],
    )),
    "Triceps Extension (Cable)": ("tricep_extension", dict(
        equipment=["cable-machine"],
        description="Cable overhead triceps extension — long-head emphasis with constant tension via cable.",
        instructions="Face away from cable stack, rope or bar attachment held overhead. Lower behind head by bending elbows, extend to lockout.",
        cues=["elbows next to ears", "no shoulder shrug", "full ROM"],
    )),
    "Triceps Extension (Dumbbell)": ("tricep_extension", dict(
        equipment=["dumbbells"],
        description="Overhead two-hand DB triceps extension — bilateral long-head work cradling one DB overhead.",
        instructions="Hold one DB with both hands at one end, overhead. Lower behind the head by bending elbows, extend up.",
        cues=["elbows in", "stretch behind head", "lock out"],
    )),
    "Triceps Extension (Machine)": ("tricep_extension", dict(
        equipment=["tricep-extension-machine"],
        description="Machine triceps extension — seated, fixed-plane extension; clean isolation.",
        instructions="Set seat, grip handles. Extend at the elbow only, lower under control.",
        cues=["upper arms static", "lock out triceps", "slow eccentric"],
    )),
    "Triceps Pushdown (Cable - Straight Bar)": ("tricep_pushdown", dict(
        equipment=["cable-machine"],
        description="Straight-bar cable triceps pushdown — high-volume triceps isolation; a staple finisher.",
        instructions="Set cable to high. Grip a straight bar overhand. Press the bar down by extending elbows, control the return.",
        cues=["elbows pinned to sides", "lockout fully", "slow eccentric"],
    )),

    # === Hip ad/abductor ===
    "Hip Adductor (Machine)": ("squat", dict(
        equipment=["hip-ad-ab-machine"],
        muscles_primary=["adductors"],
        muscles_secondary=["glutes"],
        movement_patterns=["hip-adduction"],
        difficulty="beginner",
        default_sets=3, default_reps="12-15", default_rest="60s",
        description="Hip adductor machine — isolates the inner thigh; useful for groin health and balanced hip strength.",
        instructions="Sit in the machine, pads on inside of knees. Squeeze legs together, control the opening.",
        cues=["pause at fully closed", "slow opening", "no torso swing"],
    )),

    # === Misc trap/back ===
    "Shrug (Machine)": ("shrug_machine", dict(
        equipment=["shrug-machine"],
        description="Machine shrug — fixed-plane trap work, easy to load.",
        instructions="Grip handles, traps relaxed at start. Shrug straight up, pause, control the descent.",
        cues=["straight up, not rolling", "pause at top", "full stretch at bottom"],
    )),
    "Shrug (Smith Machine)": ("shrug_machine", dict(
        equipment=["smith-machine"],
        description="Smith machine shrug — barbell-style shrug with fixed bar path; lets you load heavy without grip failure.",
        instructions="Stand under the bar at thigh height. Grip overhand, shrug straight up to ear level, control descent.",
        cues=["straight up motion", "no neck shrug", "full stretch"],
    )),

    # === Trap-bar / odd objects ===
    "Kneeling Pulldown (Band)": ("lat_pulldown", dict(
        equipment=["band-medium", "pull-up-bar"],
        environment="anywhere",
        difficulty="beginner",
        description="Kneeling band pulldown — vertical pull pattern from a band anchored overhead; portable lat work.",
        instructions="Anchor a band overhead. Kneel, grip with both hands. Pull elbows down and back, return slowly.",
        cues=["drive elbows down", "no shrug", "full lat stretch at top"],
    )),

    # === Lateral box jump (FORCE_ALIAS already mapped); below is rest of borderline NEW ===

    # === Cardio ===
    "Aerobics Wait": ("conditioning", dict(equipment=["bodyweight"])),  # dropped, never used

    # === Misc ===
    "Muscle Up": ("pull_up_variant", dict(
        equipment=["pull-up-bar", "gymnastic-rings"],
        muscles_primary=["lats", "pec-major-sternal", "triceps"],
        muscles_secondary=["biceps", "delt-anterior", "core"],
        difficulty="elite",
        default_sets=3, default_reps="3-5", default_rest="2-3 min",
        is_compound=1,
        description="Muscle-up — explosive pull-up + transition to a dip; iconic bodyweight skill combining pulling and pressing strength.",
        instructions="Hang from the bar or rings. Pull explosively, transition the chest over the bar, then press out to lockout. Reverse with control.",
        cues=["pull aggressive then transition", "chest over the bar", "lock out at the top"],
    )),
    "Pull Up (Assisted)": ("pull_up_variant", dict(
        equipment=["lat-pulldown", "band-heavy"],
        difficulty="beginner",
        default_sets=3, default_reps="6-10", default_rest="90s",
        description="Assisted pull-up — band-assisted or machine-assisted vertical pull; bridges from inverted rows to bodyweight pull-ups.",
        instructions="On a machine, set the assist weight. With a band, loop it across the bar and step or knee into it. Perform a strict pull-up.",
        cues=["full hang at bottom", "chin over bar", "control descent"],
    )),
    "Pull Up (Band)": ("pull_up_variant", dict(
        equipment=["pull-up-bar", "band-heavy"],
        difficulty="beginner",
        default_sets=3, default_reps="6-10", default_rest="90s",
        description="Band-assisted pull-up — loop a band over the bar and step into it. Progressive overload by switching to lighter bands.",
        instructions="Anchor a band over the bar. Step into the loop, perform a strict pull-up. Control the descent.",
        cues=["full ROM", "chin over bar", "shoulders engaged at hang"],
    )),
    "Pullover (Machine)": ("chest_fly", dict(
        equipment=["chest-press-machine"],  # generic pullover machine
        muscles_primary=["lats", "pec-major-sternal"],
        muscles_secondary=["triceps"],
        movement_patterns=["vertical-pull"],
        description="Machine pullover — fixed-plane pullover; targets lats with consistent loading.",
        instructions="Set seat. Grip handles overhead. Pull elbows down toward the hips in an arc, control the return.",
        cues=["arc the elbows down", "feel lat stretch at top", "no spinal extension"],
    )),
    "Push Up": ("dip", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["pec-major-sternal", "triceps", "delt-anterior"],
        muscles_secondary=["core"],
        movement_patterns=["horizontal-push"],
        difficulty="beginner",
        default_sets=3, default_reps="10-20", default_rest="60-90s",
        description="Push-up — foundational horizontal pressing pattern; scales from beginner to advanced.",
        instructions="Plank position, hands shoulder-width. Lower chest to within a fist's distance of the floor. Press to lockout.",
        cues=["straight body line", "elbows 45°", "full ROM"],
    )),
    "Push Up (Band)": ("dip", dict(
        equipment=["band-medium", "bodyweight"],
        environment="anywhere",
        muscles_primary=["pec-major-sternal", "triceps", "delt-anterior"],
        movement_patterns=["horizontal-push"],
        difficulty="intermediate",
        default_sets=3, default_reps="8-15", default_rest="60-90s",
        description="Band-resisted push-up — band across the upper back adds resistance at lockout. Great progressive overload for push-ups.",
        instructions="Loop band across upper back, hold ends under hands. Perform a strict push-up.",
        cues=["band stays taut", "press to lockout", "elbows 45°"],
    )),
    "Sit Up": ("core_crunch", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["rectus-abdominis", "hip-flexors"],
        difficulty="beginner",
        default_sets=3, default_reps="15-25", default_rest="60s",
        description="Standard sit-up — full trunk flexion with feet anchored. Classic core exercise.",
        instructions="Lie supine, knees bent, feet anchored. Sit up to a vertical torso, lower under control.",
        cues=["exhale on the sit-up", "no neck pull", "control descent"],
    )),
    "Skullcrusher (Barbell)": ("skullcrusher", dict(
        equipment=["barbell", "flat-bench"],
        description="Lying barbell triceps extension (skullcrusher) — heavy elbow extension work; long-head emphasis.",
        instructions="Lie on a bench, hold the bar at arm's length over the chest. Bend elbows to lower the bar toward forehead, extend to lockout.",
        cues=["elbows track over shoulders", "lower toward forehead", "lock out triceps"],
    )),
    "Skullcrusher (Dumbbell)": ("skullcrusher", dict(
        equipment=["dumbbells", "flat-bench"],
        description="Lying DB triceps extension — independent arm work; spares wrists.",
        instructions="Lie on a bench, DBs at arm's length over the chest. Bend elbows to lower DBs toward forehead, extend to lockout.",
        cues=["elbows over shoulders", "control descent", "lockout"],
    )),

    # === Seated Leg Press machine ===
    "Seated Leg Press (Machine)": ("squat", dict(
        equipment=["leg-press"],
        difficulty="beginner",
        default_sets=3, default_reps="8-12", default_rest="90s",
        movement_patterns=["squat"],
        muscles_primary=["quadriceps", "glutes"],
        muscles_secondary=["hamstrings", "adductors"],
        description="Seated leg press — heavy lower-body loading with no spinal load; staple machine work.",
        instructions="Set the seat. Feet shoulder-width on the platform. Lower to a deep angle (knees over toes), press back to extension without locking knees.",
        cues=["full depth", "knees track toes", "don't lock knees at top"],
    )),

    # === Seated palms-up wrist curl is in ALIAS bucket per matcher? Recheck ===
    "Seated Palms Up Wrist Curl (Dumbbell)Wait": ("front_raise", dict(equipment=["dumbbells"])),  # placeholder if needed

    # === Seated Wide-Grip Row ===
    "Seated Wide-Grip Row (Cable)": ("row_machine", dict(
        equipment=["cable-machine"],
        muscles_primary=["mid-traps", "rhomboids", "delt-posterior"],
        muscles_secondary=["lats", "biceps"],
        description="Seated wide-grip cable row — wide grip + slight backward lean biases upper back and rear delts over lats.",
        instructions="Sit at a cable row station with a wide bar attachment. Pull to the upper abs, elbows flared, squeeze upper back.",
        cues=["wide elbow flare", "pull to upper abs", "squeeze rear delts"],
    )),

    # === Torso rotation ===
    "Torso Rotation (Machine)": ("core_rotation", dict(
        equipment=["torso-rotation-machine"],
        description="Torso rotation machine — selectorized rotational core work; consistent loading on the obliques.",
        instructions="Sit in the machine. Brace, rotate against the pad, return under control.",
        cues=["rotate from torso, not arms", "control return", "no jerking"],
    )),
    "Trap Bar Deadlift Wait": ("deadlift", dict(equipment=["trap"])),  # placeholder

    # === Upright row variants ===
    "Upright Row (Cable)": ("ohp", dict(
        equipment=["cable-machine"],
        muscles_primary=["delt-lateral", "upper-traps"],
        muscles_secondary=["biceps"],
        movement_patterns=["scapular-protraction"],
        difficulty="beginner",
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="Cable upright row — lateral delt + trap work pulled vertically with cable resistance.",
        instructions="Set cable to low. Stand facing the stack, grip a straight bar or rope. Pull up to chin level, elbows leading.",
        cues=["elbows above wrists", "to chin level only", "no shrug at top"],
    )),
    "Upright Row (Dumbbell)": ("ohp", dict(
        equipment=["dumbbells"],
        muscles_primary=["delt-lateral", "upper-traps"],
        muscles_secondary=["biceps"],
        movement_patterns=["scapular-protraction"],
        difficulty="beginner",
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="DB upright row — vertical pull with DBs; lateral delt + trap work.",
        instructions="Hold DBs in front of thighs. Pull up to chin level by leading with elbows. Lower under control.",
        cues=["elbows lead", "no shoulder pinch", "DBs stay close to body"],
    )),

    # === Thrusters ===
    "Thruster (Barbell)": ("ohp", dict(
        equipment=["barbell"],
        muscles_primary=["quadriceps", "glutes", "delt-anterior"],
        muscles_secondary=["upper-traps", "triceps", "core"],
        movement_patterns=["squat", "vertical-push"],
        difficulty="intermediate",
        default_sets=3, default_reps="8-12", default_rest="90-120s",
        is_compound=1,
        description="Barbell thruster — front squat into overhead press in one motion. CrossFit and conditioning staple.",
        instructions="Bar in front rack. Squat to depth, drive up explosively, use the momentum to press the bar overhead.",
        cues=["full squat depth", "use leg drive", "lock out overhead"],
    )),
    "Thruster (Kettlebell)": ("ohp", dict(
        equipment=["kettlebell"],
        muscles_primary=["quadriceps", "glutes", "delt-anterior"],
        muscles_secondary=["upper-traps", "triceps", "core"],
        movement_patterns=["squat", "vertical-push"],
        difficulty="intermediate",
        default_sets=3, default_reps="10-15", default_rest="90s",
        is_compound=1,
        description="Kettlebell thruster — front-rack KB squat to overhead press; conditioning + power.",
        instructions="Two KBs in front rack. Squat to depth, drive up, press the KBs overhead in one motion.",
        cues=["KBs stay racked through squat", "leg drive then press", "full lockout"],
    )),

    # === Toes To Bar ===
    "Toes To Bar": ("core_hanging", dict(
        equipment=["pull-up-bar"],
        difficulty="advanced",
        default_sets=3, default_reps="5-10", default_rest="90-120s",
        description="Toes-to-bar — hanging dynamic core movement bringing toes to the bar. CrossFit gymnastic skill.",
        instructions="Hang from the bar. Use hollow → arch swing, pull and snap the toes up to touch the bar. Control descent.",
        cues=["hollow then arch", "hip snap", "toes touch bar"],
    )),

    # === Wrist Roller (already CONFIRMED?) ===

    # === Seated Palms Up Wrist Curl ===
    "Seated Palms Up Wrist Curl (Dumbbell)": ("bicep_curl", dict(
        equipment=["dumbbells", "flat-bench"],
        muscles_primary=["forearm-flexors", "grip-crush"],
        muscles_secondary=[],
        movement_patterns=["elbow-flexion"],
        difficulty="beginner",
        default_sets=3, default_reps="12-15", default_rest="45-60s",
        description="Seated palms-up wrist curl — forearm flexor isolation; wrists hang off the knees or a bench edge.",
        instructions="Sit, brace forearms on thighs with wrists hanging off knees, palms up. Curl wrists up, lower under control.",
        cues=["forearms fixed", "wrist-only motion", "full ROM"],
    )),

    # === Spider Curl ===
    "Spider Curl": ("bicep_curl", dict(
        equipment=["dumbbells", "preacher-bench"],
        description="Spider curl — preacher curl variant with arms hanging straight down off an incline bench; peak biceps contraction.",
        instructions="Lie chest-down on an incline bench, arms hanging. Curl DBs up keeping upper arms vertical, squeeze hard, lower under control.",
        cues=["upper arms vertical", "squeeze at top", "no swing"],
    )),

    # === Final 12 missing drafts ===
    "Chest Fly (Dumbbell)": ("chest_fly", dict(
        equipment=["dumbbells", "flat-bench"],
        description="Dumbbell chest fly — supine pec isolation with arc-of-motion adduction; deep stretch + squeeze.",
        instructions="Lie on a flat bench, DBs above chest with slight elbow bend. Lower out wide in an arc until DBs are at chest level, return to top.",
        cues=["slight elbow bend stays fixed", "wide arc", "feel stretch, then squeeze"],
    )),
    "Glute Bridge": ("rdl", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["glute-max"],
        muscles_secondary=["hamstrings", "core"],
        movement_patterns=["hip-flexion"],
        difficulty="beginner",
        is_unilateral=0,
        is_compound=0,
        default_sets=3, default_reps="12-20", default_rest="45-60s",
        description="Glute bridge — supine hip extension; foundational glute activation pattern.",
        instructions="Lie supine, knees bent, feet flat. Drive heels into the floor to lift hips up. Squeeze glutes at the top, lower under control.",
        cues=["squeeze glutes at top", "drive through heels", "ribs down"],
    )),
    "Jump Squat": ("squat", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["quadriceps", "glutes", "calves"],
        muscles_secondary=["hamstrings", "core"],
        movement_patterns=["squat", "jumping-landing"],
        difficulty="intermediate",
        modality="power",
        default_sets=4, default_reps="5-8", default_rest="60-90s",
        is_compound=1,
        description="Bodyweight jump squat — plyometric squat for lower-body power; descend into a squat, explode vertically.",
        instructions="Stand feet shoulder-width. Squat to a quarter or half depth, then jump explosively. Land softly, immediately reset for the next rep.",
        cues=["explode through the floor", "land softly", "reset before next rep"],
    )),
    "Kettlebell Clean": ("olympic", dict(
        equipment=["kettlebell"],
        muscles_primary=["glutes", "hamstrings", "upper-traps"],
        muscles_secondary=["quadriceps", "delt-anterior", "forearm-flexors"],
        difficulty="intermediate",
        is_unilateral=1,
        default_sets=4, default_reps="5-8", default_rest="60-90s",
        description="Kettlebell single-arm clean — KB swing variation that finishes in a front-rack position; foundational KB skill.",
        instructions="Start with KB between feet. Hike-pass back, then drive the hips through. As KB rises, guide the elbow back and let the KB land softly in the rack position. Reverse to the floor.",
        cues=["zip up close to body", "soft landing in rack", "no banging the wrist"],
    )),
    "Plank": ("core_crunch", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["rectus-abdominis", "transverse-abdominis"],
        muscles_secondary=["external-obliques", "glutes", "delt-anterior"],
        movement_patterns=["anti-extension"],
        difficulty="beginner",
        default_sets=3, default_reps="30-60s", default_rest="45-60s",
        is_compound=0,
        description="Forearm plank — anti-extension isometric; foundational core stability hold.",
        instructions="Get on forearms and toes, body in a straight line head to heel. Brace abs, squeeze glutes. Hold without letting hips sag or hike.",
        cues=["straight line head-to-heel", "ribs down", "squeeze glutes hard"],
    )),
    "Plyo Push-Up": ("dip", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["pec-major-sternal", "triceps", "delt-anterior"],
        muscles_secondary=["core"],
        movement_patterns=["horizontal-push", "jumping-landing"],
        difficulty="advanced",
        modality="power",
        default_sets=4, default_reps="5-8", default_rest="90-120s",
        is_compound=1,
        description="Plyometric push-up — explosive push-up with hands leaving the floor; upper-body power development.",
        instructions="From push-up position, lower under control, then drive up explosively so hands leave the floor. Land softly into the next rep.",
        cues=["explode off the floor", "land in a soft elbow bend", "no rest between reps"],
    )),
    "Single Leg Bridge": ("rdl", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["glute-max"],
        muscles_secondary=["hamstrings", "core"],
        movement_patterns=["hip-flexion"],
        difficulty="intermediate",
        is_unilateral=1,
        is_compound=0,
        default_sets=3, default_reps="8-12", default_rest="60s",
        description="Single-leg glute bridge — unilateral hip extension; addresses left/right glute imbalances.",
        instructions="Lie supine, one knee bent with foot flat, other leg extended. Drive the planted heel into the floor to lift hips up. Squeeze at top, lower with control.",
        cues=["hips level at top", "drive through planted heel", "no lower-back arch"],
    )),
    "Ski Erg": ("cardio_machine", dict(
        equipment=["ski-erg"],
        muscles_primary=["lats", "core", "delt-posterior"],
        muscles_secondary=["triceps", "hamstrings"],
        movement_patterns=["vertical-pull"],
        default_duration="10-20 min",
        default_reps="500m or 1km intervals",
        description="Ski erg — vertical-pull cardio machine simulating XC skiing double-pole; full upper body + core conditioning.",
        instructions="Stand at the erg, grip handles overhead. Pull down and back via hip hinge + lat drive. Return handles overhead under control.",
        cues=["pull from lats, not arms", "hinge from hips", "smooth tempo"],
    )),
    "Straight-Arm Pulldown": ("lat_pulldown", dict(
        equipment=["cable-machine"],
        muscles_primary=["lats"],
        muscles_secondary=["triceps", "core"],
        is_compound=0,
        difficulty="beginner",
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="Straight-arm cable pulldown — isolates the lats by pulling with the shoulder joint, not the elbow. Great accessory.",
        instructions="Set cable high. Grip a straight bar with arms extended. Pull the bar down in an arc to the thighs by extending the shoulders. Control the return.",
        cues=["arms stay straight", "drive elbows down by your sides", "feel lat stretch at top"],
    )),
    "Stretching": ("conditioning", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["full-body"],
        modality="flexibility",
        movement_patterns=["breathing-bracing"],
        difficulty="beginner",
        default_sets=1, default_reps="30-60s per stretch", default_rest="0",
        default_duration="10-15 min",
        is_compound=0,
        description="Static stretching routine — sustained holds for major muscle groups. Used as a cooldown or for general mobility work.",
        instructions="Cycle through stretches for hamstrings, hip flexors, chest, lats, calves, etc. Hold each for 30-60s while breathing deeply.",
        cues=["breathe into the stretch", "no bouncing", "stop before pain"],
    )),
    "V Up": ("core_crunch", dict(
        equipment=["bodyweight"],
        environment="anywhere",
        muscles_primary=["rectus-abdominis", "hip-flexors"],
        muscles_secondary=["external-obliques"],
        movement_patterns=["anti-extension"],
        difficulty="intermediate",
        is_compound=0,
        default_sets=3, default_reps="10-15", default_rest="60s",
        description="V-Up — simultaneous reach of arms and legs to meet in a V over the body; demanding rectus + hip-flexor work.",
        instructions="Lie supine, arms overhead. Simultaneously raise legs and torso to meet at the top forming a V, reach hands to feet. Lower with control.",
        cues=["meet in the middle", "control descent", "no momentum"],
    )),
    "Walking": ("cardio_machine", dict(
        equipment=["bodyweight"],
        environment="outdoor",
        muscles_primary=["calves", "quadriceps", "glutes"],
        muscles_secondary=["hamstrings"],
        movement_patterns=["locomotion"],
        default_duration="20-60 min",
        default_reps=None,
        description="Walking — foundational locomotion; the most basic and underrated cardio. Best done outdoors, low-impact.",
        instructions="Walk at a steady, conversational pace. Maintain upright posture, midfoot strike, relaxed arm swing.",
        cues=["upright posture", "natural arm swing", "comfortable pace"],
    )),
}


def load_classification() -> list[tuple[str, str, str]]:
    """Return [(source_name, disposition, target_in_db)] for NEW rows only."""
    rows = []
    with CLASSIFICATION_CSV.open() as f:
        for row in csv.DictReader(f):
            if row["disposition"] == "NEW":
                rows.append((row["source_name"], row["disposition"], row["target_in_db"]))
    return rows


def slugify(name: str) -> str:
    s = name.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s


def derive_tags(name: str, family_key: str, category: str, equipment_slugs: list[str]) -> list[str]:
    """Tags drive search + chip filters. Mix the exercise's own words with
    family/category/equipment markers so users find rows by lift name, body
    part, or piece of gear."""
    tags: set[str] = set()
    # Words from the exercise name (drop parenthesized qualifiers + short tokens).
    clean = re.sub(r"\([^)]*\)", "", name).lower()
    for word in re.split(r"[\s\-]+", clean):
        if len(word) >= 3 and word not in {"the", "and", "with", "for"}:
            tags.add(word)
    # Category as a tag
    if category:
        tags.add(category.lower())
    # Equipment as readable tags
    for eq in equipment_slugs:
        tags.add(eq.replace("-", " "))
    # Family-specific programming tags so the planner can find swap groups.
    family_tags = {
        "olympic":      ["olympic lifting", "explosive", "triple extension"],
        "deadlift":     ["posterior chain", "hinge"],
        "rdl":          ["posterior chain", "hinge"],
        "squat":        ["quad", "lower body"],
        "single_leg_squat": ["unilateral", "balance"],
        "lunge":        ["unilateral", "lower body"],
        "pull_up_variant": ["bodyweight pull", "gymnastic"],
        "dip":          ["bodyweight push", "gymnastic"],
        "core_crunch":  ["anti-extension"],
        "core_oblique": ["anti-lateral-flexion"],
        "core_rotation": ["rotation"],
        "core_hanging": ["hanging", "anti-extension"],
        "cardio_machine": ["cardio", "aerobic"],
        "conditioning": ["conditioning", "metcon"],
    }
    tags.update(family_tags.get(family_key, []))
    return sorted(tags)


def build_row(source_name: str, next_id: int) -> dict:
    """Look up the draft for source_name, return a CSV row dict."""
    draft_key = source_name
    if draft_key not in DRAFTS:
        return {"id": "", "name": source_name, "slug": slugify(source_name),
                "category": "Other",
                "_status": "NO_DRAFT — needs manual entry"}

    family_key, overrides = DRAFTS[draft_key]
    family = FAMILIES[family_key]

    row = dict.fromkeys(COLUMNS, "")
    row["name"] = source_name
    row["slug"] = slugify(source_name)

    # Inherit family defaults
    for k, v in family.items():
        if k in ("muscles_primary", "muscles_secondary", "movement_patterns", "equipment"):
            row[k] = ";".join(v) if isinstance(v, list) else (v or "")
        elif v is not None:
            row[k] = v

    # Apply overrides
    for k, v in overrides.items():
        if k in ("muscles_primary", "muscles_secondary", "movement_patterns", "equipment"):
            row[k] = ";".join(v) if isinstance(v, list) else (v or "")
        elif k == "cues" and isinstance(v, list):
            row[k] = json.dumps(v, ensure_ascii=False)
        else:
            row[k] = v

    # --- Defaults applied only when the field is still empty ---
    def fill(field: str, value):
        if row.get(field) in ("", None):
            row[field] = value

    # Difficulty-driven numeric + flag defaults
    difficulty = row.get("difficulty") or "intermediate"
    for k, v in DEFAULTS_BY_DIFFICULTY[difficulty].items():
        fill(k, v)

    # Modality-specific bumps (power → higher CNS, endurance → lower demand)
    modality = row.get("modality") or "strength"
    for k, v in DEFAULTS_BY_MODALITY.get(modality, {}).items():
        # modality overrides difficulty for these specific fields
        row[k] = v

    # Family-derived metadata
    fatigue_tags = FATIGUE_BY_FAMILY.get(family_key, [])
    if fatigue_tags:
        fill("fatigue_type", json.dumps(fatigue_tags, ensure_ascii=False))

    regression, progression = PROG_BY_FAMILY.get(family_key, ("", ""))
    fill("regression", regression)
    fill("progression", progression)

    time_eff, home_var = ALT_BY_FAMILY.get(family_key, ("", ""))
    fill("time_efficient_variation", time_eff)
    fill("home_variation", home_var)

    comps = COMPENSATIONS_BY_FAMILY.get(family_key, [])
    if comps:
        fill("common_compensations", json.dumps(comps, ensure_ascii=False))

    # Tags — derive from name + category + equipment
    eq_slugs = (row.get("equipment") or "").split(";") if row.get("equipment") else []
    eq_slugs = [s for s in eq_slugs if s]
    tags = derive_tags(source_name, family_key, row.get("category", ""), eq_slugs)
    fill("tags", json.dumps(tags, ensure_ascii=False))

    # Audit timestamps
    fill("created_at", TODAY)
    fill("updated_at", TODAY)

    # Type defaults
    fill("cues", "[]")
    fill("contraction_type", "concentric")
    fill("energy_system", "phosphagen")
    fill("movement_plane", "sagittal")

    return row


def main():
    new_rows = load_classification()
    print(f"Loaded {len(new_rows)} NEW rows from classification CSV.")

    out_path = REPO_ROOT / "proposed_new_exercises.csv"
    missing_drafts = []

    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
        writer.writeheader()
        for i, (src, _disp, _target) in enumerate(new_rows, start=1):
            row = build_row(src, i)
            if row.get("_status", "").startswith("NO_DRAFT"):
                missing_drafts.append(src)
            writer.writerow(row)

    print(f"\nWrote {out_path}")
    if missing_drafts:
        print(f"\n⚠ {len(missing_drafts)} entries have no draft and need manual definitions:")
        for s in missing_drafts:
            print(f"  - {s}")


if __name__ == "__main__":
    main()
