import XCTest
@testable import PhaseTraining

final class DemographicProfileTests: XCTestCase {

    // MARK: - Lift days

    func test_beginner_recommends_2_to_3_lifts() {
        var m = TrainingMemory()
        m.experience = .beginner
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.recommendedLiftDays, 2...3)
    }

    func test_intermediate_recommends_3_to_4_lifts() {
        var m = TrainingMemory()
        m.experience = .intermediate
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.recommendedLiftDays, 3...4)
    }

    func test_advanced_recommends_4_to_5_lifts() {
        var m = TrainingMemory()
        m.experience = .advanced
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.recommendedLiftDays, 4...5)
    }

    func test_age_55plus_caps_upper_lift_bound() {
        var m = TrainingMemory()
        m.experience = .advanced
        m.age = 60
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.recommendedLiftDays.upperBound, 4,
                       "Age 55+ should drop the upper lift-day bound by 1")
    }

    func test_age_under_55_doesnt_change_lifts() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.age = 40
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.recommendedLiftDays, 3...4)
    }

    // MARK: - Session minutes

    func test_session_minutes_scale_with_experience() {
        var m = TrainingMemory()
        m.experience = .beginner
        XCTAssertEqual(DemographicProfile.from(m).recommendedSessionMinutes, 30...45)
        m.experience = .intermediate
        XCTAssertEqual(DemographicProfile.from(m).recommendedSessionMinutes, 45...60)
        m.experience = .advanced
        XCTAssertEqual(DemographicProfile.from(m).recommendedSessionMinutes, 60...90)
    }

    func test_age_55plus_caps_session_at_60() {
        var m = TrainingMemory()
        m.experience = .advanced
        m.age = 70
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.recommendedSessionMinutes.upperBound, 60)
    }

    // MARK: - Recovery

    func test_beginner_needs_one_recovery_day_between_lifts() {
        var m = TrainingMemory()
        m.experience = .beginner
        XCTAssertEqual(DemographicProfile.from(m).minRecoveryDaysBetweenLifts, 1)
    }

    func test_intermediate_advanced_can_stack_lifts() {
        var m = TrainingMemory()
        m.experience = .intermediate
        XCTAssertEqual(DemographicProfile.from(m).minRecoveryDaysBetweenLifts, 0)
        m.experience = .advanced
        XCTAssertEqual(DemographicProfile.from(m).minRecoveryDaysBetweenLifts, 0)
    }

    func test_age_55plus_forces_at_least_one_recovery_day() {
        var m = TrainingMemory()
        m.experience = .advanced
        m.age = 56
        XCTAssertEqual(DemographicProfile.from(m).minRecoveryDaysBetweenLifts, 1)
    }

    // MARK: - Difficulty bias

    func test_beginner_only_gets_beginner_routines() {
        var m = TrainingMemory()
        m.experience = .beginner
        XCTAssertEqual(DemographicProfile.from(m).preferredDifficulties, ["beginner"])
    }

    func test_intermediate_prefers_intermediate_then_beginner() {
        var m = TrainingMemory()
        m.experience = .intermediate
        XCTAssertEqual(DemographicProfile.from(m).preferredDifficulties,
                       ["intermediate", "beginner"])
    }

    func test_advanced_prefers_advanced_then_intermediate() {
        var m = TrainingMemory()
        m.experience = .advanced
        XCTAssertEqual(DemographicProfile.from(m).preferredDifficulties,
                       ["advanced", "intermediate", "beginner"])
    }

    func test_age_60plus_advanced_demotes_to_intermediate_first() {
        var m = TrainingMemory()
        m.experience = .advanced
        m.age = 62
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.preferredDifficulties.first, "intermediate",
                       "Older advanced lifters should default to intermediate complexity")
    }

    // MARK: - Equipment → environment

    func test_full_gym_imposes_no_environment_filter() {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        XCTAssertTrue(DemographicProfile.from(m).allowedEnvironments.isEmpty)
    }

    func test_dumbbells_filters_to_home_anywhere_travel() {
        var m = TrainingMemory()
        m.equipment = [.dumbbells]
        let envs = DemographicProfile.from(m).allowedEnvironments
        XCTAssertEqual(envs, ["home", "anywhere", "travel"])
    }

    func test_bodyweight_includes_outdoor() {
        var m = TrainingMemory()
        m.equipment = [.bodyweight]
        let envs = DemographicProfile.from(m).allowedEnvironments
        XCTAssertTrue(envs.contains("outdoor"))
        XCTAssertFalse(envs.contains("gym"))
    }

    // MARK: - Constraint keyword extraction

    func test_constraint_tokenizes_dropping_side_modifiers() {
        var m = TrainingMemory()
        m.constraints = ["left knee", "the lower back"]
        let kws = DemographicProfile.from(m).excludedNameKeywords
        XCTAssertTrue(kws.contains("knee"))
        XCTAssertTrue(kws.contains("lower"))
        XCTAssertTrue(kws.contains("back"))
        XCTAssertFalse(kws.contains("left"))
        XCTAssertFalse(kws.contains("the"))
    }

    func test_short_tokens_are_dropped() {
        var m = TrainingMemory()
        m.constraints = ["pt for L5"]    // "pt", "for", "L5" all too short / stop
        let kws = DemographicProfile.from(m).excludedNameKeywords
        // Nothing >= 3 chars that isn't a stop word
        XCTAssertTrue(kws.isEmpty || kws.allSatisfy { $0.count >= 3 })
    }

    // MARK: - Structured injury contraindications (coach.db-backed)

    func test_knownInjurySlug_populatesExcludedExerciseIds() {
        var m = TrainingMemory()
        m.constraints = ["patellar-tendinopathy"]
        let p = DemographicProfile.from(m)
        XCTAssertFalse(p.excludedExerciseIds.isEmpty,
                       "Known injury slug should pull contraindicated exercise ids from coach.db")
        // And it should NOT have been mistaken for free-text keywords.
        XCTAssertFalse(p.excludedNameKeywords.contains("patellar"),
                       "Known slug should be consumed structurally, not tokenized")
    }

    func test_freeTextConstraint_stillProducesKeywordExclusions() {
        var m = TrainingMemory()
        m.constraints = ["bad ankle"]   // not a known slug
        let p = DemographicProfile.from(m)
        XCTAssertTrue(p.excludedNameKeywords.contains("ankle"))
        XCTAssertTrue(p.excludedExerciseIds.isEmpty,
                      "Free-text constraint shouldn't trigger structural contraindications")
    }

    func test_mixedConstraints_handleBoth() {
        var m = TrainingMemory()
        m.constraints = ["acl-injury", "weird custom thing"]
        let p = DemographicProfile.from(m)
        XCTAssertFalse(p.excludedExerciseIds.isEmpty,
                       "Structural pickup from acl-injury slug")
        XCTAssertTrue(p.excludedNameKeywords.contains("weird")
                      || p.excludedNameKeywords.contains("custom")
                      || p.excludedNameKeywords.contains("thing"),
                      "Free-text should still tokenize")
    }

    // MARK: - Rationale always non-empty

    func test_rationale_always_explains_at_least_lift_and_session_choice() {
        let p = DemographicProfile.from(TrainingMemory())
        XCTAssertFalse(p.rationale.isEmpty)
    }

    // MARK: - Structured userInjuries (build 87)

    func test_userInjuries_populateExcludedByInjury_perSlug() {
        var m = TrainingMemory()
        m.userInjuries = [UserInjury(slug: "acl-injury")]
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.excludedByInjury.count, 1)
        XCTAssertEqual(p.excludedByInjury.first?.slug, "acl-injury")
        XCTAssertFalse(p.excludedByInjury.first?.exerciseIds.isEmpty ?? true,
                       "ACL injury should have coach.db-tagged contraindicated exercises")
        XCTAssertEqual(p.excludedByInjury.first?.exerciseIds, p.excludedExerciseIds,
                       "Single-injury union should match the per-slug set")
    }

    func test_userInjuries_populatePrehabSuggestions() {
        var m = TrainingMemory()
        m.userInjuries = [UserInjury(slug: "patellar-tendinopathy")]
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.prehabSuggestions.count, 1,
                       "Exactly one prehab bucket for one structured injury")
        XCTAssertEqual(p.prehabSuggestions.first?.slug, "patellar-tendinopathy")
        XCTAssertLessThanOrEqual(p.prehabSuggestions.first?.exercises.count ?? 0, 3,
                                 "Capped at 3 prehab exercises per injury")
    }

    func test_legacySlugInConstraints_stillBackfillsExcludedByInjury() {
        // Pre-87 saves wrote slugs into constraints[]. DemographicProfile must
        // pick them up via the straggler path even if migration didn't run.
        var m = TrainingMemory()
        m.constraints = ["acl-injury"]
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.excludedByInjury.first?.slug, "acl-injury",
                       "Straggler slug in constraints[] should still populate the per-slug map")
    }

    func test_noInjuries_emitsEmptyBuckets() {
        let p = DemographicProfile.from(TrainingMemory())
        XCTAssertTrue(p.excludedByInjury.isEmpty)
        XCTAssertTrue(p.prehabSuggestions.isEmpty)
    }
}
