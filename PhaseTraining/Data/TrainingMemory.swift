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
    var schemaVersion: Int = 7

    // Identity / intent
    var sports: [Sport] = []
    var primarySport: Sport? = nil
    /// Per-sport season. Allows pre-season skiing + year-round climbing simultaneously.
    var seasonsBySport: [Sport: SeasonPhase] = [:]
    /// The SUPPORT sport's declared weekly load (primary/support model —
    /// PLAN-primary-support.md). When set, the planner reflows the primary
    /// lift week AROUND these days instead of just placing a crude placeholder
    /// (the `applySecondarySportPromotion` path). Persisted INTENT only: the
    /// scheduled week is always re-derived from this by SupportScheduler.
    /// nil = single-sport user (no change to shipped behavior).
    var supportPattern: SupportPattern? = nil
    /// Used when no sport is set OR for any sport without a per-sport entry.
    var defaultSeason: SeasonPhase = .maintenance
    /// Target peak date for .eventPrep seasons. Build 78 — before this, .eventPrep
    /// was just a label that fell through to .maintenance in WeeklyShape resolution,
    /// with no actual peak/taper behavior. When set, the planner applies a hard-race
    /// style taper to the week containing this date.
    var peakDate: Date? = nil
    /// Stamped when the user changes their planner season (default or per-sport).
    /// Powers the "Week N of {phase}" subtext on the SeasonPhaseBadge so the
    /// user can see how deep they are into the current block at a glance.
    /// Nil for installs that pre-date the badge — the badge falls back to
    /// just the phase label without a week counter.
    var phaseStartedAt: Date? = nil

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

    // MARK: - Sensitive (health-adjacent)
    //
    // Fields tagged `SENSITIVE` below are health-adjacent: do not log, do not
    // include in crash reports, and do not send to any third-party SDK without
    // an explicit privacy review. See MemoryStore.swift for the full privacy
    // posture. Data-minimization rule: only add one here if a feature actually
    // consumes it (each grows the App Store + GDPR special-category surface).

    /// SENSITIVE. Optional. Onboarding "About" step + generator age clamps.
    var age: Int? = nil
    /// SENSITIVE. Optional. Onboarding "About" step + coach body section.
    var gender: Gender? = nil
    /// Phase 1 era-affinity: user's training-culture cohort preference.
    /// Stored as the `EraCohort` rawValue ("magazine_bodybuilding" etc.)
    /// so this file doesn't have to depend on EraCohort directly —
    /// mirrors the precedent set by Sport (slug stored, catalog resolved
    /// at decode time on the consumer side). Nil = "use derived from age"
    /// — `DemographicProfile.eraStyle` does the override-vs-derived
    /// resolution.
    ///
    /// Per-PROFILE preference (long-lived), contrasted with
    /// `WeeklyPlanOverride` (PR 7), which is per-WEEK and lives on
    /// `PlanStore.recentPlanOverrides`. Era affinity is a stable trait of
    /// how the user thinks about training, so it belongs here.
    var eraOverride: String? = nil
    /// SENSITIVE. Body height in whole centimetres. Stored metric; rendered in the
    /// user's preferred unit system (see `usesImperial`). Nil = skipped.
    var heightCm: Int? = nil
    /// SENSITIVE. Body weight in kilograms with one-decimal precision. Stored metric;
    /// rendered per `usesImperial`. Nil = skipped. Mirrors the most recent
    /// entry in `bodyWeightLog` when the log is non-empty — every existing
    /// consumer (strength ratios, generator) keeps reading this single
    /// scalar.
    var weightKg: Double? = nil
    /// SENSITIVE. Append-only body-weight time series (build 103). The most recent entry
    /// is mirrored onto `weightKg` so existing reads keep working. Empty for
    /// installs that haven't logged a weight; the Profile + Progress UI
    /// surfaces an empty state until the first entry lands.
    var bodyWeightLog: [BodyWeightEntry] = []
    /// SENSITIVE. Append-only body-composition time series (build 103). Separate from
    /// `bodyWeightLog` because BF% + lean mass are reported by a different
    /// instrument cadence (monthly DEXA, weekly InBody) than a daily home
    /// scale weight. The planner doesn't read this yet — surfaces are
    /// Profile + Progress for now.
    var bodyCompositionLog: [BodyCompositionEntry] = []
    /// Display preference for height + weight. Defaults true (US default);
    /// users elsewhere can flip on the Profile screen.
    var usesImperial: Bool = true

    // Free-text guardrails
    var dislikes: [String] = []
    /// Per-exercise affinity score, keyed by exercise name. Positive = the user
    /// asked to see this exercise more often; negative = less often. The
    /// post-workout action sheet's "Recommend more / less" rows bump this via
    /// `MemoryStore.bumpAffinity`. The planner is free to ignore the value
    /// until a future ranking pass consumes it — the capture side just needs
    /// somewhere durable to land.
    var exerciseAffinities: [String: Int] = [:]
    /// Per-exercise count of how many times the user has swapped AWAY from this
    /// exercise (keyed by name). Internal accumulator for the swap-memory
    /// feature: every Nth swap-away (`MemoryStore.swapAwayDemoteThreshold`) drops
    /// the exercise's `exerciseAffinities` score by one. Nothing else reads the
    /// raw counts — the demotion they produce in `exerciseAffinities` is the
    /// durable signal the generator consumes.
    var swapAwayCounts: [String: Int] = [:]
    /// Legacy + free-text injury notes ("bad ankle", or pre-build-87 saves that
    /// wrote injury slugs into this list). New structured injuries live in
    /// `userInjuries`; this stays as a fall-through for the keyword-filter path.
    var constraints: [String] = []
    /// Structured per-injury record. Build 87 — replaces the slug-only
    /// `constraints[]` storage for known coach.db injuries. Optional severity /
    /// side / onsetDate flow into the CoachContext snapshot and let the model
    /// reason about laterality and acute-vs-chronic. Plain slug entries (no
    /// extra metadata) migrate over on first decode; legacy slugs left in
    /// constraints[] still feed the contraindication filter via fallback.
    var userInjuries: [UserInjury] = []

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
        case seasonsBySport, supportPattern, defaultSeason, peakDate
        case season                               // legacy (build 20-23) — read for migration
        case availableDays, fixedSportDays        // legacy (build 20-24) — read but dropped on encode
        case phaseStartedAt
        case sessionMinutes, liftDaysPerWeek
        case equipment, experience
        case startingState
        case age, gender
        case eraOverride
        case heightCm, weightKg, usesImperial
        case bodyWeightLog, bodyCompositionLog
        case dislikes, constraints
        case exerciseAffinities, swapAwayCounts
        case userInjuries
        case feedback, soreness, weeklyCheckIns
        case coachInsights
        case onboardedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion   = (try? c.decode(Int.self,            forKey: .schemaVersion))   ?? 2
        self.sports          = (try? c.decode([Sport].self,        forKey: .sports))          ?? []
        self.primarySport    =  try? c.decodeIfPresent(Sport.self, forKey: .primarySport)

        // The goal axis (focuses / legacy primaryFocus) is gone — the season
        // engine drives prescription. Old saves still carry those keys; Swift's
        // keyed decoder ignores unknown keys, so they load cleanly with no shim.

        // Season migration: prefer seasonsBySport map + defaultSeason; fall back to legacy
        // single `season` (which becomes both the default and per-primary-sport entry).
        self.seasonsBySport = (try? c.decode([Sport: SeasonPhase].self, forKey: .seasonsBySport)) ?? [:]
        // Pre-primary/support saves never wrote the key → decodeIfPresent nil →
        // single-sport behavior, no migration needed.
        self.supportPattern = (try? c.decodeIfPresent(SupportPattern.self, forKey: .supportPattern)) ?? nil
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
        self.peakDate = try? c.decodeIfPresent(Date.self, forKey: .peakDate)
        self.phaseStartedAt = try? c.decodeIfPresent(Date.self, forKey: .phaseStartedAt)

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
        // Defaulted to nil — pre-Phase-1 saves never wrote the key, so
        // `decodeIfPresent` returns nil and the generator keeps using the
        // derived cohort from `age`.
        self.eraOverride     = (try? c.decodeIfPresent(String.self, forKey: .eraOverride)) ?? nil
        self.heightCm        =  try? c.decodeIfPresent(Int.self,    forKey: .heightCm)
        self.weightKg        =  try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        self.usesImperial    = (try? c.decode(Bool.self,            forKey: .usesImperial)) ?? true
        self.bodyWeightLog   = (try? c.decode([BodyWeightEntry].self, forKey: .bodyWeightLog)) ?? []
        self.bodyCompositionLog = (try? c.decode([BodyCompositionEntry].self, forKey: .bodyCompositionLog)) ?? []
        self.dislikes        = (try? c.decode([String].self,       forKey: .dislikes))        ?? []
        self.constraints     = (try? c.decode([String].self,       forKey: .constraints))     ?? []
        self.exerciseAffinities = (try? c.decode([String: Int].self, forKey: .exerciseAffinities)) ?? [:]
        self.swapAwayCounts  = (try? c.decode([String: Int].self, forKey: .swapAwayCounts)) ?? [:]
        // userInjuries decode + one-shot migration. New saves write the typed
        // list directly. Older saves wrote injury slugs into constraints[]; on
        // first decode any constraints entry whose slug matches a coach.db
        // common_injuries.slug is promoted into a metadata-less UserInjury and
        // pulled out of constraints. Free-text legacy entries stay in
        // constraints[] for the keyword-filter fallback path.
        if let decoded = try? c.decode([UserInjury].self, forKey: .userInjuries) {
            self.userInjuries = decoded
        } else {
            let knownSlugs = Set(CoachDatabase.shared.listInjuries().map(\.slug))
            let migrated = self.constraints.filter { knownSlugs.contains($0) }
            if migrated.isEmpty {
                self.userInjuries = []
            } else {
                self.userInjuries = migrated.map { UserInjury(slug: $0) }
                self.constraints = self.constraints.filter { !knownSlugs.contains($0) }
            }
        }
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
        try c.encode(seasonsBySport,  forKey: .seasonsBySport)
        try c.encodeIfPresent(supportPattern, forKey: .supportPattern)
        try c.encode(defaultSeason,   forKey: .defaultSeason)
        try c.encodeIfPresent(peakDate, forKey: .peakDate)
        try c.encodeIfPresent(phaseStartedAt, forKey: .phaseStartedAt)
        try c.encode(sessionMinutes,  forKey: .sessionMinutes)
        try c.encode(liftDaysPerWeek, forKey: .liftDaysPerWeek)
        try c.encode(equipment,       forKey: .equipment)
        try c.encode(experience,      forKey: .experience)
        try c.encode(startingState,   forKey: .startingState)
        try c.encodeIfPresent(age,    forKey: .age)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(eraOverride, forKey: .eraOverride)
        try c.encodeIfPresent(heightCm, forKey: .heightCm)
        try c.encodeIfPresent(weightKg, forKey: .weightKg)
        try c.encode(usesImperial, forKey: .usesImperial)
        try c.encode(bodyWeightLog, forKey: .bodyWeightLog)
        try c.encode(bodyCompositionLog, forKey: .bodyCompositionLog)
        try c.encode(dislikes,        forKey: .dislikes)
        try c.encode(constraints,     forKey: .constraints)
        try c.encode(exerciseAffinities, forKey: .exerciseAffinities)
        try c.encode(swapAwayCounts,  forKey: .swapAwayCounts)
        try c.encode(userInjuries,    forKey: .userInjuries)
        try c.encode(feedback,        forKey: .feedback)
        try c.encode(soreness,        forKey: .soreness)
        try c.encode(weeklyCheckIns,  forKey: .weeklyCheckIns)
        try c.encode(coachInsights,   forKey: .coachInsights)
        try c.encodeIfPresent(onboardedAt, forKey: .onboardedAt)
    }
}

