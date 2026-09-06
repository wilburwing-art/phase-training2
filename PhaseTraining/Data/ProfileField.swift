// ProfileField.swift — the profile fields that shape the plan and can run on a
// default, plus the stated/assumed bookkeeping over them.
//
// Onboarding used to ask every one of these as a mandatory step, so every value
// in TrainingMemory was one the user had actually chosen. Once the gate was cut
// to sport + season, the rest ship on defaults — which means the app can no
// longer tell "the user wants 3 lift days" from "nobody has said, so 3."
//
// `TrainingMemory.statedFields` is that distinction. A field is STATED once the
// user touches its editor; until then it is ASSUMED, and the Week tab surfaces
// it as a tappable chip that opens the editor it belongs to.
//
// Scope is deliberately narrow: only fields where the DEFAULT materially shapes
// the generated week. Age, gender, dislikes and injuries are omitted — an empty
// injury list is a legitimate answer, not an assumption, and chipping "no
// injuries · assumed" would be noise. They keep their Profile rows and are
// reachable there whenever the user wants them.
//
// NOTE: `statedFields` must never enter `planInputsHash`. It does not affect
// generation, and that hash is BOTH the auto-regen trigger and the
// `deterministicPick` seed — presentation state in it would reshuffle the whole
// week for nothing. (That is the mistake the era axis's `"er:"` component was
// making before it was deleted.)

import Foundation

/// A plan-shaping profile field that can run on a default.
enum ProfileField: String, CaseIterable, Identifiable, Hashable {
    /// `sessionMinutes` + `liftDaysPerWeek`.
    case availability
    /// `equipment`.
    case equipment
    /// `experience` + `startingState`.
    case experience

    var id: String { rawValue }

    /// Chip / checklist label. Reads as the thing itself, not as a task.
    var label: String {
        switch self {
        case .availability: return "Schedule"
        case .equipment:    return "Equipment"
        case .experience:   return "Experience"
        }
    }

    var icon: String {
        switch self {
        case .availability: return "clock"
        case .equipment:    return "wrench.and.screwdriver"
        case .experience:   return "chart.line.uptrend.xyaxis"
        }
    }

    /// One line on what the plan does differently once this is real.
    var whyItMatters: String {
        switch self {
        case .availability:
            return "How long each session runs and how many lift days the week gets."
        case .equipment:
            return "Which exercises can be picked at all."
        case .experience:
            return "Movement complexity and how hard the first weeks ramp."
        }
    }
}

extension TrainingMemory {

    /// Has the user explicitly set this field, as opposed to running on its default?
    func isStated(_ field: ProfileField) -> Bool {
        statedFields.contains(field.rawValue)
    }

    /// Record that the user has explicitly set this field. Idempotent.
    mutating func markStated(_ field: ProfileField) {
        statedFields.insert(field.rawValue)
    }

    /// Fields still running on their default, in display order.
    var assumedFields: [ProfileField] {
        ProfileField.allCases.filter { !isStated($0) }
    }

    /// Summary of the current value of `field`, for the chip and the checklist.
    /// Phrased as the value alone — the chip renders the "assumed" qualifier.
    func assumptionSummary(for field: ProfileField) -> String {
        switch field {
        case .availability:
            let days = liftDaysPerWeek == 1 ? "1 lift day" : "\(liftDaysPerWeek) lift days"
            return "\(days) · \(sessionMinutes) min"
        case .equipment:
            if equipment.contains(.fullGym) { return "Full gym" }
            if equipment.count == 1 { return equipment[0].label }
            return "\(equipment.count) items"
        case .experience:
            return experience.label
        }
    }
}
