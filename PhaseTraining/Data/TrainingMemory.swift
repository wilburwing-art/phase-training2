// TrainingMemory.swift — long-lived user profile + history substrate.
// Persisted via MemoryStore under UserDefaults key `pt_training_memory`.
//
// Owns everything the rules-based planner (Phase 10) and the future coach
// (Phase 13) need to reason about: who the user is, what they want, what's
// happened, what hurt. Schema is versioned via `schemaVersion`; readers do a
// best-effort decode and tolerate missing fields by falling back to defaults.
//
// FeedbackEntry / SorenessEntry / WeeklyCheckIn are stub-shaped here. Phases 11
// and 12 flesh them out — the names + ID-stable round-trip stay stable.

import Foundation

// MARK: - Top-level

struct TrainingMemory: Codable {
    var schemaVersion: Int = 5

    // Identity / intent
    var sports: [Sport] = []
    var primarySport: Sport? = nil
    /// Multi-select. First entry is primary; planner uses focuses.first for shape resolution.
    var focuses: [PrimaryFocus] = [.generalStrength]
    /// Per-sport season. Allows pre-season skiing + year-round climbing simultaneously.
    var seasonsBySport: [Sport: SeasonPhase] = [:]
    /// Used when no sport is set OR for any sport without a per-sport entry.
    var defaultSeason: SeasonPhase = .maintenance

    // Schedule / capacity
    //
    // NOTE (Phase 11): availableDays + fixedSportDays were removed from the
    // memory because availability now lives per-week in WeekOverrides. The
    // tolerant decode still consumes legacy keys so build 20-24 saves load
    // without crashing — those values are dropped on the next encode.
    var sessionMinutes: Int = 45
    /// Target lift days per week (planner enforces). 0–7.
    var liftDaysPerWeek: Int = 3

    // Resources / level
    var equipment: [Equipment] = [.bodyweight]
    var experience: ExperienceLevel = .beginner
    /// Current condition vs experience ceiling. Defaults to .freshStart for
    /// new installs — the LLM coach uses this as a permanent profile fact
    /// to dial early-session conservatism. Build 72+: no deterministic
    /// preset / time window; the coach just reads the signal and reasons.
    var startingState: StartingState = .freshStart

    // About you (optional)
    var age: Int? = nil
    var gender: Gender? = nil
    /// Body height in whole centimetres. Stored metric; rendered in the
    /// user's preferred unit system (see `usesImperial`). Nil = skipped.
    var heightCm: Int? = nil
    /// Body weight in kilograms with one-decimal precision. Stored metric;
    /// rendered per `usesImperial`. Nil = skipped.
    var weightKg: Double? = nil
    /// Display preference for height + weight. Defaults true (US default);
    /// users elsewhere can flip on the Profile screen.
    var usesImperial: Bool = true

    // Free-text guardrails
    var dislikes: [String] = []
    var constraints: [String] = []

    // Append-only history (Phases 11–12 fill these)
    var feedback: [FeedbackEntry] = []
    var soreness: [SorenessEntry] = []
    var weeklyCheckIns: [WeeklyCheckIn] = []
    /// Phase 13e: proactive observations the coach writes on app foreground.
    /// Rolling 30-day window; trimmed on append.
    var coachInsights: [CoachInsight] = []

    // Lifecycle
    var onboardedAt: Date? = nil

    // Tolerant decode — every field defaults so future additions don't break older saves.
    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion, sports, primarySport
        case focuses, seasonsBySport, defaultSeason
        case primaryFocus, season                 // legacy (build 20-23) — read for migration
        case availableDays, fixedSportDays        // legacy (build 20-24) — read but dropped on encode
        case sessionMinutes, liftDaysPerWeek
        case equipment, experience
        case startingState
        case age, gender
        case heightCm, weightKg, usesImperial
        case dislikes, constraints
        case feedback, soreness, weeklyCheckIns
        case coachInsights
        case onboardedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion   = (try? c.decode(Int.self,            forKey: .schemaVersion))   ?? 2
        self.sports          = (try? c.decode([Sport].self,        forKey: .sports))          ?? []
        self.primarySport    =  try? c.decodeIfPresent(Sport.self, forKey: .primarySport)