// MARK: - Convenience accessors

extension TrainingMemory {
    /// Season the planner should use to pick a WeeklyShape. Reads
    /// seasonsBySport[primarySport] first, then falls back to defaultSeason.
    var seasonForPlanner: SeasonPhase {
        if let s = primarySport, let season = seasonsBySport[s] {
            return season
        }
        return defaultSeason
    }

    /// Weeks elapsed since `phaseStartedAt`, rounded to a 1-indexed week
    /// counter (week 1 = first 7 days). When `phaseStartedAt` is nil (the
    /// user hasn't re-picked their phase since the build-103 stamp landed),
    /// we fall back to `onboardedAt` so existing installs still see a
    /// meaningful counter from the moment they updated. Returns nil only
    /// when neither timestamp is available — pre-onboarding state.
    var weeksInCurrentPhase: Int? {
        let start = phaseStartedAt ?? onboardedAt
        guard let start else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: start, to: Date()).day ?? 0
        // 1-indexed: days 0-6 → "Week 1", 7-13 → "Week 2", ...
        return max(1, (days / 7) + 1)
    }

    /// Days until the configured peak date (.eventPrep). Negative when the
    /// peak has passed; nil when no peak is set. The badge uses this to
    /// render "T-21d to peak" instead of just the phase label.
    var daysUntilPeak: Int? {
        guard let peak = peakDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: peak).day
    }
}

