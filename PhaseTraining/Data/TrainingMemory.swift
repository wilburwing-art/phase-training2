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
    var schemaVersion: Int = 1

    // Identity / intent
    var sports: [Sport] = []
    var primarySport: Sport? = nil
    var primaryFocus: PrimaryFocus = .generalStrength
    var season: SeasonPhase = .maintenance

    // Schedule / capacity
    var availableDays: [Weekday] = []
    var fixedSportDays: [Weekday: Sport] = [:]
    var sessionMinutes: Int = 45

    // Resources / level
    var equipment: [Equipment] = [.bodyweight]
    var experience: ExperienceLevel = .beginner

    // Free-text guardrails
    var dislikes: [String] = []
    var constraints: [String] = []

    // Append-only history (Phases 11–12 fill these)
    var feedback: [FeedbackEntry] = []
    var soreness: [SorenessEntry] = []
    var weeklyCheckIns: [WeeklyCheckIn] = []

    // Lifecycle
    var onboardedAt: Date? = nil

    // Tolerant decode — every field defaults so future additions don't break older saves.
    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion, sports, primarySport, primaryFocus, season
        case availableDays, fixedSportDays, sessionMinutes
        case equipment, experience
        case dislikes, constraints
        case feedback, soreness, weeklyCheckIns
        case onboardedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion   = (try? c.decode(Int.self,            forKey: .schemaVersion))   ?? 1
        self.sports          = (try? c.decode([Sport].self,        forKey: .sports))          ?? []
        self.primarySport    =  try? c.decodeIfPresent(Sport.self, forKey: .primarySport)
        self.primaryFocus    = (try? c.decode(PrimaryFocus.self,   forKey: .primaryFocus))    ?? .generalStrength
        self.season          = (try? c.decode(SeasonPhase.self,    forKey: .season))          ?? .maintenance
        self.availableDays   = (try? c.decode([Weekday].self,      forKey: .availableDays))   ?? []
        self.fixedSportDays  = (try? c.decode([Weekday: Sport].self, forKey: .fixedSportDays)) ?? [:]
        self.sessionMinutes  = (try? c.decode(Int.self,            forKey: .sessionMinutes))  ?? 45
        self.equipment       = (try? c.decode([Equipment].self,    forKey: .equipment))       ?? [.bodyweight]
        self.experience      = (try? c.decode(ExperienceLevel.self, forKey: .experience))     ?? .beginner
        self.dislikes        = (try? c.decode([String].self,       forKey: .dislikes))        ?? []
        self.constraints     = (try? c.decode([String].self,       forKey: .constraints))     ?? []
        self.feedback        = (try? c.decode([FeedbackEntry].self, forKey: .feedback))       ?? []
        self.soreness        = (try? c.decode([SorenessEntry].self, forKey: .soreness))       ?? []
        self.weeklyCheckIns  = (try? c.decode([WeeklyCheckIn].self, forKey: .weeklyCheckIns)) ?? []
        self.onboardedAt     =  try? c.decodeIfPresent(Date.self,  forKey: .onboardedAt)
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
        let slug = try c.decode(String.self)
        if let known = Sport.catalog.first(where: { $0.slug == slug }) {
            self = known
        } else {
            self = Sport(slug: slug, name: slug.replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(slug)
    }

    /// Curated subset of coach.db sport_categories — the ones onboarding offers.
    /// Keep slugs aligned with the DB; add liberally as needs arise.
    static let catalog: [Sport] = [
        Sport(slug: "general_fitness",        name: "General Fitness"),
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
        Sport(slug: "snow_sports",            name: "Skiing / Snowboarding"),
        Sport(slug: "alpine_skiing",          name: "Alpine Skiing"),
        Sport(slug: "ski_mountaineering",     name: "Ski Mountaineering"),
        Sport(slug: "mountaineering",         name: "Mountaineering"),
        Sport(slug: "hiking_trekking",        name: "Hiking / Trekking"),
        Sport(slug: "trail_running",          name: "Trail Running"),
        Sport(slug: "yoga",                   name: "Yoga"),
        Sport(slug: "pilates",                name: "Pilates"),
        Sport(slug: "crossfit",               name: "CrossFit"),
        Sport(slug: "powerlifting",           name: "Powerlifting"),
        Sport(slug: "olympic_weightlifting",  name: "Olympic Weightlifting"),
        Sport(slug: "bodybuilding",           name: "Bodybuilding"),
        Sport(slug: "martial_arts",           name: "Martial Arts"),
        Sport(slug: "brazilian_jiu_jitsu",    name: "Brazilian Jiu-Jitsu"),
        Sport(slug: "boxing",                 name: "Boxing"),
        Sport(slug: "muay_thai",              name: "Muay Thai"),
        Sport(slug: "rowing",                 name: "Rowing"),
        Sport(slug: "paddle_sports",          name: "Paddle Sports"),
        Sport(slug: "stand_up_paddleboarding", name: "Stand-Up Paddleboarding"),
        Sport(slug: "obstacle_course_racing", name: "Obstacle Course Racing"),
        Sport(slug: "dance",                  name: "Dance")
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
