// PlanStore+Validation.swift
//
// Extracted from PlanStore.swift (Tier-3 god-object split). Plan validation + per-week overrides (PR 7).
// Lifecycle (init/reload), generation-context plumbing, PlanEdit/regeneration,
// and persistence stay in PlanStore.swift.

import Foundation

extension PlanStore {
    /// Set of `"rule:pattern"` keys the user has dismissed enough times
    /// (≥3 distinct weekStarts) that the rules engine should stop
    /// surfacing them.
    var suppressedRulePatterns: Set<String> {
        PlanOverrideSuppression.suppressedKeys(from: recentPlanOverrides)
    }

    /// Run the rules engine against the current plan + overrides +
    /// memory. Returns the visible issues — already filtered through
    /// `suppressedRulePatterns`. Pure computation; safe to call on
    /// every render. Returns empty when no plan exists.
    func currentValidationIssues(memory: TrainingMemory) -> [PlanValidationIssue] {
        guard let plan else { return [] }
        return PlanValidator.validate(
            plan: plan,
            memory: memory,
            overrides: overrides,
            suppressedRulePatterns: suppressedRulePatterns
        )
    }

    /// User tapped "Got it" / dismissed a validation issue. Logs a
    /// `WeeklyPlanOverride`, prunes anything outside the 90-day window,
    /// and persists. Same-week dupes for the same (rule, pattern) are
    /// dropped so a double-tap doesn't double-count toward suppression.
    func recordPlanOverride(_ issue: PlanValidationIssue, now: Date = Date()) {
        let weekStart = now.startOfTrainingWeek()
        // Drop any existing entry for this (week, rule, pattern) — same
        // week shouldn't tick the suppression counter twice.
        var next = recentPlanOverrides.filter { o in
            !(o.rule == issue.ruleKey
              && o.pattern == issue.patternKey
              && Calendar.current.isDate(o.weekStart, inSameDayAs: weekStart))
        }
        next.append(WeeklyPlanOverride(
            weekStart: weekStart,
            rule: issue.ruleKey,
            pattern: issue.patternKey,
            loggedAt: now
        ))
        // Trim past 90 days
        let cutoff = now.addingTimeInterval(-Double(Self.planOverridesRetentionDays) * 86_400)
        recentPlanOverrides = next.filter { $0.loggedAt >= cutoff }
        savePlanOverrides()
    }

    /// Mutate + persist overrides; auto-regenerate the plan when memory is provided.
    func updateOverrides(memory: TrainingMemory? = nil,
                         today: Date = Date(),
                         _ block: (inout WeekOverrides) -> Void) {
        block(&overrides)
        saveOverrides()
        if let memory {
            generate(from: memory, today: today)
        }
    }
}