// MARK: - Body-weight log ↔ scalar reconciliation (build 103)
//
// `weightKg` is the scalar every consumer reads (strength ratios, generator,
// 1RM math). `bodyWeightLog` is the time series that drives the trend. They
// must not drift, but there are three writers (onboarding/About-You set the
// scalar directly; the log sheet appends; HealthKit imports merge). These
// helpers are the single funnel that keeps the pair consistent so no caller
// can null out a legitimately-set weight or mirror a stale value.

extension TrainingMemory {
    /// Most-recent entry by date. The log isn't kept sorted at rest (callers
    /// append without re-sorting), so resolve the newest explicitly rather
    /// than trusting `.last`.
    var latestBodyWeightEntry: BodyWeightEntry? {
        bodyWeightLog.max { $0.date < $1.date }
    }

    /// Append a logged weight and mirror the scalar to whatever is newest.
    /// Single writer for the append+mirror pair so a back-dated entry can't
    /// clobber a newer scalar.
    mutating func recordBodyWeight(_ kg: Double, on date: Date = Date(), note: String? = nil) {
        bodyWeightLog.append(BodyWeightEntry(date: date, weightKg: kg, note: note))
        weightKg = latestBodyWeightEntry?.weightKg
    }

    /// Re-mirror the scalar to the log's newest entry. Crucially does NOT
    /// null the scalar when the log is empty — a weight set via onboarding /
    /// About You (which never created a log entry) must survive deleting the
    /// last logged entry. Without this guard, deleting your one logged weight
    /// silently wipes the onboarded bodyweight and the strength-ratios card
    /// disappears.
    mutating func remirrorWeightFromLog() {
        if let newest = latestBodyWeightEntry { weightKg = newest.weightKg }
    }

