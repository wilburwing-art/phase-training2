// WorkoutGenerator+Accessories.swift
//
// Extracted from WorkoutGenerator.swift (Tier-3 god-object split). The
// high-minute volume tier's extra accessory patterns — no state, no
// orchestration; the generation loop calls into this as a focused seam.

import Foundation

extension WorkoutGenerator {
    /// Extra patterns the high-minute volume tier (T1.4) adds at ≥90-min
    /// sessions — one slot beyond the focus recipe's own optional slots. Chosen
    /// to complement each focus without duplicating what the recipe already
    /// prescribes (the dedup is enforced by `pickedIds`, but distinct patterns
    /// also give variety rather than a second hit of the same movement family).
    static func highMinuteAccessoryPatterns(for focus: WorkoutFocus) -> [String] {
        switch focus {
        case .push:
            return ["elbow-flexion", "anti-rotation"]
        case .pull:
            return ["anti-extension", "anti-rotation"]
        case .legs, .lower:
            return ["hip-abduction", "anti-extension"]
        case .upper, .fullBodyA, .fullBodyB:
            return ["elbow-extension", "elbow-flexion", "loaded-carry"]
        }
    }
}
