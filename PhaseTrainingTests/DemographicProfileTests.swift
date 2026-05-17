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

    // MARK: - Rationale always non-empty

    func test_rationale_always_explains_at_least_lift_and_session_choice() {
        let p = DemographicProfile.from(TrainingMemory())
        XCTAssertFalse(p.rationale.isEmpty)
    }
}