    /// Seed the log from a scalar set outside it (onboarding / About You, or
    /// any pre–build-103 save). Idempotent: no-op once the log has entries or
    /// when there's no scalar. Anchored to `onboardedAt` so a later HealthKit
    /// import with real sample dates compares correctly against it instead of
    /// blindly overwriting it.
    mutating func backfillBodyWeightLogFromScalar() {
        guard bodyWeightLog.isEmpty, let kg = weightKg else { return }
        bodyWeightLog = [BodyWeightEntry(date: onboardedAt ?? Date(), weightKg: kg, note: nil)]
    }

    /// Reconcile after an external scalar edit (About You writes `weightKg`
    /// directly): if the scalar no longer matches the newest log entry, record
    /// a fresh "today" entry so the trend and the scalar agree. Seeds an empty
    /// log first so the very first edit lands as one point rather than a
    /// divergence. `< 0.05 kg` tolerance treats a re-open with no change as a
    /// no-op (the stored value round-trips through one-decimal display).
    mutating func reconcileScalarIntoLog(on date: Date = Date()) {
        guard let kg = weightKg else { return }
        if bodyWeightLog.isEmpty {
            backfillBodyWeightLogFromScalar()
            return
        }
        if let newest = latestBodyWeightEntry, abs(newest.weightKg - kg) < 0.05 { return }
        bodyWeightLog.append(BodyWeightEntry(date: date, weightKg: kg, note: nil))
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
        self = Sport.resolve(slug: try c.decode(String.self))
    }