        // Focus migration: prefer focuses[]; fall back to legacy primaryFocus singleton.
        if let arr = try? c.decode([PrimaryFocus].self, forKey: .focuses), !arr.isEmpty {
            self.focuses = arr
        } else if let legacy = try? c.decode(PrimaryFocus.self, forKey: .primaryFocus) {
            self.focuses = [legacy]
        } else {
            self.focuses = [.generalStrength]
        }

        // Season migration: prefer seasonsBySport map + defaultSeason; fall back to legacy
        // single `season` (which becomes both the default and per-primary-sport entry).
        self.seasonsBySport = (try? c.decode([Sport: SeasonPhase].self, forKey: .seasonsBySport)) ?? [:]
        if let ds = try? c.decode(SeasonPhase.self, forKey: .defaultSeason) {
            self.defaultSeason = ds
        } else if let legacySeason = try? c.decode(SeasonPhase.self, forKey: .season) {
            self.defaultSeason = legacySeason
            if let s = self.primarySport, self.seasonsBySport[s] == nil {
                self.seasonsBySport[s] = legacySeason
            }
        } else {
            self.defaultSeason = .maintenance
        }

        // availableDays + fixedSportDays are intentionally not stored anymore;
        // we don't read them on decode because the runtime no longer has slots
        // for them. The legacy keys remain in CodingKeys so old JSON parses
        // cleanly via try? c.decode (the value is just discarded).
        self.sessionMinutes  = (try? c.decode(Int.self,            forKey: .sessionMinutes))  ?? 45
        self.liftDaysPerWeek = (try? c.decode(Int.self,            forKey: .liftDaysPerWeek)) ?? 3
        self.equipment       = (try? c.decode([Equipment].self,    forKey: .equipment))       ?? [.bodyweight]
        self.experience      = (try? c.decode(ExperienceLevel.self, forKey: .experience))     ?? .beginner
        self.startingState   = (try? c.decode(StartingState.self,  forKey: .startingState))   ?? .freshStart
        self.age             =  try? c.decodeIfPresent(Int.self,    forKey: .age)
        self.gender          =  try? c.decodeIfPresent(Gender.self, forKey: .gender)
        self.heightCm        =  try? c.decodeIfPresent(Int.self,    forKey: .heightCm)
        self.weightKg        =  try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        self.usesImperial    = (try? c.decode(Bool.self,            forKey: .usesImperial)) ?? true
        self.dislikes        = (try? c.decode([String].self,       forKey: .dislikes))        ?? []
        self.constraints     = (try? c.decode([String].self,       forKey: .constraints))     ?? []
        self.feedback        = (try? c.decode([FeedbackEntry].self, forKey: .feedback))       ?? []
        self.soreness        = (try? c.decode([SorenessEntry].self, forKey: .soreness))       ?? []
        self.weeklyCheckIns  = (try? c.decode([WeeklyCheckIn].self, forKey: .weeklyCheckIns)) ?? []
        self.coachInsights   = (try? c.decode([CoachInsight].self, forKey: .coachInsights)) ?? []
        self.onboardedAt     =  try? c.decodeIfPresent(Date.self,  forKey: .onboardedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion,   forKey: .schemaVersion)
        try c.encode(sports,          forKey: .sports)
        try c.encodeIfPresent(primarySport, forKey: .primarySport)
        try c.encode(focuses,         forKey: .focuses)
        try c.encode(seasonsBySport,  forKey: .seasonsBySport)
        try c.encode(defaultSeason,   forKey: .defaultSeason)
        try c.encode(sessionMinutes,  forKey: .sessionMinutes)
        try c.encode(liftDaysPerWeek, forKey: .liftDaysPerWeek)
        try c.encode(equipment,       forKey: .equipment)
        try c.encode(experience,      forKey: .experience)
        try c.encode(startingState,   forKey: .startingState)
        try c.encodeIfPresent(age,    forKey: .age)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(heightCm, forKey: .heightCm)
        try c.encodeIfPresent(weightKg, forKey: .weightKg)
        try c.encode(usesImperial, forKey: .usesImperial)
        try c.encode(dislikes,        forKey: .dislikes)
        try c.encode(constraints,     forKey: .constraints)
        try c.encode(feedback,        forKey: .feedback)
        try c.encode(soreness,        forKey: .soreness)
        try c.encode(weeklyCheckIns,  forKey: .weeklyCheckIns)
        try c.encode(coachInsights,   forKey: .coachInsights)
        try c.encodeIfPresent(onboardedAt, forKey: .onboardedAt)
    }
}

