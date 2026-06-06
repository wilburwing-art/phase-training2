// MovementCategoryTests.swift — characterization tests for the
// movement_patterns.slug → MovementCategory reverse map.
//
// The category map is hand-maintained data (40 fine-grained pattern slugs
// rolled into 5 lifter-mental-model groups). These tests pin the spot checks
// the filter UI depends on, prove every member slug round-trips to exactly
// one category, and lock the nil fallback for unmapped / malformed slugs.
// Pure value-type logic — no CoachDatabase, no clock.

import XCTest
@testable import PhaseTraining

final class MovementCategoryTests: XCTestCase {

    // MARK: - Known slugs map to their category

    func test_category_pushSlugs() {
        XCTAssertEqual(MovementCategory.category(forSlug: "horizontal-push"), .push)
        XCTAssertEqual(MovementCategory.category(forSlug: "vertical-push"), .push)
        XCTAssertEqual(MovementCategory.category(forSlug: "scapular-protraction"), .push)
    }

    func test_category_pullSlugs() {
        XCTAssertEqual(MovementCategory.category(forSlug: "horizontal-pull"), .pull)
        XCTAssertEqual(MovementCategory.category(forSlug: "vertical-pull"), .pull)
        XCTAssertEqual(MovementCategory.category(forSlug: "scapular-retraction"), .pull)
        XCTAssertEqual(MovementCategory.category(forSlug: "elbow-flexion"), .pull)
        XCTAssertEqual(MovementCategory.category(forSlug: "climbing-pull"), .pull)
    }

    func test_category_legsSlugs() {
        XCTAssertEqual(MovementCategory.category(forSlug: "squat"), .legs)
        XCTAssertEqual(MovementCategory.category(forSlug: "hip-hinge"), .legs)
        XCTAssertEqual(MovementCategory.category(forSlug: "calf-raise"), .legs)
        XCTAssertEqual(MovementCategory.category(forSlug: "olympic-derivative"), .legs)
    }

    func test_category_coreSlugs() {
        XCTAssertEqual(MovementCategory.category(forSlug: "anti-extension"), .core)
        XCTAssertEqual(MovementCategory.category(forSlug: "anti-rotation"), .core)
        XCTAssertEqual(MovementCategory.category(forSlug: "loaded-carry"), .core)
        // hip-flexion lives in core (hanging leg raise family), not legs.
        XCTAssertEqual(MovementCategory.category(forSlug: "hip-flexion"), .core)
    }

    func test_category_conditioningSlugs() {
        XCTAssertEqual(MovementCategory.category(forSlug: "locomotion"), .conditioning)
        XCTAssertEqual(MovementCategory.category(forSlug: "jumping-landing"), .conditioning)
        XCTAssertEqual(MovementCategory.category(forSlug: "swim-stroke"), .conditioning)
        XCTAssertEqual(MovementCategory.category(forSlug: "ground-to-standing"), .conditioning)
    }

    // MARK: - Round trip + disjointness

    func test_everyMemberSlug_roundTripsToItsCategory() {
        // category(forSlug:) returns the FIRST matching category in allCases
        // order — a slug accidentally listed in two categories would shadow
        // the later one. The round trip proves both coverage and no shadowing.
        for cat in MovementCategory.allCases {
            for slug in cat.memberPatternSlugs {
                XCTAssertEqual(MovementCategory.category(forSlug: slug), cat,
                               "slug '\(slug)' should resolve to \(cat)")
            }
        }
    }

    func test_memberSlugs_areDisjointAcrossCategories() {
        var seen: Set<String> = []
        for cat in MovementCategory.allCases {
            for slug in cat.memberPatternSlugs {
                XCTAssertTrue(seen.insert(slug).inserted,
                              "slug '\(slug)' appears in more than one category")
            }
        }
    }

    // MARK: - Unknown slug fallback

    func test_unknownSlug_returnsNil() {
        XCTAssertNil(MovementCategory.category(forSlug: "definitely-not-a-pattern"))
        XCTAssertNil(MovementCategory.category(forSlug: ""))
    }

    func test_slugMatching_isExactAndCaseSensitive() {
        // Slugs are lowercase-hyphenated exact matches; UI labels and
        // space-separated variants must not resolve.
        XCTAssertNil(MovementCategory.category(forSlug: "Squat"))
        XCTAssertNil(MovementCategory.category(forSlug: "horizontal push"))
        XCTAssertNil(MovementCategory.category(forSlug: " horizontal-push "))
    }
}
