// SportProfile.swift: every per-sport decision in one table.
//
// Before Phase 3b (2026-11-11) about ten places decided ski or climbing
// membership on their own: the rule table, the season engine gate, the
// signature demand, the movement pool, the default variant, the SessionMix
// family, the authored pilot, the two-sport feature (planner, onboarding,
// profile), the ski discipline, and the two ski cards, two of which added
// snowboarding by hand. A sport changed in one and not the others planned
// differently from its picker twin (`snowboarding` against `snow-sports`).
// Each of those now reads this table.

import Foundation

struct SportProfile: Equatable {

    /// Which PhaseRule table governs the sport.
    enum Rules: Equatable {
        /// `PhaseRule.skiing`, sport sessions from the season engine.
        case ski
        /// `PhaseRule.climbing`, sport sessions from authored routines first
        /// (the pilot), the engine when none fits.
        case climbing
        /// `PhaseRule.general`: sport sessions are authored routines only; the
        /// rule sets the complement days' dose.
        case general
    }

    let rules: Rules
    /// The one demand every engine sport session keeps (fatigue cap and
    /// `guaranteeSignature`). Nil when no single demand defines the sport.
    let signature: Demand?
    /// What the sport's own sessions load, which decides what its complement
    /// days train (SessionMix).
    let family: SessionMix.Family
    /// The primary/support two-sport feature: the onboarding section, the
    /// Profile row and the planner's deconflict pass.
    let supportFeature: Bool
    /// Written routines are served on sport days ahead of the engine, for a
    /// sport the engine could also build. The engine fills in only where no
    /// routine fits the season, level, equipment or injuries.
    var writtenFirst: Bool = false

    /// The season engine builds this sport's sessions.
    var usesSeasonEngine: Bool { rules != .general }
    /// Authored routines are preferred over the engine: climbing, and any
    /// sport marked `writtenFirst`.
    var authoredOverEngine: Bool { rules == .climbing || writtenFirst }
    /// A ski or board sport: the disciplines, the ski readiness card and the
    /// SkiSeason Health summary.
    var isSki: Bool { rules == .ski }

    /// The `sport_movements.sport` that holds this sport's engine pool. The ski
    /// sports share one movement vocabulary and the climbing sports another;
    /// `PhaseRule.applyingVariantOverride` expresses their differences.
    func poolSlug(for slug: String) -> String {
        switch rules {
        case .ski: return "alpine-skiing"
        case .climbing: return "climbing"
        case .general: return slug
        }
    }

    private func with(signature: Demand? = nil, family: SessionMix.Family? = nil) -> SportProfile {
        SportProfile(rules: rules, signature: signature ?? self.signature,
                     family: family ?? self.family, supportFeature: supportFeature)
    }

    /// The sport's own row, else one inherited from its family (`familySlug`),
    /// else `unlisted`.
    static func of(_ slug: String?) -> SportProfile {
        guard let slug else { return unlisted }
        if let row = table[slug] { return row }
        guard let family = familySlug(of: slug), let row = table[family] else { return unlisted }
        // An inherited row keeps the family's signature and complement family
        // and nothing else. Freestyle skiing would otherwise land on the ski
        // engine and bouldering-indoor on the climbing engine, neither of
        // which knows them; their sport days are the written routines.
        return SportProfile(rules: .general, signature: row.signature,
                            family: row.family, supportFeature: false)
    }

    /// Slugs in the table under `rules`.
    static func slugs(_ rules: Rules) -> Set<String> {
        Set(table.filter { $0.value.rules == rules }.keys)
    }

    /// Every slug whose profile is `.general` and comes from a row: the
    /// table's own general rows plus every catalog sport that inherits one.
    /// `general-fitness` and `misc-outdoor` reach no row and stay out.
    static let generalSlugs: Set<String> = {
        let inheriting = Set(parents.keys).union(familyOverride.keys)
            .filter { table[$0] == nil && familySlug(of: $0) != nil }
        return slugs(.general).union(inheriting)
    }()

    /// The nearest ancestor (through `familyOverride`, then
    /// `sport_categories.parent_id`) that has a row in `table`. Nil for a slug
    /// with its own row and for one no row covers.
    static func familySlug(of slug: String) -> String? {
        guard table[slug] == nil else { return nil }
        var seen: Set<String> = [slug]
        var next = familyOverride[slug] ?? parents[slug]
        while let current = next, seen.insert(current).inserted {
            if table[current] != nil { return current }
            next = familyOverride[current] ?? parents[current]
        }
        return nil
    }

    /// Every ancestor of `slug`, nearest first, through `familyOverride` then
    /// `sport_categories.parent_id`. `tennis-singles` gives `tennis`,
    /// `racquet-sports`. Empty for a root or an unknown slug.
    static func ancestors(of slug: String) -> [String] {
        var seen: Set<String> = [slug]
        var chain: [String] = []
        var next = familyOverride[slug] ?? parents[slug]
        while let current = next, seen.insert(current).inserted {
            chain.append(current)
            next = familyOverride[current] ?? parents[current]
        }
        return chain
    }