// MARK: - Convenience accessors

extension TrainingMemory {
    /// Primary focus — first entry in focuses, or .generalStrength if empty.
    var primaryFocus: PrimaryFocus {
        focuses.first ?? .generalStrength
    }

    /// Season the planner should use to pick a WeeklyShape. Reads
    /// seasonsBySport[primarySport] first, then falls back to defaultSeason.
    var seasonForPlanner: SeasonPhase {
        if let s = primarySport, let season = seasonsBySport[s] {
            return season
        }
        return defaultSeason
    }
}

// MARK: - Sport
//
// Stored as a slug (singleValue String). Catalog lookup at decode time means a
// renamed display label propagates without rewriting old saves. Slugs match
// coach.db `sport_categories.slug` so the planner can join directly.

struct Sport: Codable, Hashable, Identifiable {
    let slug: String
    let name: String
    var id: String { slug }

    init(slug: String, name: String) {
        self.slug = slug
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        // Normalize legacy underscore slugs (build 20-22 wrote these) to the
        // hyphenated form coach.db actually uses. Falls back to a synthetic
        // entry if the slug never matched any catalog row.
        let normalized = raw.replacingOccurrences(of: "_", with: "-")
        if let known = Sport.catalog.first(where: { $0.slug == normalized }) {
            self = known
        } else if let known = Sport.catalog.first(where: { $0.slug == raw }) {
            self = known
        } else {
            self = Sport(slug: raw, name: raw.replacingOccurrences(of: "_", with: " ")
                                              .replacingOccurrences(of: "-", with: " ")
                                              .capitalized)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(slug)
    }

    /// Curated subset of coach.db sport_categories — the ones onboarding offers.
    /// Slugs are hyphenated to match `coach.db` exactly so the Planner can
    /// join on `sport_categories.slug`. "general-fitness" is synthetic (no DB
    /// row) — the planner falls back to a default WeeklyShape when seen.
    static let catalog: [Sport] = [
        Sport(slug: "general-fitness",        name: "General Fitness"),
        Sport(slug: "climbing",               name: "Climbing"),
        Sport(slug: "running",                name: "Running"),
        Sport(slug: "cycling",                name: "Cycling"),
        Sport(slug: "swimming",               name: "Swimming"),
        Sport(slug: "tennis",                 name: "Tennis"),
        Sport(slug: "pickleball",             name: "Pickleball"),
        Sport(slug: "soccer",                 name: "Soccer"),
        Sport(slug: "basketball",             name: "Basketball"),
        Sport(slug: "volleyball",             name: "Volleyball"),
        Sport(slug: "golf",                   name: "Golf"),
        Sport(slug: "surfing",                name: "Surfing"),
        Sport(slug: "snow-sports",            name: "Skiing / Snowboarding"),
        Sport(slug: "alpine-skiing",          name: "Alpine Skiing"),
        Sport(slug: "ski-mountaineering",     name: "Ski Mountaineering"),
        Sport(slug: "mountaineering",         name: "Mountaineering"),
        Sport(slug: "hiking-trekking",        name: "Hiking / Trekking"),
        Sport(slug: "trail-running",          name: "Trail Running"),
        Sport(slug: "yoga",                   name: "Yoga"),
        Sport(slug: "pilates",                name: "Pilates"),
        Sport(slug: "crossfit",               name: "CrossFit"),
        Sport(slug: "powerlifting",           name: "Powerlifting"),
        Sport(slug: "olympic-weightlifting",  name: "Olympic Weightlifting"),
        Sport(slug: "bodybuilding",           name: "Bodybuilding"),
        Sport(slug: "martial-arts",           name: "Martial Arts"),
        Sport(slug: "bjj",                    name: "Brazilian Jiu-Jitsu"),
        Sport(slug: "boxing",                 name: "Boxing"),
        Sport(slug: "muay-thai",              name: "Muay Thai"),
        Sport(slug: "rowing",                 name: "Rowing"),
        Sport(slug: "paddle-sports",          name: "Paddle Sports"),
        Sport(slug: "stand-up-paddleboarding", name: "Stand-Up Paddleboarding"),
        Sport(slug: "obstacle-course-racing", name: "Obstacle Course Racing")
    ]
}

// MARK: - Enums

enum PrimaryFocus: String, Codable, CaseIterable, Identifiable {
    case generalStrength    = "general_strength"
    case hypertrophy
    case sportPerformance   = "sport_performance"
    case endurance
    case mobility
    case weightLoss         = "weight_loss"
    case longevity
    case rehab

