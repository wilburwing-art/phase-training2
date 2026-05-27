// PlanValidatorTests.swift — PR 7 of the weekly-coach roadmap.
//
// Pure-logic coverage for each rule in `PlanValidator` + the suppression
// helper. The rules engine is the safety net for painted-strip
// customization; these tests pin its behavior so a refactor doesn't
// silently weaken a guardrail.

import XCTest
@testable import PhaseTraining

final class PlanValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func memory(liftDaysPerWeek: Int = 3, sessionMinutes: Int = 60) -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = liftDaysPerWeek
        m.sessionMinutes = sessionMinutes
        return m
    }

    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        return Calendar.current.date(from: c)!
    }

    private func plan(_ kinds: [DayKind], focusTitle: [String?]? = nil) -> WeekPlan {
        precondition(kinds.count == 7)
        let cal = Calendar.current
        let start = monday()
        let days = (0..<7).map { i -> DayPlan in
            let kind = kinds[i]
            let title: String
            if kind == .lift, let titles = focusTitle, let custom = titles[i] {
                title = custom
            } else {
                title = kind == .lift ? "Push day" :
                        kind == .sport ? "Climbing" :
                        kind == .rest ? "Rest" : "Event"
            }
            var workout: GeneratedWorkout? = nil
            if kind == .lift {
                workout = GeneratedWorkout(
                    title: title, summary: "", exercises: [],
                    estimatedMinutes: 60, provenance: ""
                )
            }
            return DayPlan(
                date: cal.date(byAdding: .day, value: i, to: start) ?? start,
                kind: kind, title: title, routineId: nil,
                generatedWorkout: workout
            )
        }
        return WeekPlan(days: days, generatedAt: Date(), inputsHash: "test")
    }

    // MARK: - Stacked hard days

    func test_stackedHardDays_firesOnThreeInARow() {
        // Mon Tue Wed all lift, rest of week light
        let p = plan([.lift, .lift, .lift, .rest, .rest, .rest, .rest])
        let issues = PlanValidator.stackedHardDays(plan: p)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].ruleKey, "stacked-hard-days")
        XCTAssertEqual(issues[0].severity, .warn)
        XCTAssertEqual(issues[0].relevantDates.count, 3)
    }

    func test_stackedHardDays_silentBelowThree() {
        // Two in a row should NOT fire
        let p = plan([.lift, .lift, .rest, .lift, .rest, .rest, .rest])
        XCTAssertEqual(PlanValidator.stackedHardDays(plan: p).count, 0)
    }

    func test_stackedHardDays_mixesLiftAndSport() {
        // Lift+Sport+Lift back to back should count as hard
        let p = plan([.lift, .sport, .lift, .rest, .rest, .rest, .rest])
        XCTAssertEqual(PlanValidator.stackedHardDays(plan: p).count, 1)
    }

    func test_stackedHardDays_restBreaksTheStreak() {
        // Mon Tue Lift, Wed Rest, Thu Fri Sat Lift — only the Thu-Sat run
        // is ≥3 and triggers
        let p = plan([.lift, .lift, .rest, .lift, .lift, .lift, .rest])
        let issues = PlanValidator.stackedHardDays(plan: p)
        XCTAssertEqual(issues.count, 1, "rest should break the streak")
    }

    // MARK: - Volume drift

    func test_volumeDrift_underTargetByTwo() {
        let p = plan([.lift, .rest, .rest, .rest, .rest, .rest, .rest])  // 1 lift
        let issues = PlanValidator.volumeDrift(plan: p, memory: memory(liftDaysPerWeek: 3))
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].severity, .info)
    }

    func test_volumeDrift_overTargetByTwo() {
        let p = plan([.lift, .lift, .lift, .lift, .lift, .rest, .rest])  // 5 lifts
        let issues = PlanValidator.volumeDrift(plan: p, memory: memory(liftDaysPerWeek: 3))
        XCTAssertEqual(issues.count, 1)
    }

    func test_volumeDrift_silentWithinOne() {
        let p = plan([.lift, .lift, .rest, .lift, .lift, .rest, .rest])  // 4 lifts vs 3 declared
        XCTAssertEqual(
            PlanValidator.volumeDrift(plan: p, memory: memory(liftDaysPerWeek: 3)).count, 0
        )
    }

    // MARK: - Pattern imbalance

    func test_patternImbalance_pushHeavy() {
        // 3 push, 1 pull → diff = 2 → fires
        let p = plan(
            [.lift, .lift, .lift, .lift, .rest, .rest, .rest],
            focusTitle: ["Push day", "Push day", "Push day", "Pull day", nil, nil, nil]
        )
        let issues = PlanValidator.patternImbalance(plan: p, overrides: WeekOverrides(weekStart: monday()))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].title.contains("Push-heavy"))
        XCTAssertEqual(issues[0].severity, .info)
    }

    func test_patternImbalance_silentWhenBalanced() {
        let p = plan(
            [.lift, .lift, .lift, .lift, .rest, .rest, .rest],
            focusTitle: ["Push day", "Pull day", "Push day", "Pull day", nil, nil, nil]
        )
        XCTAssertEqual(
            PlanValidator.patternImbalance(plan: p, overrides: WeekOverrides(weekStart: monday())).count, 0
        )
    }

    func test_patternImbalance_respectsExplicitFocusOverride() {
        // Plan title says "Push" but the dayOverride forces .pull — the
        // override should win when resolving focus.
        let p = plan([.lift, .lift, .lift, .lift, .rest, .rest, .rest],
                     focusTitle: ["Push day", "Push day", "Push day", "Push day", nil, nil, nil])
        var overrides = WeekOverrides(weekStart: monday())
        for i in 0..<2 {
            let date = Calendar.current.date(byAdding: .day, value: i, to: monday())!
            overrides.dayOverrides[date] = .lift(routineId: nil, focus: .pull)
        }
        // After override: 2 pull (Mon/Tue), 2 push (Wed/Thu) → balanced
        let issues = PlanValidator.patternImbalance(plan: p, overrides: overrides)
        XCTAssertEqual(issues.count, 0,
                       "override should reclassify the days so the diff drops below the threshold")
    }

    // MARK: - Recovery debt

    func test_recoveryDebt_firesOnLiftThenHardSport() {
        // Tue lift, Wed sport (hard intensity via event)
        let p = plan([.rest, .lift, .sport, .rest, .rest, .rest, .rest])
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        var overrides = WeekOverrides(weekStart: monday())
        overrides.events = [WeekEvent(date: wed, title: "Climb",
                                      kind: .sportSession, sport: nil,
                                      intensity: .hard)]
        let issues = PlanValidator.recoveryDebt(plan: p, overrides: overrides)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].severity, .warn)
    }

    func test_recoveryDebt_silentWhenSportIsModerate() {
        let p = plan([.rest, .lift, .sport, .rest, .rest, .rest, .rest])
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        var overrides = WeekOverrides(weekStart: monday())
        overrides.events = [WeekEvent(date: wed, title: "Climb",
                                      kind: .sportSession, sport: nil,
                                      intensity: .moderate)]
        XCTAssertEqual(PlanValidator.recoveryDebt(plan: p, overrides: overrides).count, 0)
    }

    // MARK: - Time budget

    func test_timeBudget_firesAbove7Hours() {
        // 5 lift days × 90min + 2 rest = 450min = 7.5h → fires
        let p = plan([.lift, .lift, .lift, .lift, .lift, .rest, .rest])
        let issues = PlanValidator.timeBudgetReality(
            plan: p, memory: memory(sessionMinutes: 90),
            overrides: WeekOverrides(weekStart: monday()))
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].severity, .warn)
    }

    func test_timeBudget_silentBelow7Hours() {
        // 4 lift × 60min = 240min, well under 7h
        let p = plan([.lift, .lift, .lift, .lift, .rest, .rest, .rest])
        let issues = PlanValidator.timeBudgetReality(
            plan: p, memory: memory(sessionMinutes: 60),
            overrides: WeekOverrides(weekStart: monday()))
        XCTAssertEqual(issues.count, 0)
    }

    // MARK: - Single-pattern overload

    func test_singlePatternOverload_threePushDays() {
        let p = plan(
            [.lift, .lift, .lift, .rest, .rest, .rest, .rest],
            focusTitle: ["Push day", "Push day", "Push day", nil, nil, nil, nil]
        )
        let issues = PlanValidator.singlePatternOverload(
            plan: p, overrides: WeekOverrides(weekStart: monday()))
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].patternKey, "push")
    }

    func test_singlePatternOverload_silentWithTwo() {
        let p = plan(
            [.lift, .lift, .rest, .rest, .rest, .rest, .rest],
            focusTitle: ["Push day", "Push day", nil, nil, nil, nil, nil]
        )
        XCTAssertEqual(
            PlanValidator.singlePatternOverload(
                plan: p, overrides: WeekOverrides(weekStart: monday())).count, 0
        )
    }

    // MARK: - Suppression

    func test_suppression_threeWeeksSilencesPattern() {
        let cal = Calendar.current
        let weeks: [Date] = (0..<3).map {
            cal.date(byAdding: .day, value: -7 * $0, to: monday())!.startOfTrainingWeek()
        }
        let overrides = weeks.map { week in
            WeeklyPlanOverride(weekStart: week, rule: "stacked-hard-days",
                               pattern: "mon-tue-wed")
        }
        let suppressed = PlanOverrideSuppression.suppressedKeys(from: overrides)
        XCTAssertTrue(suppressed.contains("stacked-hard-days:mon-tue-wed"))
    }

    func test_suppression_twoWeeksNotEnough() {
        let cal = Calendar.current
        let weeks: [Date] = (0..<2).map {
            cal.date(byAdding: .day, value: -7 * $0, to: monday())!.startOfTrainingWeek()
        }
        let overrides = weeks.map { week in
            WeeklyPlanOverride(weekStart: week, rule: "stacked-hard-days",
                               pattern: "mon-tue-wed")
        }
        XCTAssertTrue(PlanOverrideSuppression.suppressedKeys(from: overrides).isEmpty)
    }

    func test_suppression_threeDupesSameWeekDoesNotCount() {
        let week = monday()
        let overrides = (0..<3).map { _ in
            WeeklyPlanOverride(weekStart: week, rule: "stacked-hard-days",
                               pattern: "mon-tue-wed")
        }
        XCTAssertTrue(PlanOverrideSuppression.suppressedKeys(from: overrides).isEmpty,
                      "three overrides in the SAME week shouldn't trip suppression")
    }

    // MARK: - Validator.validate integration

    func test_validate_filtersSuppressedIssues() {
        // Plan with 3 lift days in a row + a focus overload → 2 issues
        // normally. Suppress one — only the other surfaces.
        let p = plan(
            [.lift, .lift, .lift, .rest, .rest, .rest, .rest],
            focusTitle: ["Push day", "Push day", "Push day", nil, nil, nil, nil]
        )
        let m = memory()
        let raw = PlanValidator.validate(
            plan: p, memory: m, overrides: WeekOverrides(weekStart: monday()))
        XCTAssertGreaterThanOrEqual(raw.count, 2)

        let filtered = PlanValidator.validate(
            plan: p, memory: m, overrides: WeekOverrides(weekStart: monday()),
            suppressedRulePatterns: ["single-pattern-overload:push"])
        XCTAssertFalse(filtered.contains { $0.suppressionKey == "single-pattern-overload:push" })
        XCTAssertTrue(filtered.contains { $0.ruleKey == "stacked-hard-days" })
    }

    func test_validate_sortsBySeverity() {
        // Manufacture both a warn (stacked) and an info (overload).
        // Warn must appear first.
        let p = plan(
            [.lift, .lift, .lift, .rest, .rest, .rest, .rest],
            focusTitle: ["Push day", "Push day", "Push day", nil, nil, nil, nil]
        )
        let issues = PlanValidator.validate(
            plan: p, memory: memory(),
            overrides: WeekOverrides(weekStart: monday()))
        guard issues.count >= 2 else {
            XCTFail("expected ≥2 issues"); return
        }
        // First two should be warn-or-stronger
        XCTAssertGreaterThanOrEqual(severityRank(issues[0].severity),
                                    severityRank(issues[1].severity))
    }

    private func severityRank(_ s: ValidationSeverity) -> Int {
        switch s { case .strong: return 3; case .warn: return 2; case .info: return 1 }
    }
}
