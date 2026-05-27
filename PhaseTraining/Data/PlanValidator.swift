// PlanValidator.swift — synchronous rules engine for weekly plan
// validation. PR 7 of the weekly-coach roadmap.
//
// Pure Swift, no UI. Runs deterministically on the device — not the LLM.
// The LLM is asynchronous + capped; rules engine is the safety net that
// makes the painted-strip customization (PR 6) usable without users
// shooting themselves in the foot.
//
// Rules catalog (PLAN-weekly-coach.md §4.1):
//   1. stacked-hard-days        warn   ≥3 lift/sport back-to-back, no rest
//   2. volume-drift             info   lift count diverges from
//                                      memory.liftDaysPerWeek by ≥2
//   3. pattern-imbalance        info   Push/Pull ratio off by ≥2
//   4. recovery-debt            warn   hard sport immediately after a lift
//   5. time-budget              warn   declared weekly minutes > 7h
//   6. single-pattern-overload  info   same focus 3+ times in one week
//
// Skip-streak suppression (the 7th rule) is silent planner-input
// behavior, not a user-facing issue — it lives in PR 10.
//
// Suppression: callers pass a `suppressedRulePatterns` set keyed by
// "<ruleKey>:<patternKey>". When the user dismisses the same issue three
// weeks in a row, PlanStore folds the pattern into this set and the
// rule self-suppresses for that user.

import Foundation

// MARK: - ValidationSeverity

enum ValidationSeverity: String, Codable, Hashable, CaseIterable {
    case info, warn, strong

    /// SF Symbol shown in the banner.
    var icon: String {
        switch self {
        case .info:   return "info.circle"
        case .warn:   return "exclamationmark.triangle"
        case .strong: return "exclamationmark.octagon"
        }
    }
}

// MARK: - PlanValidationIssue

/// One concrete validation flag against a WeekPlan. Tied back to a
/// stable (rule, pattern) key pair so suppression can target it
/// across weeks — `id` is per-invocation and not persisted.
struct PlanValidationIssue: Identifiable, Hashable {
    let id: UUID
    /// Stable rule identifier ("stacked-hard-days", "volume-drift", etc.).
    /// Used to look up suppression state + log overrides.
    let ruleKey: String
    /// Per-user pattern this issue captures. e.g. for stacked-hard-days
    /// the pattern is the weekday triple ("mon-tue-wed"); for
    /// single-pattern-overload the pattern is the focus ("push"). Two
    /// issues with the same (rule, pattern) on different weeks count
    /// toward the same suppression bucket.
    let patternKey: String
    let severity: ValidationSeverity
    let title: String
    let explanation: String
    /// Days the issue points at — UI can highlight matching rows.
    let relevantDates: [Date]

    init(ruleKey: String, patternKey: String, severity: ValidationSeverity,
         title: String, explanation: String, relevantDates: [Date]) {
        self.id = UUID()
        self.ruleKey = ruleKey
        self.patternKey = patternKey
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.relevantDates = relevantDates
    }

    /// Stable identity for suppression: a rule + pattern uniquely
    /// identifies a "kind of issue" across weeks.
    var suppressionKey: String { "\(ruleKey):\(patternKey)" }
}

// MARK: - PlanValidator

enum PlanValidator {

    /// Walk every rule against the plan + memory state, collect issues,
    /// filter suppressed (rule, pattern) buckets, and return the visible
    /// issues sorted by severity (strong → warn → info).
    static func validate(
        plan: WeekPlan,
        memory: TrainingMemory,
        overrides: WeekOverrides,
        suppressedRulePatterns: Set<String> = []
    ) -> [PlanValidationIssue] {
        var raw: [PlanValidationIssue] = []
        raw.append(contentsOf: stackedHardDays(plan: plan))
        raw.append(contentsOf: volumeDrift(plan: plan, memory: memory))
        raw.append(contentsOf: patternImbalance(plan: plan, overrides: overrides))
        raw.append(contentsOf: recoveryDebt(plan: plan, overrides: overrides))
        raw.append(contentsOf: timeBudgetReality(plan: plan, memory: memory, overrides: overrides))
        raw.append(contentsOf: singlePatternOverload(plan: plan, overrides: overrides))

        let filtered = raw.filter { !suppressedRulePatterns.contains($0.suppressionKey) }
        return filtered.sorted { ranking(of: $0.severity) > ranking(of: $1.severity) }
    }

    private static func ranking(of s: ValidationSeverity) -> Int {
        switch s {
        case .strong: return 3
        case .warn:   return 2
        case .info:   return 1
        }
    }

    // MARK: - Rule: stacked hard days

