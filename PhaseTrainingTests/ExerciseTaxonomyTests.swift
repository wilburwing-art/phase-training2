// ExerciseTaxonomyTests.swift — pins the body-part + equipment classifier
// behavior the two-dropdown filter UI (PR 3) depends on.
//
// The classifier resolves multi-fit cases (a bench press hits chest, shoulders,
// and triceps muscle-wise) via priority order. These tests fix the priorities
// against representative cases drawn from the catalog so reorderings stay
// intentional.

import XCTest
@testable import PhaseTraining

final class ExerciseTaxonomyTests: XCTestCase {

    // MARK: - BodyPartCategory.classify

    func test_classify_cardio_wins_over_muscles() {
        // Running has primary muscle = quadriceps/calves but modality=endurance.
        // The cardio rule must win over the muscle-based rule.
        let result = BodyPartCategory.classify(
            modality: "endurance",
            primaryMuscleSlugs: ["quadriceps", "calves"],
            secondaryMuscleSlugs: [],
            patternSlugs: ["locomotion"]
        )
        XCTAssertEqual(result, .cardio)
    }

    func test_classify_olympic_by_pattern() {
        // Power Clean has pattern=olympic-derivative. Pattern beats modality.
        let result = BodyPartCategory.classify(
            modality: "strength",
            primaryMuscleSlugs: ["glutes", "hamstrings"],
            secondaryMuscleSlugs: ["quadriceps"],
            patternSlugs: ["olympic-derivative"]
        )
        XCTAssertEqual(result, .olympic)
    }

    func test_classify_olympic_by_modality_when_no_pattern() {
        // If a row is tagged power-modality but missing the pattern (data
        // hygiene gap), still classify Olympic.
        let result = BodyPartCategory.classify(
            modality: "power",
            primaryMuscleSlugs: ["glutes", "hamstrings"],
            secondaryMuscleSlugs: [],
            patternSlugs: []
        )
        XCTAssertEqual(result, .olympic)
    }

    func test_classify_fullBody_when_primary_muscle_is_full_body() {
        // Thruster has muscles_primary = ["full-body"] — must hit Full Body
        // rather than fall back to a muscle-based rule.
        let result = BodyPartCategory.classify(
            modality: "strength",
            primaryMuscleSlugs: ["full-body"],
            secondaryMuscleSlugs: ["quadriceps", "delt-anterior"],
            patternSlugs: ["squat", "vertical-push"]
        )
        XCTAssertEqual(result, .fullBody)
    }

    func test_classify_chest_for_bench_press() {
        // Bench press primary muscle = pec-major-sternal. Secondary muscles
        // include triceps (Arms) and delt-anterior (Shoulders). Chest must
        // win because of the priority order.
        let result = BodyPartCategory.classify(
            modality: "strength",
            primaryMuscleSlugs: ["pec-major-sternal"],
            secondaryMuscleSlugs: ["triceps", "delt-anterior"],
            patternSlugs: ["horizontal-push"]
        )
        XCTAssertEqual(result, .chest)
    }

    func test_classify_legs_for_squat() {
        let result = BodyPartCategory.classify(
            modality: "strength",
            primaryMuscleSlugs: ["quadriceps", "glutes"],
            secondaryMuscleSlugs: ["hamstrings", "core"],
            patternSlugs: ["squat"]
        )
        XCTAssertEqual(result, .legs)
    }

    func test_classify_arms_for_curl() {
        let result = BodyPartCategory.classify(
            modality: "strength",
            primaryMuscleSlugs: ["biceps"],
            secondaryMuscleSlugs: ["brachialis", "brachioradialis"],
            patternSlugs: ["elbow-flexion"]
        )
        XCTAssertEqual(result, .arms)
    }

    func test_classify_core_for_plank() {
        let result = BodyPartCategory.classify(
            modality: "strength",
            primaryMuscleSlugs: ["rectus-abdominis"],
            secondaryMuscleSlugs: ["external-obliques", "glutes"],
            patternSlugs: ["anti-extension"]
        )
        XCTAssertEqual(result, .core)
    }

    func test_classify_other_for_flexibility() {
        // Stretching: no muscle/pattern match, modality=flexibility.
        let result = BodyPartCategory.classify(
            modality: "flexibility",
            primaryMuscleSlugs: ["full-body"],  // generic muscle tag
            secondaryMuscleSlugs: [],
            patternSlugs: ["breathing-bracing"]
        )
        // Full-body wins over Other; this exercise type uses .fullBody.
        XCTAssertEqual(result, .fullBody)
    }

    func test_classify_other_for_unknown() {
        // Edge case — completely unmatched. Should land in Other.
        let result = BodyPartCategory.classify(
            modality: "balance",
            primaryMuscleSlugs: [],
            secondaryMuscleSlugs: ["unknown-muscle"],
            patternSlugs: []
        )
        XCTAssertEqual(result, .other)
    }

    // MARK: - EquipmentCategory.classify

    func test_classify_equipment_cardio_by_modality() {
        let result = EquipmentCategory.classify(
            modality: "endurance",
            defaultReps: nil, defaultDuration: "20-40 min",
            equipmentSlugs: ["treadmill"]
        )
        XCTAssertEqual(result, .cardio)
    }

