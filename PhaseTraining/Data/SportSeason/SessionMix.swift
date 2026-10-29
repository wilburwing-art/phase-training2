// SessionMix.swift — which lift days of a week are sport sessions and which
// are complement sessions.
//
// A sport session trains what the sport demands (ski: legs). Past a few of
// those a week, more of the same stops helping, so the remaining gym days
// train the muscle groups the sport work leaves out. Before this, every lift
// day was a sport session and `Planner.applyPhaseSessionCap` turned the days
// past the phase's cap into rest: a pre-season skier at 5 gym days got 3 leg
// sessions and 2 empty days.
//
// Everything here is a pure function of (liftIndex, totalLifts, phase,
// sport), so a day keeps its role across regenerations and a moved workout,
// which keeps its lift index, keeps its role too.

import Foundation

enum SessionMix {

    /// What a lift day is for.
    enum Role: Equatable {
        /// The `index`-th of `of` sport sessions this week.
        case sport(index: Int, of: Int)
        case complement(ComplementSlot)
    }

    /// Which muscle groups a sport's own sessions load, which decides what
    /// its complement days train.
    enum Family: Equatable {
        case legsDominant
        case upperDominant
    }

    static func family(forSport slug: String?) -> Family {
        guard let slug else { return .legsDominant }
        return PhaseRule.climbingSlugs.contains(slug) ? .upperDominant : .legsDominant
    }

    /// Sport sessions per week (Wilbur, 2026-10-28). The rest of the lift
    /// days are complement sessions.
    ///
    /// | lift days | off | pre / event | in / maintenance |
    /// |   1       |  1  |  1          |  1               |
    /// |   2       |  2  |  2          |  1               |
    /// |   3-4     |  2  |  2          |  1               |
    /// |   5       |  3  |  2          |  2               |
    /// |   6+      |  3  |  3          |  2               |
    static func sportDose(phase: SeasonPhase, liftDays: Int) -> Int {
        guard liftDays > 0 else { return 0 }
        let dose: Int
        switch phase {
        case .offSeason:
            dose = liftDays >= 5 ? 3 : 2
        case .preSeason, .eventPrep:
            dose = liftDays >= 6 ? 3 : 2
        case .inSeason, .maintenance:
            dose = liftDays >= 5 ? 2 : 1
        }
        return min(dose, liftDays)
    }

    /// Lift indices that hold the sport sessions, spread across the week:
    /// floor((i + 0.5) * total / dose). Lift indices follow date order, so 2
    /// of 5 land on the 2nd and 4th lift days rather than back to back.
    static func sportPositions(totalLifts: Int, dose: Int) -> [Int] {
        guard dose > 0, totalLifts > 0 else { return [] }
        return (0..<dose).map { Int((Double($0) + 0.5) * Double(totalLifts) / Double(dose)) }
    }

    static func role(liftIndex: Int, totalLifts: Int, phase: SeasonPhase, family: Family) -> Role {
        let total = max(1, totalLifts)
        let index = ((liftIndex % total) + total) % total
        let dose = sportDose(phase: phase, liftDays: total)
        let positions = sportPositions(totalLifts: total, dose: dose)
        if let k = positions.firstIndex(of: index) {
            return .sport(index: k, of: dose)
        }
        let ordinal = index - positions.filter { $0 < index }.count
        let rotation = complementRotation(family: family, count: total - dose)
        let focus = rotation[ordinal % rotation.count]
        let repeatNumber = rotation.prefix(ordinal).filter { $0 == focus }.count + 1
        return .complement(ComplementSlot(focus: focus, repeatNumber: repeatNumber))
    }

    /// Complement focuses for `count` complement days, in lift-index order.
    static func complementRotation(family: Family, count: Int) -> [ComplementFocus] {
        let base: [ComplementFocus]
        switch (family, count) {
        case (.legsDominant, 1):  base = [.upperBody]
        case (.legsDominant, 2):  base = [.pushCore, .pullArms]
        case (.legsDominant, _):  base = [.upperPush, .upperPull, .coreArms]
        case (.upperDominant, 1): base = [.legsPush]
        case (.upperDominant, 2): base = [.legsCore, .pushCore]
        case (.upperDominant, _): base = [.legs, .upperPush, .legsCore]
        }
        guard count > 0 else { return base }
        return (0..<count).map { base[$0 % base.count] }
    }
}

/// One complement day: its focus, and which repeat of that focus it is this
/// week, so a second "Upper push" reads "Upper push 2".
struct ComplementSlot: Equatable {
    let focus: ComplementFocus
    let repeatNumber: Int

    var title: String {
        repeatNumber > 1 ? "\(focus.title) \(repeatNumber)" : focus.title
    }
}

/// What a complement session trains. Demand weights draw from the
/// general-fitness pool in coach.db.
enum ComplementFocus: String, CaseIterable, Equatable {
    case upperBody, pushCore, pullArms, upperPush, upperPull, coreArms
    case legs, legsPush, legsCore

    /// Session title. It names the focus on purpose: `PlanValidator.resolveFocus`
    /// reads push / pull / leg / upper from the title.
    var title: String {
        switch self {
        case .upperBody: return "Upper body"
        case .pushCore:  return "Push + core"
        case .pullArms:  return "Pull + arms"
        case .upperPush: return "Upper push"
        case .upperPull: return "Upper pull"
        case .coreArms:  return "Core + arms"
        case .legs:      return "Legs"
        case .legsPush:  return "Legs + push"
        case .legsCore:  return "Legs + core"
        }
    }

    var demandWeights: [Demand: Double] {
        switch self {
        case .upperBody: return [.upperPush: 0.4, .upperPull: 0.4, .core: 0.2]
        case .pushCore:  return [.upperPush: 0.6, .arms: 0.1, .core: 0.3]
        case .pullArms:  return [.upperPull: 0.65, .arms: 0.35]
        case .upperPush: return [.upperPush: 0.8, .arms: 0.2]
        case .upperPull: return [.upperPull: 0.8, .arms: 0.2]
        case .coreArms:  return [.core: 0.55, .arms: 0.45]
        case .legs:      return [.legStrength: 0.8, .core: 0.2]
        case .legsPush:  return [.legStrength: 0.5, .upperPush: 0.35, .core: 0.15]
        case .legsCore:  return [.legStrength: 0.6, .core: 0.4]
        }
    }

    var workoutFocus: WorkoutFocus {
        switch self {
        case .upperBody, .coreArms: return .upper
        case .pushCore, .upperPush: return .push
        case .pullArms, .upperPull: return .pull
        case .legs, .legsCore:      return .legs
        case .legsPush:             return .fullBodyA
        }
    }
}