    /// Resolve a raw slug (LLM- or coach-supplied) to a catalog Sport,
    /// normalizing legacy underscore slugs (build 20-22 wrote these) to the
    /// hyphenated form coach.db uses. Falls back to a synthetic entry with a
    /// prettified name when the slug matches no catalog row — so an
    /// off-catalog sport (e.g. "mountain-biking") still yields a usable Sport.
    static func resolve(slug raw: String) -> Sport {
        let normalized = raw.replacingOccurrences(of: "_", with: "-")
        if let known = catalog.first(where: { $0.slug == normalized }) { return known }
        if let known = catalog.first(where: { $0.slug == raw }) { return known }
        return Sport(slug: normalized, name: raw.replacingOccurrences(of: "_", with: " ")
                                                .replacingOccurrences(of: "-", with: " ")
                                                .capitalized)
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
        Sport(slug: "mountain-biking",        name: "Mountain Biking"),
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
        Sport(slug: "snowboarding",           name: "Snowboarding"),
        Sport(slug: "mountaineering",         name: "Mountaineering"),
        Sport(slug: "hiking-trekking",        name: "Hiking / Trekking"),
        Sport(slug: "thru-hiking",            name: "Thru-Hiking"),
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

    /// Short form for tight chrome (the Today header eyebrow). Identical to
    /// `label` except maintenance, whose full "Year-round / maintenance"
    /// overflows the eyebrow row next to the date.
    var compactLabel: String {
        switch self {
        case .maintenance: return "Maintenance"
        default:           return label
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

    // MARK: - coach.db equipment.slug mapping
    //
    // The DB stores required equipment per exercise in `exercise_equipment`
    // joined to `equipment.slug`. This onboarding enum is coarser — one
    // selection unlocks a SET of DB slugs. The planner + generator filter
    // candidates by checking that every required slug for an exercise lies
    // inside the user's union allow-list.
    //
    // The "always available" set (bodyweight + chair/wall/table) is added
    // regardless of selection so the floor case stays useful. Picking nothing
    // ≠ no workouts; it means STRICTLY bodyweight floor exercises only.

    /// Slugs anyone has, regardless of what they picked. Furniture-grade
    /// "equipment" sits in coach.db's bodyweight category and gates a real
    /// chunk of the floor / chair-step catalog.
    static let bodyweightAlwaysAvailable: Set<String> = [
        "bodyweight", "chair", "wall", "table"
    ]

    /// Slugs unlocked specifically by THIS selection, ON TOP of the
    /// always-available set. `.bodyweight` strictly adds nothing — picking
    /// "bodyweight only" in onboarding means no pull-up bar, no bench, no
    /// rings. Users who own those pick the corresponding Equipment case.
    var specificCoachDbSlugs: Set<String> {
        switch self {
        case .bodyweight:   return []
        case .dumbbells:    return ["dumbbells"]
        case .barbell:      return ["barbell", "weight-plates", "squat-rack", "flat-bench"]
        case .kettlebell:   return ["kettlebell"]
        case .bands:        return ["band-light", "band-medium", "band-heavy", "mini-band", "suspension-trainer"]
        case .pullUpBar:    return ["pull-up-bar", "dip-station", "gymnastic-rings", "parallettes"]
        case .cableMachine: return ["cable-machine", "cable-crossover", "lat-pulldown"]
        case .bench:        return ["flat-bench", "adjustable-bench"]
        case .yogaMat:      return ["yoga-mat", "foam-pad", "yoga-block", "yoga-wheel", "stretch-strap"]
        case .plyoBox:      return ["plyo-box"]
        case .medicineBall: return ["medicine-ball", "slam-ball"]
        case .weightVest:   return ["weight-vest"]
        case .sandbag:      return ["sandbag"]
        case .fullGym:      return []  // handled by allowedCoachDbSlugs
        }
    }

    /// Union allow-list for a user's selection. `.fullGym` → empty set, which
    /// the SQL filter treats as "no equipment restriction." Otherwise the
    /// always-available floor is unioned with each picked equipment's
    /// specific slugs.
    static func allowedCoachDbSlugs(_ selection: Set<Equipment>) -> Set<String> {
        if selection.contains(.fullGym) { return [] }
        var result = bodyweightAlwaysAvailable
        for eq in selection { result.formUnion(eq.specificCoachDbSlugs) }
        return result
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

// MARK: - Structured injuries

/// One per active injury the user has selected from coach.db's curated list.
/// Slug is the FK to `common_injuries.slug`; the remaining fields are optional
/// metadata that the coach reads but the planner doesn't bind to (today's
/// filter still keys off slug only). Adding severity/side/onset later doesn't
/// change which exercises get excluded — it just lets the model speak in terms
/// of "your mild left ACL from 8 weeks ago" instead of `acl-injury`.
struct UserInjury: Codable, Hashable, Identifiable {
    var slug: String
    var severity: InjurySeverity? = nil
    var side: InjurySide? = nil
    var onsetDate: Date? = nil
    var notes: String? = nil
    /// Stable across edits: same slug + side = same identity, so editing
    /// severity in-place doesn't break List diffing.
    var id: String { slug + "|" + (side?.rawValue ?? "_") }
}

enum InjurySeverity: String, Codable, CaseIterable, Identifiable {
    case mild, moderate, severe
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mild:     return "Mild"
        case .moderate: return "Moderate"
        case .severe:   return "Severe"
        }
    }
}

enum InjurySide: String, Codable, CaseIterable, Identifiable {
    case left, right, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .left:  return "Left"
        case .right: return "Right"
        case .both:  return "Both"
        }
    }
    var short: String {
        switch self {
        case .left:  return "L"
        case .right: return "R"
        case .both:  return "Both"
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
