// PlanStoreValidationOverrideTests.swift — PR 7 of the weekly-coach
// roadmap. Covers the PlanStore-level glue between PlanValidator,
// WeeklyPlanOverride logging, and suppression.

import XCTest
@testable import PhaseTraining

final class PlanStoreValidationOverrideTests: XCTestCase {

    private func freshStore() -> PlanStore {
        let suite = "plan-validation-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PlanStore(defaults: defaults)
    }

    private func issue(rule: String = "stacked-hard-days",
                       pattern: String = "mon-tue-wed",
                       severity: ValidationSeverity = .warn) -> PlanValidationIssue {
        PlanValidationIssue(
            ruleKey: rule, patternKey: pattern, severity: severity,
            title: "x", explanation: "y", relevantDates: []
        )
    }

    func test_recordOverride_logsAnEntry() {
        let store = freshStore()
        XCTAssertTrue(store.recentPlanOverrides.isEmpty)
        store.recordPlanOverride(issue())
        XCTAssertEqual(store.recentPlanOverrides.count, 1)
        XCTAssertEqual(store.recentPlanOverrides[0].rule, "stacked-hard-days")
    }

    func test_recordOverride_idempotentWithinWeek() {
        // Two acks on the same (rule, pattern) within the same week
        // should NOT double-count — the spec says distinct weeks count.
        let store = freshStore()
        store.recordPlanOverride(issue())
        store.recordPlanOverride(issue())
        XCTAssertEqual(store.recentPlanOverrides.count, 1,
                       "second ack in the same week should replace the first, not append")
    }

    func test_recordOverride_acrossThreeWeeksTriggersSuppression() {
        let store = freshStore()
        let cal = Calendar.current
        let now = Date()
        for i in 0..<3 {
            let date = cal.date(byAdding: .day, value: -7 * i, to: now)!
            store.recordPlanOverride(issue(), now: date)
        }
        XCTAssertTrue(store.suppressedRulePatterns.contains("stacked-hard-days:mon-tue-wed"))
    }

    func test_currentValidationIssues_returnsEmptyWhenNoPlan() {
        let store = freshStore()
        var m = TrainingMemory(); m.equipment = [.fullGym]
        XCTAssertTrue(store.currentValidationIssues(memory: m).isEmpty)
    }

    func test_clearWipesOverrides() {
        let store = freshStore()
        store.recordPlanOverride(issue())
        XCTAssertEqual(store.recentPlanOverrides.count, 1)
        store.clear()
        XCTAssertEqual(store.recentPlanOverrides.count, 0)
    }

    func test_overridesPersistAcrossInstances() {
        let suite = "plan-validation-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        do {
            let store = PlanStore(defaults: defaults)
            store.recordPlanOverride(issue())
            XCTAssertEqual(store.recentPlanOverrides.count, 1)
        }
        let reopened = PlanStore(defaults: defaults)
        XCTAssertEqual(reopened.recentPlanOverrides.count, 1,
                       "override log should survive a fresh PlanStore init")
    }
}
