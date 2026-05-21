// CoachContext.swift — serialize live app state into a compact text block
// the model reads as part of its system prompt.
//
// Two-block strategy:
//   1. CoachSystemPrompt.cachedHeader — long, static, marked cache_control:
//      ephemeral so prompt-cache hits on every turn after the first.
//   2. CoachContext.snapshot(...)     — short, per-turn, contains today's
//      date, the active tab, plan, recent feedback. Sent fresh each call.

import Foundation

enum CoachContext {
    /// Build the per-turn context block. Caller passes everything explicitly
    /// so this stays a pure function and CoachDrawer can mock it for tests.
    static func snapshot(
        now: Date = Date(),
        activeTab: AppTab,
        memory: TrainingMemory,
        plan: WeekPlan?,
        recentSessions: [SavedSession],
        recentFeedback: [FeedbackEntry],
        recentSoreness: [SorenessEntry],
        // Defaulted so existing callers (insight generation, LLM refinement,
        // tests) keep working without churn. Wire-up exists in CoachDrawer
        // — the surface where the user actually chats and might say
        // "how was my climbing this week?"
        recentSportLogs: [SportLogEntry] = []
    ) -> String {
        var blocks: [String] = []

        blocks.append("Today is \(longDate(now)) (\(weekday(now))).")
        blocks.append("The user is currently viewing the \(activeTab.label) tab.")

        // Profile summary — what the planner reads.
        var profile: [String] = []
        if let sport = memory.primarySport { profile.append("primary sport: \(sport.name)") }
        if !memory.sports.isEmpty {
            let others = memory.sports.filter { $0.id != memory.primarySport?.id }.map(\.name)
            if !others.isEmpty { profile.append("other sports: \(others.joined(separator: ", "))") }
        }
        profile.append("focus: \(memory.primaryFocus.label)")
        // Season is what tells the planner whether to bias toward strength
        // (off-season) or sport time (in-season). Without it the coach was
        // guessing from sport + recent volume.
        profile.append("season: \(seasonSummary(memory: memory))")
        if let peak = memory.peakDate {
            let cal = Calendar.current
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: now),
                                          to: cal.startOfDay(for: peak)).day ?? 0
            if days > 0 {
                profile.append("peak date: \(short(peak)) (in \(days) day\(days == 1 ? "" : "s"))")
            } else if days == 0 {
                profile.append("peak date: \(short(peak)) (today)")
            } else {
                profile.append("peak date: \(short(peak)) (passed \(-days) day\(days == -1 ? "" : "s") ago)")
            }
        }
        profile.append("experience: \(memory.experience.label)")
        // Starting state is a permanent profile fact, not a time-bounded
        // window. Lets the coach reason about expected soreness + load
        // tolerance on a brand-new user vs a continuing lifter.
        profile.append("training state: \(memory.startingState.label.lowercased())")
        profile.append("equipment: \(memory.equipment.map(\.label).joined(separator: ", "))")
        profile.append("target lifts/wk: \(memory.liftDaysPerWeek)")
        // Session length: declared vs actual. If the user's average completed
        // session diverges meaningfully (≥15%) from declared, flag both so the
        // coach can budget realistic workouts instead of trusting the
        // declared number that gets blown through every time.
        let avgActual = averageRecentDurationMinutes(sessions: recentSessions)
        if let avg = avgActual,
           abs(Double(avg) - Double(memory.sessionMinutes)) / Double(max(memory.sessionMinutes, 1)) >= 0.15 {
            profile.append("session length: \(memory.sessionMinutes) min declared · avg actual \(avg) min")
        } else {
            profile.append("session length: \(memory.sessionMinutes) min")
        }
        blocks.append("USER PROFILE\n" + profile.map { "- \($0)" }.joined(separator: "\n"))

        if let body = bodySection(memory: memory) {
            blocks.append(body)
        }
        if let strength = strengthSection(memory: memory, sessions: recentSessions) {
            blocks.append(strength)
        }
        if let balance = muscleBalanceSection(sessions: recentSessions, now: now) {
            blocks.append(balance)
        }
        if let patterns = patternFrequencySection(sessions: recentSessions, now: now) {
            blocks.append(patterns)
        }

        if !memory.dislikes.isEmpty {
            blocks.append("DISLIKES\n" + memory.dislikes.map { "- \($0)" }.joined(separator: "\n"))
        }
        let demoProfile = DemographicProfile.from(memory)
        if let block = structuredInjuriesSection(memory: memory, now: now) {
            blocks.append(block)
        }
        if let block = injuryFiltersSection(profile: demoProfile, memory: memory) {
            blocks.append(block)
        }
        if let block = prehabCandidatesSection(profile: demoProfile, memory: memory) {
            blocks.append(block)
        }
        // Legacy free-text constraints (anything in memory.constraints that
        // doesn't match a coach.db injury slug). Kept as a separate block so
        // the model still sees user-typed notes like "bad ankle" without us
        // dumping the structured slugs back in alongside the rich rendering
        // above.
        let knownSlugs = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        let legacyConstraints = memory.constraints.filter { !knownSlugs.contains($0) }
        if !legacyConstraints.isEmpty {
            blocks.append("CONSTRAINTS (free-text)\n" + legacyConstraints.map { "- \($0)" }.joined(separator: "\n"))
        }

        // Current plan
        if let plan {
            let today = plan.today(now: now)
            var planLines: [String] = []
            planLines.append("range: \(plan.rangeLabel)")
            // Resolved once and reused — keeps the prehab annotation cheap
            // when expanding exercises across every day in the week.
            let injuryNamesBySlug = injuryNameLookup()

            // Render the exercises in a day's GeneratedWorkout as indented
            // bullets. Used for today AND for the other days in the week so
            // the coach can describe Tuesday's Push or Wednesday's Pull, not
            // just today's session. propose_workout_changes still only
            // operates on today (the cached system prompt enforces that) —
            // visibility just isn't restricted to today anymore.
            func appendExercises(_ workout: GeneratedWorkout) {
                for ex in workout.exercises {
                    var line = "  • \(ex.name) — \(ex.sets) × \(ex.reps)"
                    if let rpe = ex.rpe { line += " @RPE \(rpe)" }
                    if case .prehab(let slug) = ex.source {
                        let label = injuryNamesBySlug[slug] ?? slug
                        line += " (prehab for \(label))"
                    }
                    planLines.append(line)
                }
            }

            if let t = today {
                var hero = "today (\(weekday(t.date))): \(t.kind.label) — \(t.title)"
                if t.protected { hero += " [protected]" }
                if let mins = t.durationMinutes { hero += " · \(mins) min" }
                planLines.append(hero)
                if let workout = t.generatedWorkout {
                    appendExercises(workout)
                }
            }
            for day in plan.days where !Calendar.current.isDate(day.date, inSameDayAs: now) {
                let prefix = day.protected ? "[protected] " : ""
                planLines.append("- \(weekday(day.date)) \(short(day.date)): \(prefix)\(day.kind.label) — \(day.title)")
                if let workout = day.generatedWorkout {
                    appendExercises(workout)
                }
            }
            blocks.append("CURRENT WEEK PLAN\n" + planLines.joined(separator: "\n"))
        } else {
            blocks.append("CURRENT WEEK PLAN\n(no plan generated yet — user hasn't completed onboarding or hasn't generated one)")
        }

        // Recent sessions (last 5). Header shows days since the most recent
        // completed session so the coach can reason about layoffs without
        // having to do date math on the listed dates.
        let sessions = recentSessions.suffix(5).reversed()
        if !sessions.isEmpty {
            let mostRecent = recentSessions.max(by: { $0.startTime < $1.startTime })
            let daysSince = mostRecent.map {
                max(0, Calendar.current.dateComponents([.day], from: $0.startTime, to: now).day ?? 0)
            }
            let header: String
            if let days = daysSince {
                header = "RECENT SESSIONS (days since last: \(days))"
            } else {
                header = "RECENT SESSIONS"
            }
            var lines: [String] = []
            for s in sessions {
                let done = s.exercises.flatMap(\.sets).filter(\.done).count
                let feel = s.feel.map { " · felt: \($0.lowercased())" } ?? ""
                lines.append("- \(short(s.startTime)) · \(s.name) · \(done) sets · \(s.duration / 60) min\(feel)")
            }
            blocks.append("\(header)\n" + lines.joined(separator: "\n"))
        }

        // Recent sport logs (last 5). Mirrors RECENT SESSIONS so the coach
        // has visible context for non-lift load — when the user says "I
        // climbed 90 min Tuesday" the next conversation turn shouldn't need
        // them to repeat it. Sorted ascending in; reverse for display so
        // the most-recent entry is first (matches RECENT SESSIONS).
        let sportLogs = recentSportLogs
            .sorted { $0.date < $1.date }
            .suffix(5)
            .reversed()
        if !sportLogs.isEmpty {
            var lines: [String] = []
            for log in sportLogs {
                var line = "- \(short(log.date)) · \(log.sport.name) · \(log.durationMinutes) min · \(log.intensity.label.lowercased())"
                if let note = log.note, !note.isEmpty {
                    line += " · note: \(note)"
                }
                lines.append(line)
            }
            blocks.append("RECENT SPORT LOGS\n" + lines.joined(separator: "\n"))
        }

        if let familiarity = familiaritySection(sessions: recentSessions, now: now) {
            blocks.append(familiarity)
        }

        // Recent feedback (last 5)
        let feedback = recentFeedback.suffix(5).reversed()
        if !feedback.isEmpty {
            var lines: [String] = []
            for f in feedback {
                var parts: [String] = ["\(short(f.date))"]
                if let d = f.difficulty { parts.append("felt \(d.replacingOccurrences(of: "_", with: " "))") }
                if f.ranLong { parts.append("ran long") }
                if !f.hurtAreas.isEmpty { parts.append("hurt: \(f.hurtAreas.joined(separator: ", "))") }
                if let n = f.notes, !n.isEmpty { parts.append("note: \(n)") }
                lines.append("- " + parts.joined(separator: " · "))
            }
            blocks.append("RECENT POST-WORKOUT FEEDBACK\n" + lines.joined(separator: "\n"))
        }

        // Today's pre-workout check-in (if any)
        if let today = recentSoreness.last,
           Calendar.current.isDate(today.date, inSameDayAs: now) {
            var parts: [String] = []
            if let e = today.energy { parts.append("energy: \(e)") }
            if let s = today.soreness { parts.append("soreness: \(s)") }
            if today.pain { parts.append("pain: yes") }
            if !today.areas.isEmpty { parts.append("areas: \(today.areas.joined(separator: ", "))") }
            if let t = today.timeBudget { parts.append("time: \(t) min") }
            if today.equipmentChanged { parts.append("equipment changed: yes") }
            if !parts.isEmpty {
                blocks.append("TODAY'S PRE-WORKOUT CHECK-IN\n- " + parts.joined(separator: ", "))
            }
        }

        if let trend = recoveryTrendSection(soreness: recentSoreness, now: now) {
            blocks.append(trend)
        }

        return blocks.joined(separator: "\n\n")
    }

    // MARK: - Season summary
    //
    // Render the per-sport season map + the default, collapsing to a single
    // value when everyone is on the same phase. The coach needs both the
    // primary season (planner uses this) AND the off-primary sport seasons
    // (planner ignores them today, but the LLM can still reason about
    // "in-season skiing on Sundays means lighter Saturday lifts").
    static func seasonSummary(memory: TrainingMemory) -> String {
        // No sports — single default season is the whole signal.
        if memory.sports.isEmpty {
            return memory.defaultSeason.label.lowercased()
        }
        let phases = memory.sports.map { sport -> (Sport, SeasonPhase) in
            (sport, memory.seasonsBySport[sport] ?? memory.defaultSeason)
        }
        // All sports in the same phase → render once.
        let distinct = Set(phases.map(\.1))
        if distinct.count == 1, let only = distinct.first {
            return only.label.lowercased()
        }
        // Mixed — show each sport's phase explicitly + default fallback.
        let pieces = phases.map { "\($0.0.name.lowercased()) \($0.1.label.lowercased())" }
        return pieces.joined(separator: ", ") + " (otherwise: \(memory.defaultSeason.label.lowercased()))"
    }

    // MARK: - Injury sections (build 87)
    //
    // Three blocks replace the slug-only CONSTRAINTS dump:
    //   STRUCTURED INJURIES   — human-readable name + region + severity + side
    //                           + onset + coach.db description / mechanism.
    //   INJURY FILTERS        — names of the exercises the planner is
    //                           subtracting per injury (top 5 + remainder).
    //   PREHAB CANDIDATES     — names of the prehab / rehab_late exercises
    //                           the planner would prefer for each injury.
    //
    // Without these, the coach saw `- patellar-tendinopathy` and had to know
    // by training what that slug meant; it also couldn't say "I dropped Back
    // Squat because of your ACL" because the exclusion happened silently at
    // the SQL boundary.

    /// Cache slug → display name once per snapshot. CoachDatabase joins SQL
    /// per call, so calling listInjuries() in a tight loop is wasteful.
    static func injuryNameLookup() -> [String: String] {
        var out: [String: String] = [:]
        for inj in CoachDatabase.shared.listInjuries() {
            out[inj.slug] = inj.name
        }
        return out
    }

    /// Cache slug → full CommonInjury (for region + description + recovery).
    private static func injuryByLookup() -> [String: CommonInjury] {
        var out: [String: CommonInjury] = [:]
        for inj in CoachDatabase.shared.listInjuries() {
            out[inj.slug] = inj
        }
        return out
    }

    static func structuredInjuriesSection(memory: TrainingMemory, now: Date = Date()) -> String? {
        guard !memory.userInjuries.isEmpty else { return nil }
        let byLookup = injuryByLookup()
        let cal = Calendar.current
        var lines: [String] = []
        for inj in memory.userInjuries.sorted(by: { $0.slug < $1.slug }) {
            guard let common = byLookup[inj.slug] else { continue }
            var qualifiers: [String] = []
            if let region = common.bodyRegion, !region.isEmpty {
                qualifiers.append(region)
            }
            if let sev = inj.severity { qualifiers.append(sev.rawValue) }
            if let side = inj.side    { qualifiers.append(side.label.lowercased()) }
            if let onset = inj.onsetDate {
                let weeks = cal.dateComponents([.weekOfYear],
                                               from: cal.startOfDay(for: onset),
                                               to: cal.startOfDay(for: now)).weekOfYear ?? 0
                if weeks <= 0 {
                    qualifiers.append("onset this week")
                } else if weeks == 1 {
                    qualifiers.append("onset 1 week ago")
                } else {
                    qualifiers.append("onset \(weeks) weeks ago")
                }
            }
            let qualifierBlob = qualifiers.isEmpty ? "" : " (" + qualifiers.joined(separator: " · ") + ")"
            var line = "- \(common.name)\(qualifierBlob)"
            // Description + recovery time give the model a clinical anchor.
            // Both trimmed of trailing punctuation so we can compose cleanly.
            var detail: [String] = []
            if let desc = common.description, !desc.isEmpty {
                detail.append(desc.trimmingCharacters(in: CharacterSet(charactersIn: " .")))
            }
            // The listInjuries() projection doesn't include mechanism /
            // typical_recovery — they're columns on the table but not read by
            // CoachDatabase. Skipped here; can be promoted later if useful.
            if let notes = inj.notes, !notes.isEmpty {
                detail.append("user note: \(notes)")
            }
            if !detail.isEmpty {
                line += ". " + detail.joined(separator: ". ") + "."
            }
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        return "STRUCTURED INJURIES\n" + lines.joined(separator: "\n")
    }

    static func injuryFiltersSection(profile: DemographicProfile, memory: TrainingMemory) -> String? {
        guard !profile.excludedByInjury.isEmpty else { return nil }
        let names = injuryNameLookup()
        let db = CoachDatabase.shared
        var lines: [String] = []
        for entry in profile.excludedByInjury {
            let display = names[entry.slug] ?? entry.slug
            // Top 5 names, alphabetised; remainder rolled into "+N more".
            let sortedIds = Array(entry.exerciseIds)
            let resolved = sortedIds.compactMap { db.exercise(id: $0)?.name }
                .sorted()
            guard !resolved.isEmpty else { continue }
            let head = resolved.prefix(5).joined(separator: ", ")
            let rest = resolved.count - 5
            let trail = rest > 0 ? " (+ \(rest) more)" : ""
            lines.append("- \(display): \(head)\(trail)")
        }
        guard !lines.isEmpty else { return nil }
        return "INJURY FILTERS — exercises currently excluded\n" + lines.joined(separator: "\n")
    }

    static func prehabCandidatesSection(profile: DemographicProfile, memory: TrainingMemory) -> String? {
        guard !profile.prehabSuggestions.isEmpty else { return nil }
        let names = injuryNameLookup()
        var lines: [String] = []
        for entry in profile.prehabSuggestions {
            guard !entry.exercises.isEmpty else { continue }
            let display = names[entry.slug] ?? entry.slug
            let exNames = entry.exercises.map(\.name).joined(separator: ", ")
            lines.append("- \(display): \(exNames)")
        }
        guard !lines.isEmpty else { return nil }
        return "PREHAB CANDIDATES — coach.db-tagged for the user's injuries\n" + lines.joined(separator: "\n")
    }

    // MARK: - Section builders (build 62: richer profile signal for the coach)

    /// Height / weight / gender / age block. Returns nil when none are set
    /// — keeps the snapshot tight for users who skipped the optional fields.
    /// Age was missing from the coach's view until build 65 even though the
    /// generator already used it — without age the coach would program the
    /// same workout for a 28- and 58-year-old.
    static func bodySection(memory: TrainingMemory) -> String? {
        var lines: [String] = []
        if let cm = memory.heightCm {
            lines.append("- height: \(BodyMetrics.formatHeight(cm: cm, imperial: memory.usesImperial))")
        }
        if let kg = memory.weightKg {
            lines.append("- weight: \(BodyMetrics.formatWeight(kg: kg, imperial: memory.usesImperial))")
        }
        if let g = memory.gender {
            lines.append("- gender: \(g.label.lowercased())")
        }
        if let age = memory.age {
            lines.append("- age: \(age)")
        }
        if lines.isEmpty { return nil }
        return "BODY\n" + lines.joined(separator: "\n")
    }

    /// Strength-ratio snapshot for canonical lifts (Bench/Squat/Deadlift/OHP/
    /// Pull-Up). Emits one line per lift with the user's est. 1RM × bodyweight
    /// ratio and a tier label when gender is set. Hidden when bodyweight is
    /// missing — the ratio is undefined without it.
    ///
    /// Build 65 adds VELOCITY — each row compares the user's best est-1RM in
    /// the LAST 4 weeks against the best from the 4 weeks before that. The
    /// coach now sees "+12 lb / 4w" (progressing) vs "≈" (plateaued) vs
    /// "-8 lb / 4w" (regressed). Drives the obvious "deload / change rep
    /// scheme" decisions without the LLM having to date-math over sessions.
    static func strengthSection(memory: TrainingMemory, sessions: [SavedSession], now: Date = Date()) -> String? {
        guard memory.weightKg != nil else { return nil }
        let rows = StrengthStandards.rows(
            from: sessions,
            bodyweightKg: memory.weightKg,
            gender: memory.gender
        )
        guard !rows.isEmpty else { return nil }
        let unitLabel = memory.usesImperial ? "lb" : "kg"
        // Split sessions into "current 4w" vs "prior 4w" for velocity.
        let cal = Calendar.current
        let recentCutoff = cal.date(byAdding: .weekOfYear, value: -4, to: now) ?? now
        let priorCutoff = cal.date(byAdding: .weekOfYear, value: -8, to: now) ?? now
        let recentWindow = sessions.filter { $0.startTime >= recentCutoff }
        let priorWindow = sessions.filter { $0.startTime >= priorCutoff && $0.startTime < recentCutoff }

        let recentBest = StrengthStandards.rows(from: recentWindow,
                                                bodyweightKg: memory.weightKg,
                                                gender: memory.gender)
        let priorBest = StrengthStandards.rows(from: priorWindow,
                                               bodyweightKg: memory.weightKg,
                                               gender: memory.gender)
        let recentBestById = Dictionary(uniqueKeysWithValues: recentBest.map { ($0.id, $0.oneRepMaxLb) })
        let priorBestById = Dictionary(uniqueKeysWithValues: priorBest.map { ($0.id, $0.oneRepMaxLb) })

        let lines = rows.map { row -> String in
            let oneRm: Int
            if memory.usesImperial {
                oneRm = Int(row.oneRepMaxLb.rounded())
            } else {
                oneRm = Int(BodyMetrics.lbToKg(row.oneRepMaxLb).rounded())
            }
            let ratio = String(format: "%.2f", row.ratio)
            let tier = row.tier.map { " · \($0.label.lowercased())" } ?? ""
            // Velocity: only when we have BOTH windows of data for this lift.
            var velocity = ""
            if let recent = recentBestById[row.id], let prior = priorBestById[row.id] {
                let deltaLb = recent - prior
                let deltaDisplay = memory.usesImperial
                    ? Int(deltaLb.rounded())
                    : Int(BodyMetrics.lbToKg(deltaLb).rounded())
                // ≈ when the change is below the smallest plate increment
                // (5 lb). Below the noise floor it's noise, not signal.
                if abs(deltaLb) < 5 {
                    velocity = " · ≈ /4w"
                } else if deltaLb > 0 {
                    velocity = " · +\(deltaDisplay) /4w"
                } else {
                    velocity = " · \(deltaDisplay) /4w"  // negative number formats with the minus
                }
            }
            return "- \(row.lift.label): est 1RM \(oneRm) \(unitLabel) · \(ratio)× BW\(tier)\(velocity)"
        }
        var section = "STRENGTH (est 1RM × bodyweight)\n" + lines.joined(separator: "\n")
        if memory.gender == nil {
            section += "\n(gender not set — no tier labels)"
        }
        return section
    }

    // MARK: - New build-65 sections

    /// Movement-pattern frequency over the last 4 weeks. Counts how many
    /// distinct training days hit each pattern (squat, hip-hinge, etc.) and
    /// flags any CANONICAL lifting pattern with zero hits so the coach can
    /// prioritise it on the next workout. Returns nil if no sessions in the
    /// window have any resolvable patterns.
    static func patternFrequencySection(sessions: [SavedSession],
                                        weeks: Int = 4,
                                        now: Date = Date()) -> String? {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .weekOfYear, value: -weeks, to: now) ?? now
        let recent = sessions.filter { $0.startTime >= cutoff }
        guard !recent.isEmpty else { return nil }

        // Memoise name → pattern slugs across the call.
        var resolved: [String: [String]] = [:]
        let db = CoachDatabase.shared

        // For each session, gather the unique pattern slugs it contains,
        // then increment per-pattern session counts. Sessions, not sets —
        // hitting "squat" 4 times in one day is still one session for this
        // signal.
        var byPattern: [String: Int] = [:]
        for session in recent {
            var sessionPatterns: Set<String> = []
            for ex in session.exercises {
                if let cached = resolved[ex.name] {
                    sessionPatterns.formUnion(cached)
                    continue
                }
                let exact = db.listExercises(search: ex.name)
                    .first { $0.name.caseInsensitiveCompare(ex.name) == .orderedSame }
                let patterns = exact.map { db.patternsForExercise($0.id) } ?? []
                resolved[ex.name] = patterns
                sessionPatterns.formUnion(patterns)
            }
            for p in sessionPatterns { byPattern[p, default: 0] += 1 }
        }

        if byPattern.isEmpty { return nil }

        // Top patterns by count, plus a "missing" list of canonical patterns
        // not seen. The canonical set is the same one the WorkoutGenerator's
        // recipes anchor on.
        let canonical: [String] = [
            "squat", "hip-hinge",
            "horizontal-push", "vertical-push",
            "horizontal-pull", "vertical-pull",
        ]
        let top = byPattern.sorted { $0.value > $1.value }.prefix(8)
        let plural = recent.count == 1 ? "session" : "sessions"
        var lines = top.map { (slug, count) in
            "- \(formatPattern(slug)): \(count) \(count == 1 ? "session" : "sessions")"
        }
        let missing = canonical.filter { byPattern[$0] == nil }
        if !missing.isEmpty {
            lines.append("- missing (no training in last \(weeks)w): \(missing.map(formatPattern).joined(separator: ", "))")
        }
        return "PATTERN FREQUENCY — last \(weeks)w across \(recent.count) \(plural)\n" + lines.joined(separator: "\n")
    }

    /// Soreness / energy rollup over the last 7 days. Surfaces recurring
    /// hurt areas (a knee mentioned 3 days running is a different signal
    /// than one off mention) and aggregate energy/pain reports.
    static func recoveryTrendSection(soreness: [SorenessEntry], now: Date = Date()) -> String? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let recent = soreness.filter { $0.date >= cutoff }
        guard recent.count >= 2 else { return nil }   // single entry already shown as "today's check-in"

        // energy + soreness are bucket strings ("low"/"normal"/"high",
        // "none"/"mild"/"high"). Roll them up as bucket histograms.
        var areaCounts: [String: Int] = [:]
        var energyBuckets: [String: Int] = [:]
        var sorenessBuckets: [String: Int] = [:]
        var painDays = 0
        for entry in recent {
            if entry.pain { painDays += 1 }
            for area in entry.areas { areaCounts[area, default: 0] += 1 }
            if let e = entry.energy { energyBuckets[e, default: 0] += 1 }
            if let s = entry.soreness { sorenessBuckets[s, default: 0] += 1 }
        }
        var lines: [String] = []
        lines.append("- days reporting: \(recent.count) of 7")
        if !energyBuckets.isEmpty {
            lines.append("- energy: " + histogramSummary(energyBuckets))
        }
        if !sorenessBuckets.isEmpty {
            lines.append("- soreness: " + histogramSummary(sorenessBuckets))
        }
        if painDays > 0 {
            lines.append("- pain days: \(painDays)")
        }
        // Areas mentioned 2+ times look like recurrence — flag them.
        let recurring = areaCounts.filter { $0.value >= 2 }.sorted { $0.value > $1.value }
        if !recurring.isEmpty {
            let rendered = recurring.map { "\($0.key) (\($0.value)x)" }.joined(separator: ", ")
            lines.append("- recurring hurt areas: \(rendered)")
        }
        return "RECOVERY TREND — last 7d\n" + lines.joined(separator: "\n")
    }

    /// Average actual session length (minutes) over the user's last 8
    /// completed sessions, or nil when fewer than 3 sessions exist (small
    /// samples flapping aren't useful signal).
    static func averageRecentDurationMinutes(sessions: [SavedSession]) -> Int? {
        let recent = sessions.sorted { $0.startTime > $1.startTime }.prefix(8)
        guard recent.count >= 3 else { return nil }
        let totalSec = recent.reduce(0) { $0 + $1.duration }
        return Int(Double(totalSec) / Double(recent.count) / 60.0)
    }

    /// "horizontal-push" → "Horizontal push". Cheap display formatting.
    private static func formatPattern(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// "{normal: 4, high: 2, low: 1}" → "normal (4), high (2), low (1)".
    /// Most-common bucket first so the coach reads the modal answer up top.
    private static func histogramSummary(_ counts: [String: Int]) -> String {
        counts.sorted { $0.value > $1.value }
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
    }

    /// Muscle-balance snapshot over the last 4 weeks. Surfaces the top 5
    /// muscle groups by allocated volume + flags any group whose volume is
    /// < 1/3 the top group's (a coarse imbalance signal the coach can act on).
    /// Returns nil when there's no resolvable session volume.
    static func muscleBalanceSection(sessions: [SavedSession], now: Date) -> String? {
        let rows = MuscleVolume.rows(from: sessions, weeks: 4, limit: 5, now: now)
        guard !rows.isEmpty else { return nil }
        let top = rows[0].volume
        guard top > 0 else { return nil }
        var lines: [String] = []
        for row in rows {
            let pct = Int((row.volume / top * 100).rounded())
            var line = "- \(row.label): \(Int(row.volume.rounded())) (\(pct)% of top)"
            if row.volume * 3 < top {
                line += " · underdone"
            }
            lines.append(line)
        }
        return "MUSCLE BALANCE — last 4w (weight × reps, role-allocated)\n" + lines.joined(separator: "\n")
    }

    /// Top exercises the user has actually trained recently. Different signal
    /// than strength — strength only covers the canonical 5 lifts. This
    /// includes everything (accessories, isolations, mobility) so the coach
    /// can speak to what's familiar. Returns nil if the user has < 3 unique
    /// completed exercises in the window.
    static func familiaritySection(sessions: [SavedSession], now: Date, days: Int = 90, limit: Int = 10) -> String? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        struct Stat { var setCount: Int = 0; var sessionDates: Set<DateComponents> = [] }
        var stats: [String: Stat] = [:]
        let cal = Calendar.current
        for session in sessions where session.startTime >= cutoff {
            let day = cal.dateComponents([.year, .month, .day], from: session.startTime)
            for ex in session.exercises {
                let done = ex.sets.filter(\.done).count
                guard done > 0 else { continue }
                var s = stats[ex.name] ?? Stat()
                s.setCount += done
                s.sessionDates.insert(day)
                stats[ex.name] = s
            }
        }
        guard stats.count >= 3 else { return nil }
        let top = stats
            .map { (name: $0.key, sets: $0.value.setCount, sessions: $0.value.sessionDates.count) }
            .sorted { $0.sets > $1.sets }
            .prefix(limit)
        let lines = top.map { row -> String in
            let plural = row.sessions == 1 ? "session" : "sessions"
            return "- \(row.name): \(row.sets) sets across \(row.sessions) \(plural)"
        }
        return "EXERCISE FAMILIARITY — last \(days)d\n" + lines.joined(separator: "\n")
    }

    // MARK: - Date helpers

    private static func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: d)
    }

    private static func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    private static func short(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

extension AppTab {
    var label: String {
        switch self {
        case .today:    return "Today"
        case .week:     return "Week"
        case .library:  return "Library"
        case .progress: return "Progress"
        case .profile:  return "Profile"
        }
    }
}
