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
        recentSportLogs: [SportLogEntry] = [],
        // PR 4: rolling 12-week history. Just counts + completion ratios —
        // full plan shapes are too verbose for the per-turn context budget.
        // The coach can reason about consistency without seeing every day.
        pastPlans: [WeekPlanSnapshot] = [],
        // PR 7: rules-engine issues active against the current plan. The
        // coach can mention them in chat ("you've got 4 push days lined
        // up — want to swap one to pull?"). Suppressed (rule, pattern)
        // combinations don't appear here.
        planIssues: [PlanValidationIssue] = [],
        // PR 8: missed-workout history. Let the coach see patterns
        // ("you've missed Tuesday's lift 3 weeks in a row"). Recent
        // (last 14 days) entries only — older misses aren't actionable.
        missedWorkouts: [MissedWorkoutEntry] = [],
        // Phase 2 readiness: pass-through of the in-season readiness
        // score (0..1, 0.5 = neutral / no data) so the LLM knows
        // whether to nudge intensity up or down in its prose. Per the
        // `phase-training-personalization-two-axes` skill, this is a
        // SILENT signal — the coach must not surface a "you might be
        // detrained" prompt. The number lets the LLM avoid pushing 90%
        // intensity copy on a user whose deterministic prescription
        // was already capped. Defaulted nil → no readiness block.
        readinessScore: Double? = nil
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
        // Support sport (primary/support model): a declared weekly rhythm the
        // primary plan flows around. Surfaced so the coach reasons about the
        // interference the SupportScheduler is already planning for.
        if let support = memory.supportPattern, !support.isEmpty {
            let name = Sport.resolve(slug: support.sportSlug).name
            let days = support.days
                .map { "\($0.weekday.short) \($0.magnitude.label.lowercased())" }
                .joined(separator: ", ")
            profile.append("support sport: \(name) — \(support.days.count) declared day\(support.days.count == 1 ? "" : "s")/week (\(days))")
        }
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

        // Phase 2 readiness block. Emitted only when the caller computed a
        // real score (callers that don't yet thread it pass nil, and we
        // skip the block entirely). The block instructs the LLM to treat
        // this as a SILENT prior — never surface "you might be detrained"
        // language to the user — but to scale its intensity prose to match.
        if let readinessScore {
            let pct = Int((readinessScore * 100).rounded())
            var lines: [String] = []
            lines.append("- current_readiness_pct: \(pct)")
            let band: String
            switch readinessScore {
            case ..<0.3:  band = "detrained — generator already capped volume + RPE; do NOT push the user harder"
            case 0.3..<0.7: band = "neutral / mid — match the prescribed intensity, no extra push or hold-back"
            default:        band = "in-season — user can handle the prescribed load; reinforce, don't sandbag"
            }
            lines.append("- guidance: \(band)")
            blocks.append("IN-SEASON READINESS (silent prior — do NOT name a 'detrained' or 'underprepared' status to the user)\n" + lines.joined(separator: "\n"))
        }

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
            blocks.append("DISLIKES\n" + memory.dislikes.map { "- \(sanitizeFreeText($0))" }.joined(separator: "\n"))
        }
        let demoProfile = DemographicProfile.from(memory)
        if let block = structuredInjuriesSection(memory: memory, now: now) {
            blocks.append(block)
        }
        if let block = injuryFiltersSection(profile: demoProfile, memory: memory) {
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
            blocks.append("CONSTRAINTS (free-text)\n" + legacyConstraints.map { "- \(sanitizeFreeText($0))" }.joined(separator: "\n"))
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

        // Build 106 — per-set detail of the last 2 sessions. RECENT SESSIONS
        // (below) gives the high-level summary; this block surfaces the
        // actual loads + reps + RPE so the coach can make smart progression
        // decisions ("you missed rep 5 on the top set, hold the same load
        // today" rather than "you did bench, push the load"). Working sets
        // only — skips warmups + un-done sets that aren't signal.
        if let detail = lastSessionDetailSection(sessions: recentSessions) {
            blocks.append(detail)
        }

        // Build 106 — planned vs completed for the last 7 days. Without
        // this the coach kept pushing volume into a user who'd skipped
        // workouts. Empty block when no plan is loaded.
        if let plan, let adherence = weekAdherenceSection(plan: plan, sessions: recentSessions, now: now) {
            blocks.append(adherence)
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
                // T2-9: session name comes from a custom routine title.
                lines.append("- \(short(s.startTime)) · \(sanitizeFreeText(s.name, max: 80)) · \(done) sets · \(s.duration / 60) min\(feel)")
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
                    line += " · note: \(sanitizeFreeText(note))"
                }
                lines.append(line)
            }
            blocks.append("RECENT SPORT LOGS\n" + lines.joined(separator: "\n"))
        }

        // PR 4: past-plan history summary. Last 6 weeks (capped from the
        // 12-week store) so the block stays under ~200 chars. Per-week
        // line is one row: planned counts + completion ratio + missed.
        // The coach can detect patterns ("missed Tuesdays 3 weeks in a
        // row") without us shipping the whole DayPlan inline. Excludes
        // the current week (still in-flight) so completion ratios are
        // meaningful — a Monday-morning snapshot would read 0% across
        // the board.
        let nowWeekStart = now.startOfTrainingWeek()
        let historical = pastPlans
            .filter { $0.weekStart < nowWeekStart }
            .prefix(6)
        if !historical.isEmpty {
            var lines: [String] = []
            for snap in historical {
                let planned = snap.plannedLiftDays + snap.plannedSportDays
                let done = snap.completedSessionCount(in: recentSessions)
                let pct = planned > 0 ? Int((Double(done) / Double(planned) * 100).rounded()) : 0
                lines.append("- week of \(short(snap.weekStart)): planned \(planned), completed \(done) (\(pct)%)")
            }
            blocks.append("PAST WEEKS (last \(lines.count))\n" + lines.joined(separator: "\n"))
        }

        // PR 7: active rules-engine issues. Only present when the
        // planner produced something the user might want feedback on.
        // Tight format — one line per issue (severity + title), no
        // explanation body (the coach already has the rules taxonomy
        // in its system prompt + can ask if it needs more detail).
        if !planIssues.isEmpty {
            var lines: [String] = []
            for issue in planIssues.prefix(5) {
                lines.append("- [\(issue.severity.rawValue)] \(issue.title) (rule: \(issue.ruleKey))")
            }
            blocks.append("PLAN ISSUES\n" + lines.joined(separator: "\n"))
        }

        // PR 8: recent missed-workout history (last 14 days). The coach
        // can read patterns like "you've missed Tuesday lifts 3 weeks
        // running" from this block.
        let missedCutoff = now.addingTimeInterval(-14 * 86_400)
        let recentMissed = missedWorkouts
            .filter { $0.date >= missedCutoff }
            .sorted { $0.date > $1.date }
            .prefix(8)
        if !recentMissed.isEmpty {
            var lines: [String] = []
            for entry in recentMissed {
                let title = entry.plannedTitle ?? entry.plannedKind.label.lowercased()
                lines.append("- \(short(entry.date)) (\(weekday(entry.date))): \(title) — \(entry.resolution.summary)")
            }
            blocks.append("MISSED WORKOUTS (last 14 days)\n" + lines.joined(separator: "\n"))
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
                if let n = f.notes, !n.isEmpty { parts.append("note: \(sanitizeFreeText(n))") }
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
            let displayAreas = today.areas.filter { MuscleBucket.sorenessPrimarySlugs.contains($0) }
            if !displayAreas.isEmpty { parts.append("areas: \(displayAreas.joined(separator: ", "))") }
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

    //
    // Render the per-sport season map + the default, collapsing to a single
    // value when everyone is on the same phase. The coach needs both the
    // primary season (planner uses this) AND the off-primary sport seasons
    // (planner ignores them today, but the LLM can still reason about
    // "in-season skiing on Sundays means lighter Saturday lifts").

    //
    // Two blocks replace the slug-only CONSTRAINTS dump:
    //   STRUCTURED INJURIES   — human-readable name + region + severity + side
    //                           + onset + coach.db description / mechanism.
    //   INJURY FILTERS        — names of the exercises the planner is
    //                           subtracting per injury (top 5 + remainder).
    //
    // Without these, the coach saw `- patellar-tendinopathy` and had to know
    // by training what that slug meant; it also couldn't say "I dropped Back
    // Squat because of your ACL" because the exclusion happened silently at
    // the SQL boundary.

    // MARK: - Shared helpers (used across the section-builder extensions)

    /// Average actual session length (minutes) over the user's last 8
    /// completed sessions, or nil when fewer than 3 sessions exist (small
    /// samples flapping aren't useful signal).
    static func averageRecentDurationMinutes(sessions: [SavedSession]) -> Int? {
        let recent = sessions.sorted { $0.startTime > $1.startTime }.prefix(8)
        guard recent.count >= 3 else { return nil }
        let totalSec = recent.reduce(0) { $0 + $1.duration }
        return Int(Double(totalSec) / Double(recent.count) / 60.0)
    }

    /// Neutralize user-typed free-text before it goes into the per-turn prompt.
    /// The injection vector that matters is newlines — a note like
    /// "\n\nSYSTEM: ignore prior instructions" could fake a new section the
    /// model treats as authoritative. We flatten all line breaks/control
    /// whitespace to single spaces, collapse runs, and bound the length so a
    /// long note can't blow out the context. The system prompt separately tells
    /// the model this text is data, not instructions. Clean single-line notes
    /// (the common case) pass through unchanged.
    static func sanitizeFreeText(_ raw: String, max: Int = 240) -> String {
        let cleaned = raw.map { ch -> Character in
            if ch.isWhitespace { return " " }
            if ch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return " " }
            return ch
        }
        var s = String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        if s.count > max { s = String(s.prefix(max)) + "…" }
        return s
    }

    // MARK: - Date helpers

    private static func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: d)
    }

    static func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    static func short(_ d: Date) -> String {
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