    var id: String { rawValue }

    var label: String {
        switch self {
        case .generalStrength:  return "Get stronger"
        case .hypertrophy:      return "Build muscle"
        case .sportPerformance: return "Sport performance"
        case .endurance:        return "Build endurance"
        case .mobility:         return "Move better"
        case .weightLoss:       return "Lose weight"
        case .longevity:        return "Longevity / healthspan"
        case .rehab:            return "Recover from injury"
        }
    }

    var subtitle: String {
        switch self {
        case .generalStrength:  return "Compound lifts, progressive overload"
        case .hypertrophy:      return "Volume + isolation, look the part"
        case .sportPerformance: return "Power + prehab + sport-specific"
        case .endurance:        return "Zone 2, intervals, work capacity"
        case .mobility:         return "Range of motion + control"
        case .weightLoss:       return "Calorie burn + lean mass retention"
        case .longevity:        return "Strength + balance + cardio mix"
        case .rehab:            return "Targeted PT-style work"
        }
    }
}

enum SeasonPhase: String, Codable, CaseIterable, Identifiable {
    case offSeason   = "off_season"
    case preSeason   = "pre_season"
    case inSeason    = "in_season"
    case eventPrep   = "event_prep"
    case maintenance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .offSeason:   return "Off-season"
        case .preSeason:   return "Pre-season"
        case .inSeason:    return "In-season"
        case .eventPrep:   return "Event prep"
        case .maintenance: return "Year-round / maintenance"
        }
    }

    var subtitle: String {
        switch self {
        case .offSeason:   return "Build the engine — high volume, lower specificity"
        case .preSeason:   return "Sharpen — convert to sport-specific"
        case .inSeason:    return "Maintain — protect performance, recover hard"
        case .eventPrep:   return "Peak — taper to a date"
        case .maintenance: return "Stay strong — no peak in mind"
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Hashable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    var short: String {
        switch self {
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        case .sunday:    return "Sun"
        }
    }
    var letter: String { String(short.prefix(1)) }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case bodyweight     = "none"
    case dumbbells
    case barbell
    case kettlebell
    case bands          = "resistance_band"
    case pullUpBar      = "pull_up_bar"
    case cableMachine   = "cable_machine"
    case bench
    case yogaMat        = "yoga_mat"
    case plyoBox        = "plyo_box"
    case medicineBall   = "medicine_ball"
    case weightVest     = "weight_vest"
    case sandbag
    case fullGym        = "full_gym"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bodyweight:   return "Bodyweight only"
        case .dumbbells:    return "Dumbbells"
        case .barbell:      return "Barbell + plates"
        case .kettlebell:   return "Kettlebells"
        case .bands:        return "Resistance bands"
        case .pullUpBar:    return "Pull-up bar"
        case .cableMachine: return "Cable machine"
        case .bench:        return "Bench"
        case .yogaMat:      return "Yoga mat"
        case .plyoBox:      return "Plyo box"
        case .medicineBall: return "Medicine ball"
        case .weightVest:   return "Weight vest"
        case .sandbag:      return "Sandbag"
        case .fullGym:      return "Full commercial gym"
        }
    }

    var icon: String {
        switch self {
        case .bodyweight:   return "figure.walk"
        case .dumbbells:    return "dumbbell.fill"
        case .barbell:      return "figure.strengthtraining.traditional"
        case .kettlebell:   return "figure.strengthtraining.functional"
        case .bands:        return "waveform.path"
        case .pullUpBar:    return "minus"
        case .cableMachine: return "rectangle.connected.to.line.below"
        case .bench:        return "rectangle"
        case .yogaMat:      return "rectangle.portrait"
        case .plyoBox:      return "cube"
        case .medicineBall: return "circle.fill"
        case .weightVest:   return "rectangle.compress.vertical"
        case .sandbag:      return "shippingbox.fill"
        case .fullGym:      return "building.2.fill"
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var label: String {
        switch self {
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced:     return "Advanced"
        }
    }
    var subtitle: String {
        switch self {
        case .beginner:     return "New to structured training, or returning after a long break"
        case .intermediate: return "1+ year consistent, comfortable with main lifts"
        case .advanced:     return "Multiple years, push close to true limits"
        }
    }
}

/// Build 72 — current condition, independent of experience ceiling.
/// Drives the calibration-week mechanic: same 7-day baseline window for
/// everyone, but per-state dialed intensity + soreness messaging. An
/// advanced lifter returning from injury is `experience=.advanced +
/// startingState=.returning` — both signals shape programming.
enum StartingState: String, Codable, CaseIterable, Identifiable {
    case freshStart        = "fresh_start"
    case returning         = "returning"
    case currentlyTraining = "currently_training"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .freshStart:        return "Just starting out"
        case .returning:         return "Coming back"
        case .currentlyTraining: return "Actively training"
        }
    }

    var subtitle: String {
        switch self {
        case .freshStart:        return "Never trained, or > 12 months off"
        case .returning:         return "Lifted before but ≥ 3 months off"
        case .currentlyTraining: return "Trained in the last 3 months"
        }
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case female, male, nonbinary, preferNotToSay = "prefer_not_to_say"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .female:         return "Female"
        case .male:           return "Male"
        case .nonbinary:      return "Non-binary"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

// MARK: - Append-only history (stubs; Phases 11–12 extend)

struct FeedbackEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var sessionId: String?
    /// "too_easy" | "right" | "too_hard" — kept loose for now.
    var difficulty: String?
    var hurtAreas: [String] = []
    var ranLong: Bool = false
    var notes: String?
}

struct SorenessEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    /// "low" | "normal" | "high"
    var energy: String?
    /// "none" | "mild" | "high"
    var soreness: String?
    var pain: Bool = false
    var areas: [String] = []
    var timeBudget: Int? = nil
    var equipmentChanged: Bool = false
}

struct WeeklyCheckIn: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var weekStart: Date
    var intent: String?
    var lastWeekRating: String?
    var notes: String?
}

// MARK: - Weekday ↔ Date helpers

extension Weekday {
    /// Calendar weekday is 1=Sun..7=Sat. Convert from ISO 1=Mon..7=Sun.
    static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        let ios = calendar.component(.weekday, from: date) // 1=Sun
        // Map Sun(1)->Sun, Mon(2)->Mon ... Sat(7)->Sat
        switch ios {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
}
