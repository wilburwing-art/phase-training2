// WeeklyPlanOverride.swift — log entry recorded when a user explicitly
// dismisses a PlanValidationIssue from the painted-strip banner.
//
// PR 7 of the weekly-coach roadmap. Lives in PlanStore.recentOverrides
// under the UserDefaults key `pt_plan_overrides`. Three consecutive
// overrides on the same (rule, pattern) within the recent window
// suppress that combination for the user going forward.
//
// Spec: PLAN-weekly-coach.md §4.2 + §11.1.

import Foundation

struct WeeklyPlanOverride: Codable, Identifiable, Hashable {
    var id: UUID
    /// Monday start-of-day of the week this override happened in. Two
    /// overrides for the same (rule, pattern) on the same `weekStart`
    /// only count as one toward the suppression threshold — otherwise
    /// a tap-twice user-error would prematurely silence rules.
    var weekStart: Date
    /// Stable rule key from `PlanValidationIssue.ruleKey`.
    var rule: String
    /// User-specific pattern from `PlanValidationIssue.patternKey`.
    var pattern: String
    var loggedAt: Date

    init(weekStart: Date, rule: String, pattern: String, loggedAt: Date = Date()) {
        self.id = UUID()
        self.weekStart = weekStart
        self.rule = rule
        self.pattern = pattern
        self.loggedAt = loggedAt
    }
}

extension WeeklyPlanOverride {
    /// Combined key for suppression lookups — matches
    /// `PlanValidationIssue.suppressionKey`.
    var suppressionKey: String { "\(rule):\(pattern)" }
}

/// Helpers for the suppression rule: when a given (rule, pattern)
/// has been overridden ≥3 times across ≥3 distinct weekStart values,
/// the rule self-silences for that pattern.
enum PlanOverrideSuppression {
    /// Threshold from spec §4.2: "After 3 consecutive overrides on
    /// same rule+pattern, rule self-suppresses for that user pattern."
    /// "Consecutive" here means "distinct weekStarts where the issue
    /// was raised AND the user dismissed it" — we don't track
    /// not-raised weeks, so the simpler invariant is: ≥3 distinct
    /// `weekStart` values with overrides for the same (rule, pattern).
    static let threshold = 3

    /// Derive the set of suppressed `"rule:pattern"` keys from the
    /// override log. A (rule, pattern) reaches suppression when it
    /// shows up under ≥3 distinct weekStarts. Older entries past 12
    /// weeks aren't pruned by this function — `PlanStore` is expected
    /// to maintain a rolling window separately.
    static func suppressedKeys(from overrides: [WeeklyPlanOverride]) -> Set<String> {
        // Group by suppressionKey → set of distinct weekStart dates
        var weeksByKey: [String: Set<Date>] = [:]
        for o in overrides {
            weeksByKey[o.suppressionKey, default: []].insert(o.weekStart)
        }
        return Set(weeksByKey.compactMap { key, weeks in
            weeks.count >= threshold ? key : nil
        })
    }
}