    /// "Hard day" = .lift or .sport. Any run of ≥3 consecutive hard days
    /// without a rest/event break warns. Pattern key is the weekday
    /// triple that triggered it ("mon-tue-wed") so dismissing one
    /// stretch doesn't silence a different one later in the season.
    static func stackedHardDays(plan: WeekPlan) -> [PlanValidationIssue] {
        var issues: [PlanValidationIssue] = []
        var run: [DayPlan] = []
        for day in plan.days {
            if day.kind == .lift || day.kind == .sport {
                run.append(day)
            } else {
                if run.count >= 3 {
                    issues.append(makeStackedIssue(run: run))
                }
                run = []
            }
        }
        if run.count >= 3 { issues.append(makeStackedIssue(run: run)) }
        return issues
    }

    private static func makeStackedIssue(run: [DayPlan]) -> PlanValidationIssue {
        let weekdays = run.map { weekdayShort(of: $0.date).lowercased() }
        let patternKey = weekdays.joined(separator: "-")
        let title = "\(run.count) hard days in a row"
        let explanation = "You've got \(weekdays.joined(separator: " → ")) booked as " +
            "lift or sport days with no rest between them. Most lifters need at " +
            "least one easy day after two hard ones — recovery starts breaking " +
            "down past that. Move one of the middle days to a mobility flow or rest."
        return PlanValidationIssue(
            ruleKey: "stacked-hard-days",
            patternKey: patternKey,
            severity: .warn,
            title: title,
            explanation: explanation,
            relevantDates: run.map(\.date)
        )
    }

    // MARK: - Rule: volume drift

    static func volumeDrift(plan: WeekPlan, memory: TrainingMemory) -> [PlanValidationIssue] {
        let planned = plan.days.filter { $0.kind == .lift }.count
        let declared = memory.liftDaysPerWeek
        let diff = planned - declared
        guard abs(diff) >= 2 else { return [] }
        let title: String
        let body: String
        if diff > 0 {
            title = "Lifting \(planned) days — declared \(declared)"
            body = "Your profile says you want to lift \(declared) times a week, but this week schedules \(planned). That's a \(diff)-day jump. If you're consciously pushing, mark the week as a Build tone; if not, drop a lift to keep volume on track."
        } else {
            title = "Lifting \(planned) days — usually \(declared)"
            body = "Your profile says \(declared) lift days but this week only schedules \(planned). If you're recovering or busy, mark the week tone so the coach reads the signal. Otherwise add a lift day back."
        }
        return [PlanValidationIssue(
            ruleKey: "volume-drift",
            patternKey: "diff-\(diff)",
            severity: .info,
            title: title,
            explanation: body,
            relevantDates: plan.days.filter { $0.kind == .lift }.map(\.date)
        )]
    }

    // MARK: - Rule: pattern imbalance

    /// Push vs Pull ratio off by ≥2 in either direction. Reads focus
    /// from the override map first, falls back to inferring from the
    /// generated workout's title (which mirrors WorkoutFocus.title).
    static func patternImbalance(plan: WeekPlan, overrides: WeekOverrides) -> [PlanValidationIssue] {
        var pushCount = 0
        var pullCount = 0
        var relevant: [Date] = []
        for day in plan.days where day.kind == .lift {
            let focus = resolveFocus(for: day, overrides: overrides)
            switch focus {
            case .push:
                pushCount += 1
                relevant.append(day.date)
            case .pull:
                pullCount += 1
                relevant.append(day.date)
            default:
                break
            }
        }
        let diff = pushCount - pullCount
        guard abs(diff) >= 2 else { return [] }
        let title: String
        let body: String
        if diff > 0 {
            title = "Push-heavy week (\(pushCount) push vs \(pullCount) pull)"
            body = "You've got \(pushCount) push days and \(pullCount) pull days. " +
                "Posterior chain matters for shoulder health and balanced strength — " +
                "swap one of the push days to pull, or pick Full body to even it out."
        } else {
            title = "Pull-heavy week (\(pullCount) pull vs \(pushCount) push)"
            body = "You've got \(pullCount) pull days and \(pushCount) push. Add a " +
                "push day or swap one pull to full body if you want symmetry."
        }
        return [PlanValidationIssue(
            ruleKey: "pattern-imbalance",
            patternKey: diff > 0 ? "push-heavy" : "pull-heavy",
            severity: .info,
            title: title,
            explanation: body,
            relevantDates: relevant
        )]
    }

    // MARK: - Rule: recovery debt

