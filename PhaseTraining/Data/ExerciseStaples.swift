// ExerciseStaples.swift — preference whitelist for the deterministic
// planner.
//
// Why this exists: WorkoutGenerator.pickForSlot used to draw from the full
// candidate pool for a movement pattern, picking essentially at random.
// On a 20-exercise pool for "horizontal-push", bench press had the same
// odds as "Single-arm landmine press." This skewed everyday workouts away
// from universally-recognizable lifts toward obscure sport-flavored
// variants (coach.db is heavy on climbing / sailing / ski prep drills).
//
// Build 95 introduces a staple preference layer: when the candidate pool
// contains any staple for the slot's pattern, the picker narrows to those
// staples only. Variety still works — the existing `recentlyPicked` filter
// drops staples out once they've been used, opening the wider pool for
// week-over-week rotation. So the user sees bench / squat / deadlift /
// pull-ups by default, but variants surface naturally over time.
//
// Keywords are case-insensitive substring matches against
// `exercises.name`. The DB doesn't have plain "Bench Press" or "Pull-Up"
// in the canonical names — those staples are Dumbbell Bench Press,
// Weighted Pull-Up, etc. The keyword list reflects what's actually there.

import Foundation

enum ExerciseStaples {

    /// movement_patterns.slug → array of name keywords. An exercise is a
    /// staple for a pattern if any keyword is contained in its name
    /// (case-insensitive). Patterns absent from this map opt out of the
    /// staple preference entirely (falls through to the wider pool).
    static let keywordsByPattern: [String: [String]] = [
        "horizontal-push": ["bench press", "push-up", "floor press"],
        "vertical-push":   ["overhead press", "shoulder press", "military press", "dips (parallel"],
        "horizontal-pull": ["bent-over row", "barbell row", "single-arm row", "inverted row", "body row", "dumbbell row"],
        "vertical-pull":   ["pull-up", "chin-up", "lat pulldown"],
        "scapular-retraction": ["face pull", "scapular pull", "band pull-apart"],
        "squat":           ["back squat", "front squat", "goblet squat"],
        "hip-hinge":       ["deadlift", "kettlebell swing", "good morning"],
        "single-leg-squat": ["bulgarian split squat", "lunge", "split squat"],
        "step-up":         ["step-up", "step up"],
        "calf-raise":      ["calf raise"],
        "hip-abduction":   ["clamshell", "hip abduction", "side-lying leg raise"],
        "loaded-carry":    ["farmer's carry", "farmer carry", "suitcase carry"],
        "anti-extension":  ["plank", "dead bug", "ab wheel"],
        "anti-rotation":   ["pallof press", "anti-rotation press"],
        "anti-lateral-flexion": ["side plank", "suitcase carry"],
        "trunk-rotation":  ["russian twist", "wood chop", "cable chop"],
        "hip-flexion":     ["hanging knee raise", "leg raise", "v-up"],
        // Just "curl" — coach.db has Preacher Curl, Zottman Curl, etc., not
        // the more specific "bicep curl" name. Keyword is broad enough to
        // catch them while not capturing weird wrist-curl variants
        // (those live under separate forearm patterns anyway).
        "elbow-flexion":   ["curl"],
        "elbow-extension": ["triceps extension", "skull crusher", "tricep pushdown", "close-grip push-up"],
        "climbing-pull":   ["pull-up", "chin-up"],
    ]

    /// True if `name` matches any staple keyword for the given pattern.
    /// Empty / unknown patterns return false (no preference applied).
    static func isStaple(name: String, forPattern slug: String) -> Bool {
        guard let keywords = keywordsByPattern[slug] else { return false }
        let lower = name.lowercased()
        return keywords.contains { lower.contains($0) }
    }
}