    /// Owner decision, 2026-11-18 (backlog 11e #2): these follow a sport other
    /// than their catalog parent. Via ferrata trains like scrambling, and
    /// misc-outdoor, the parent of geocaching and bikejoring, has no program.
    static let familyOverride: [String: String] = [
        "via-ferrata": "scrambling",
        "geocaching": "day-hiking",
        "bikejoring": "mountain-biking",
    ]

    /// child slug -> parent slug, read once from coach.db.
    private static let parents: [String: String] = CoachDatabase.shared.sportParentSlugs()

    /// A sport with no row: the general rule, legs-dominant complements.
    static let unlisted = SportProfile(rules: .general, signature: nil,
                                       family: .legsDominant, supportFeature: false)

    private static let ski = SportProfile(rules: .ski, signature: .eccentricLeg,
                                          family: .legsDominant, supportFeature: true)
    private static let climb = SportProfile(rules: .climbing, signature: .fingerStrength,
                                            family: .upperDominant, supportFeature: false)
    private static let authoredOnly = SportProfile(rules: .general, signature: nil,
                                                   family: .legsDominant, supportFeature: false)

    static let table: [String: SportProfile] = [
        "alpine-skiing": ski,
        "ski-mountaineering": ski,
        "snow-sports": ski,
        // Owner decision, 2026-11-11: sport days are the written splitboard
        // routines, served as written; the engine fills a season with none.
        // Everything else follows the ski row: the complement days' rule, the
        // disciplines, the two-sport feature and the ski cards. (An earlier
        // call the same day put the sport days on the engine too, and was
        // reversed: written programs come first.)
        "snowboarding": SportProfile(rules: .ski, signature: .eccentricLeg, family: .legsDominant,
                                     supportFeature: true, writtenFirst: true),

        "climbing": climb,
        "bouldering": climb,
        "sport-climbing": climb,
        "trad-climbing": climb,
        "alpine-climbing": climb,
        "ice-climbing": climb,
        "mixed-climbing": climb,

        // Signatures (Phase 3b, item 4). Mountain biking has none: its gym
        // needs split between leg power, leg endurance and grip, and no one
        // Demand names the reason the block exists. Mountaineering's loaded
        // carry has no Demand case, so it takes legEndurance, as do the two
        // hiking sports. Trail running takes eccentricLeg: the descents.
        "mountain-biking": authoredOnly,
        // Owner decision, 2026-11-15: cycling is picked as a primary sport and
        // reads like mountain biking (no signature); running takes legEndurance.
        "cycling": authoredOnly,
        "running": authoredOnly.with(signature: .legEndurance),
        // Owner decision, 2026-11-15: paddle sports and SUP complement days are
        // upper-dominant with a pulling endurance signature.
        "paddle-sports": authoredOnly.with(signature: .pullEndurance, family: .upperDominant),
        "sup": authoredOnly.with(signature: .pullEndurance, family: .upperDominant),
        // Item 5: the pack loads the upper back and trunk the legs carry it
        // with, so complement days lead with them.
        "mountaineering": authoredOnly.with(signature: .legEndurance, family: .legsAndCarry),
        "trail-running": authoredOnly.with(signature: .eccentricLeg),
        "hiking-trekking": authoredOnly.with(signature: .legEndurance),
        "thru-hiking": authoredOnly.with(signature: .legEndurance),

        // Owner decision, 2026-11-18 (backlog 11e #1): one row per family
        // root. Every catalog sport under a root inherits its row through
        // `of(_:)` unless it has one of its own.
        "martial-arts": authoredOnly.with(signature: .contactStrength, family: .upperDominant),
        "golf": authoredOnly.with(signature: .core),
        "racquet-sports": authoredOnly.with(signature: .power),
        "surf-wave-sports": authoredOnly.with(signature: .pullEndurance, family: .upperDominant),
        "swimming": authoredOnly.with(signature: .pullEndurance, family: .upperDominant),
        "multi-sport-endurance": authoredOnly.with(signature: .legEndurance),
        "team-rec-sports": authoredOnly.with(signature: .power),
        "skating-wheeled": authoredOnly.with(signature: .legEndurance),
        "yoga-movement": authoredOnly.with(signature: .bodyTension, family: .upperDominant),
        "strength-fitness-sports": authoredOnly.with(signature: .maxStrength),
        "sailing-air-sports": authoredOnly.with(signature: .core),
        "equestrian": authoredOnly.with(signature: .core),
        "archery-shooting": authoredOnly.with(signature: .pullEndurance, family: .upperDominant),
        "fishing-hunting": authoredOnly.with(signature: .legEndurance, family: .legsAndCarry),
        "dance-fitness": authoredOnly.with(signature: .legEndurance),
    ]
}