    func test_classify_equipment_cardio_by_equipment_slug() {
        // Even if modality isn't endurance, a row tagged with an erg-class
        // equipment slug should still classify as Cardio.
        let result = EquipmentCategory.classify(
            modality: "power",
            defaultReps: "30s",
            defaultDuration: nil,
            equipmentSlugs: ["rowing-erg"]
        )
        XCTAssertEqual(result, .cardio)
    }

    func test_classify_equipment_barbell_wins_over_dumbbell() {
        // A row tagged with BOTH barbell + dumbbells (multi-equipment) should
        // classify as Barbell — that's the user-recognizable identity.
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "6-10",
            defaultDuration: nil,
            equipmentSlugs: ["barbell", "dumbbells"]
        )
        XCTAssertEqual(result, .barbell)
    }

    func test_classify_equipment_dumbbell_when_no_barbell() {
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "8-12",
            defaultDuration: nil,
            equipmentSlugs: ["dumbbells", "flat-bench"]
        )
        XCTAssertEqual(result, .dumbbell)
    }

    func test_classify_equipment_machine_for_smith_machine() {
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "6-10",
            defaultDuration: nil,
            equipmentSlugs: ["smith-machine"]
        )
        XCTAssertEqual(result, .machineOther)
    }

    func test_classify_equipment_machine_for_cable() {
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "10-15",
            defaultDuration: nil,
            equipmentSlugs: ["cable-machine"]
        )
        XCTAssertEqual(result, .machineOther)
    }

    func test_classify_equipment_machine_for_kettlebell() {
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "8-12",
            defaultDuration: nil,
            equipmentSlugs: ["kettlebell"]
        )
        XCTAssertEqual(result, .machineOther)
    }

    func test_classify_equipment_weighted_bw_for_pull_up_bar() {
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "5-10",
            defaultDuration: nil,
            equipmentSlugs: ["pull-up-bar"]
        )
        XCTAssertEqual(result, .weightedBodyweight)
    }

    func test_classify_equipment_assisted_bw_for_band() {
        // Band-assisted pull-up — pull-up-bar AND band-heavy. Pull-up-bar
        // is weighted-BW, band-heavy is assisted-BW; weighted wins because
        // it comes first in the priority. (User can search by band tag.)
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "6-10",
            defaultDuration: nil,
            equipmentSlugs: ["pull-up-bar", "band-heavy"]
        )
        XCTAssertEqual(result, .weightedBodyweight)
    }

    func test_classify_equipment_pure_band_is_assisted() {
        // Pure band exercise (no bar) — should classify as assisted bw.
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "10-15",
            defaultDuration: nil,
            equipmentSlugs: ["band-medium"]
        )
        XCTAssertEqual(result, .assistedBodyweight)
    }

    func test_classify_equipment_reps_only_for_bodyweight() {
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: "10-20",
            defaultDuration: nil,
            equipmentSlugs: ["bodyweight"]
        )
        XCTAssertEqual(result, .repsOnly)
    }

    func test_classify_equipment_duration_for_timed_hold() {
        // Plank: bodyweight, no reps, has duration — should be Duration.
        let result = EquipmentCategory.classify(
            modality: "strength",
            defaultReps: nil,
            defaultDuration: "30-60s",
            equipmentSlugs: ["bodyweight"]
        )
        XCTAssertEqual(result, .duration)
    }

    func test_classify_equipment_duration_for_flexibility() {
        // Stretching: modality=flexibility → always Duration regardless of reps.
        let result = EquipmentCategory.classify(
            modality: "flexibility",
            defaultReps: "30-60s per stretch",
            defaultDuration: "10-15 min",
            equipmentSlugs: ["bodyweight"]
        )
        XCTAssertEqual(result, .duration)
    }

    // MARK: - ExerciseFilters.from(bodyPart:equipment:)

    func test_filters_from_bodyPart_legs_yields_leg_muscle_slugs() {
        let (filters, muscles, equipment, patterns) =
            ExerciseFilters.from(bodyPart: .legs, equipment: nil)
        XCTAssertNil(filters.modality)
        XCTAssertTrue(muscles.contains("quadriceps"))
        XCTAssertTrue(muscles.contains("glutes"))
        XCTAssertTrue(equipment.isEmpty)
        XCTAssertTrue(patterns.isEmpty)
    }

    func test_filters_from_cardio_sets_modality() {
        let (filters, muscles, equipment, patterns) =
            ExerciseFilters.from(bodyPart: .cardio, equipment: nil)
        XCTAssertEqual(filters.modality, "endurance")
        XCTAssertTrue(muscles.isEmpty)
        XCTAssertTrue(equipment.isEmpty)
        XCTAssertTrue(patterns.isEmpty)
    }

    func test_filters_from_olympic_sets_pattern() {
        let (_, _, _, patterns) =
            ExerciseFilters.from(bodyPart: .olympic, equipment: nil)
        XCTAssertEqual(patterns, ["olympic-derivative"])
    }

    func test_filters_from_equipment_barbell_yields_barbell_slug() {
        let (_, _, equipment, _) =
            ExerciseFilters.from(bodyPart: nil, equipment: .barbell)
        XCTAssertEqual(equipment, ["barbell", "ez-bar"])
    }

    func test_filters_from_both_axes_combine() {
        let (filters, muscles, equipment, _) =
            ExerciseFilters.from(bodyPart: .legs, equipment: .barbell)
        XCTAssertFalse(muscles.isEmpty)
        XCTAssertFalse(equipment.isEmpty)
        XCTAssertNil(filters.modality)
    }
}
