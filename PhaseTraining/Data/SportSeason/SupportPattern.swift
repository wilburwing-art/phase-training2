// SupportPattern.swift — the declared in-season load of the athlete's SUPPORT
// sport (PLAN-primary-support.md).
//
// The primary/support model is asymmetric: the primary sport gets the
// periodized plan; the support sport gets NO plan — it enters the system as a
// declared weekly pattern ("climb Tue/Thu, alpine day Sat"), each day tagged
// with a magnitude. This file is the INTENT side of that contract: persist the
// pattern, never the scheduled week derived from it — SupportScheduler
// re-derives placement deterministically on every regen.
//
// SupportInterference is the hand-tuned rules table (PhaseRule-style Swift
// switch, not DB seed) keyed by (primary variant, support variant, magnitude).
// v1 authors the ski/board-primary × climbing-support wedge from felt sense;
// unknown combos fall back to a moderate generic row.

import Foundation

// MARK: - Weekday (extends TrainingMemory.swift's app-wide enum)

extension Weekday: Comparable {
    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Days from `self` FORWARD to `other` (circular week, 0 = same day) —
    /// the declared pattern repeats weekly, so distance wraps.
    func daysUntil(_ other: Weekday) -> Int {
        (other.rawValue - rawValue + 7) % 7
    }
}

// MARK: - SupportMagnitude

/// How big a declared support-sport day is. The athlete's own read — a gym
/// bouldering session vs an all-day alpine route — not something we infer.
enum SupportMagnitude: String, Codable, CaseIterable, Hashable, Comparable {
    case light, medium, big

    var label: String {
        switch self {
        case .light: return "Light"; case .medium: return "Medium"; case .big: return "Big"
        }
    }

    private var rank: Int {
        switch self { case .light: return 0; case .medium: return 1; case .big: return 2 }
    }
    static func < (lhs: SupportMagnitude, rhs: SupportMagnitude) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - SupportDay / SupportPattern

/// One declared support day: "Tuesday, medium."
struct SupportDay: Codable, Hashable, Identifiable {
    var weekday: Weekday
    var magnitude: SupportMagnitude
    var id: Int { weekday.rawValue }
}

/// The support sport plus its declared weekly rhythm. This is the ONLY thing
/// persisted for the support sport (intent, not output): the scheduled week is
/// always re-derived from it.
struct SupportPattern: Codable, Hashable, Equatable {
    var sportSlug: String
    var variant: SportVariant
    /// At most one entry per weekday; kept sorted for stable hashing/encoding.
    var days: [SupportDay]

    init(sportSlug: String, variant: SportVariant, days: [SupportDay]) {
        self.sportSlug = sportSlug
        self.variant = variant
        // Dedupe by weekday (last declaration wins) + sort → canonical form.
        var byDay: [Weekday: SupportDay] = [:]
        for d in days { byDay[d.weekday] = d }
        self.days = byDay.values.sorted { $0.weekday < $1.weekday }
    }

    var isEmpty: Bool { days.isEmpty }
    func magnitude(on weekday: Weekday) -> SupportMagnitude? {
        days.first { $0.weekday == weekday }?.magnitude
    }
}

// MARK: - SupportInterference (the rules table)

/// How much one support day of a given magnitude interferes with the primary
/// plan, keyed by (primary variant, support variant, magnitude).
///
///   restDaysBefore — the week's heaviest primary session must sit at least
///     this many days BEFORE a support day of this magnitude (the 48h rule is
///     restDaysBefore = 2). Directional: heavy legs the day before a big
///     alpine day wrecks it; the day after merely hurts.
///   loadFraction — the fraction of a mean primary session this support day
///     consumes from the weekly budget. When the week's summed fractions reach
///     a full session-equivalent, SupportScheduler lightens the plan.
struct SupportInterference: Equatable {
    let restDaysBefore: Int
    let loadFraction: Double

    /// v1 wedge: ski/board primary × climbing support, authored from felt
    /// sense (shralpinism). Climbing is upper-dominant so leg interference is
    /// modest — EXCEPT tradAlpine, where a "big day" means approach + descent
    /// on foot: that is leg work and gets the full 48h buffer.
    static func resolve(primary: SportVariant,
                        support: SportVariant,
                        magnitude: SupportMagnitude) -> SupportInterference {
        switch (support, magnitude) {
        // Sport routes: pump + upper fatigue, legs mostly fresh.
        case (.sportRoute, .light):  return .init(restDaysBefore: 0, loadFraction: 0.10)
        case (.sportRoute, .medium): return .init(restDaysBefore: 1, loadFraction: 0.30)
        case (.sportRoute, .big):    return .init(restDaysBefore: 1, loadFraction: 0.50)
        // Bouldering: max-effort pulls + dynamic hips; power interference.
        case (.boulder, .light):     return .init(restDaysBefore: 0, loadFraction: 0.15)
        case (.boulder, .medium):    return .init(restDaysBefore: 1, loadFraction: 0.35)
        case (.boulder, .big):       return .init(restDaysBefore: 1, loadFraction: 0.60)
        // Trad/alpine: the approach IS leg training. Big day = full buffer.
        case (.tradAlpine, .light):  return .init(restDaysBefore: 0, loadFraction: 0.20)
        case (.tradAlpine, .medium): return .init(restDaysBefore: 1, loadFraction: 0.50)
        case (.tradAlpine, .big):    return .init(restDaysBefore: 2, loadFraction: 1.00)
        // Non-wedge combos: moderate generic row until authored.
        default:
            switch magnitude {
            case .light:  return .init(restDaysBefore: 0, loadFraction: 0.15)
            case .medium: return .init(restDaysBefore: 1, loadFraction: 0.40)
            case .big:    return .init(restDaysBefore: 2, loadFraction: 0.75)
            }
        }
    }
}