    /// Hard sport day landing immediately after a lift day. Sport
    /// intensity is sourced from the event; lift days are treated as
    /// "hard" by default (we don't currently track per-lift intensity).
    static func recoveryDebt(plan: WeekPlan, overrides: WeekOverrides) -> [PlanValidationIssue] {
        var issues: [PlanValidationIssue] = []
        let days = plan.days
        for i in 1..<days.count {
            let prev = days[i - 1]
            let next = days[i]
            guard prev.kind == .lift, next.kind == .sport else { continue }
            // Is the sport day flagged as hard via WeekEvent intensity?
            let sportEvents = overrides.events(on: next.date)
            let isHard = sportEvents.contains { $0.intensity == .hard }
            guard isHard else { continue }
            let patternKey = "\(weekdayShort(of: prev.date).lowercased())-then-\(weekdayShort(of: next.date).lowercased())"
            issues.append(PlanValidationIssue(
                ruleKey: "recovery-debt",
                patternKey: patternKey,
                severity: .warn,
                title: "Hard sport right after a lift",
                explanation: "\(weekdayShort(of: prev.date)) is a lift day and \(weekdayShort(of: next.date)) is a hard \(next.sport?.name ?? "sport") session. Stacking two hard days in a row eats into recovery — consider moving the lift earlier in the week or marking the sport day lighter.",
                relevantDates: [prev.date, next.date]
            ))
        }
        return issues
    }

    // MARK: - Rule: time budget reality

    /// Sum the declared per-day workout minutes (lifts × sessionMinutes,
    /// plus sport days at intensity-derived defaults) and warn when the
    /// total breaches 7h. The 7h threshold matches what most coaches use
    /// as the upper bound for sustainable weekly training time outside
    /// of competitive prep.
    static let weeklyMinuteBudget = 7 * 60   // 7 hours

    static func timeBudgetReality(
        plan: WeekPlan,
        memory: TrainingMemory,
        overrides: WeekOverrides
    ) -> [PlanValidationIssue] {
        var totalMinutes = 0
        var workoutDates: [Date] = []
        for day in plan.days {
            switch day.kind {
            case .lift:
                totalMinutes += memory.sessionMinutes
                workoutDates.append(day.date)
            case .sport:
                let event = overrides.events(on: day.date).first
                let mins: Int = {
                    switch event?.intensity {
                    case .light:    return 45
                    case .moderate: return 75
                    case .hard:     return 105
                    case .none:     return 60
                    }
                }()
                totalMinutes += mins
                workoutDates.append(day.date)
            case .rest, .event:
                break
            }
        }
        guard totalMinutes > weeklyMinuteBudget else { return [] }
        let hours = Double(totalMinutes) / 60.0
        return [PlanValidationIssue(
            ruleKey: "time-budget",
            patternKey: "over-\(weeklyMinuteBudget / 60)h",
            severity: .warn,
            title: String(format: "%.1fh of training this week", hours),
            explanation: "That's beyond what most lifters can sustain week after week. If you're prepping for a specific event, ignore this; otherwise drop a session or shorten the lifts (set the week tone to Busy to auto-compress).",
            relevantDates: workoutDates
        )]
    }

    // MARK: - Rule: single-pattern overload

    /// Same lift focus appearing 3+ times in a week. Reads focus
    /// from override first, falls back to title inference.
    static func singlePatternOverload(plan: WeekPlan, overrides: WeekOverrides) -> [PlanValidationIssue] {
        var counts: [LiftFocus: [Date]] = [:]
        for day in plan.days where day.kind == .lift {
            guard let focus = resolveFocus(for: day, overrides: overrides) else { continue }
            counts[focus, default: []].append(day.date)
        }
        var issues: [PlanValidationIssue] = []
        for (focus, dates) in counts where dates.count >= 3 {
            let title = "\(dates.count) \(focus.label.lowercased()) days this week"
            let body = "Hitting \(focus.label.lowercased()) \(dates.count) times in a week is a lot — " +
                "joint and tendon load on that pattern won't have time to settle. Unless " +
                "you're consciously specializing, swap one or two to a different focus."
            issues.append(PlanValidationIssue(
                ruleKey: "single-pattern-overload",
                patternKey: focus.rawValue,
                severity: .info,
                title: title,
                explanation: body,
                relevantDates: dates
            ))
        }
        return issues
    }

    // MARK: - Focus resolution

    /// Pull the day's LiftFocus from (a) an explicit override on that
    /// date, then (b) the generated workout's title — the workout
    /// title was generated from `WorkoutFocus.title` so it's a
    /// reliable signal for what the planner picked.
    static func resolveFocus(for day: DayPlan, overrides: WeekOverrides) -> LiftFocus? {
        if let override = overrides.override(on: day.date), let focus = override.liftFocus {
            return focus
        }
        guard let title = day.generatedWorkout?.title else { return nil }
        let lower = title.lowercased()
        if lower.contains("push")        { return .push }
        if lower.contains("pull")        { return .pull }
        if lower.contains("leg")         { return .legs }
        if lower.contains("upper")       { return .upper }
        if lower.contains("lower body") || lower == "lower" { return .lower }
        if lower.contains("full body")   { return .fullBody }
        return nil
    }

    // MARK: - Helpers

    private static func weekdayShort(of date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
