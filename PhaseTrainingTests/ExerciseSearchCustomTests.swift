// ExerciseSearchCustomTests — custom exercises merged into the picker query
// (ExerciseSearch.run with a userDB). CoachDatabaseSearchTests covers the
// catalog-only broadening; these cover the merge on top of it.

import XCTest
@testable import PhaseTraining

final class ExerciseSearchCustomTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(CoachDatabase.shared.isOpen, "coach.db not bundled")
    }

    private func db(_ rows: [(String, MuscleBucket?)]) throws -> UserDatabase {
        let db = UserDatabase(path: ":memory:")
        for (name, bucket) in rows {
            _ = try db.createUserExercise(name: name, muscleBucket: bucket, notes: nil).get()
        }
        return db
    }

    /// A modality the catalog actually uses, read at test time.
    private func someModality() throws -> String {
        try XCTUnwrap(CoachDatabase.shared.listExercises().compactMap(\.modality).first)
    }

    func test_typedQueryMatchingOnlyACustomExercise_returnsIt_unbroadened() throws {
        let userDB = try db([("Qzxv Wbrt Lift", nil)])
        let out = ExerciseSearch.run(query: "qzxv wbrt", filters: ExerciseFilters(), userDB: userDB)
        XCTAssertEqual(out.exercises.first?.name, "Qzxv Wbrt Lift")
        XCTAssertTrue(out.exercises.first?.isCustom ?? false)
        XCTAssertFalse(out.broadenedPastFilters)
    }

    func test_everyQueryToken_mustAppearInTheName() throws {
        let userDB = try db([("Hammer Strength Leg Press", .quads), ("Zorblax Leg Curl", .hamstrings)])
        let out = ExerciseSearch.run(query: "leg ham", filters: ExerciseFilters(), userDB: userDB)
        let custom = out.exercises.filter(\.isCustom).map(\.name)
        XCTAssertEqual(custom, ["Hammer Strength Leg Press"], "\"ham\" is not in Zorblax Leg Curl")
        XCTAssertTrue(ExerciseSearch.customMatches("Hammer Strength Leg Press", query: "  LEG   ham "))
        XCTAssertTrue(ExerciseSearch.customMatches("Anything", query: ""), "an empty query matches all")
    }

    func test_bucketFilter_keepsTheSameBucket_andDropsAnother() throws {
        let userDB = try db([("Zorblax Squat", .quads), ("Zorblax Row", .back), ("Zorblax Hold", nil)])
        var filters = ExerciseFilters()
        filters.bucket = .quads
        for query in ["zorblax", ""] {
            let out = ExerciseSearch.run(query: query, filters: filters, userDB: userDB)
            XCTAssertEqual(out.exercises.filter(\.isCustom).map(\.name), ["Zorblax Squat"], "query '\(query)'")
            XCTAssertFalse(out.broadenedPastFilters, "a same-bucket custom hit is a real hit; query '\(query)'")
        }
    }

    func test_catalogOnlyFilters_excludeCustomExercises_andATypedQueryBroadensToThem() throws {
        let userDB = try db([("Qzxv Wbrt Lift", .chest)])
        var filters = ExerciseFilters()
        filters.modality = try someModality()

        let browse = ExerciseSearch.run(query: "", filters: filters, userDB: userDB)
        XCTAssertFalse(browse.exercises.contains(where: \.isCustom), "custom rows carry no modality")
        XCTAssertFalse(browse.broadenedPastFilters)

        let typed = ExerciseSearch.run(query: "qzxv wbrt", filters: filters, userDB: userDB)
        XCTAssertTrue(typed.broadenedPastFilters)
        XCTAssertEqual(typed.exercises.first?.name, "Qzxv Wbrt Lift")

        // Each other catalog-only filter excludes them the same way.
        var others: [ExerciseFilters] = []
        var f = ExerciseFilters(); f.category = .push; others.append(f)
        f = ExerciseFilters(); f.difficulty = "beginner"; others.append(f)
        f = ExerciseFilters(); f.environment = "gym"; others.append(f)
        f = ExerciseFilters(); f.compoundOnly = true; others.append(f)
        f = ExerciseFilters(); f.compoundOnly = false; others.append(f)
        for filters in others {
            XCTAssertFalse(ExerciseSearch.run(query: "", filters: filters, userDB: userDB)
                .exercises.contains(where: \.isCustom), "\(filters)")
        }
    }

    func test_hideOtherSports_doesNotExcludeCustomExercises() throws {
        let userDB = try db([("Zorblax Pull", .back)])
        var filters = ExerciseFilters()
        filters.hideOtherSports = true
        let out = ExerciseSearch.run(query: "zorblax", filters: filters,
                                     userSportSlugs: ["alpine-skiing"], userDB: userDB)
        XCTAssertEqual(out.exercises.first?.name, "Zorblax Pull")
        XCTAssertFalse(out.broadenedPastFilters)
    }

    func test_customRows_precedeCatalogRows_sortedByName() throws {
        let userDB = try db([("Zorblax Press B", nil), ("Zorblax Press A", nil)])
        let out = ExerciseSearch.run(query: "press", filters: ExerciseFilters(), userDB: userDB)
        let firstCatalog = try XCTUnwrap(out.exercises.firstIndex { !$0.isCustom }, "catalog has presses")
        XCTAssertEqual(out.exercises.prefix(firstCatalog).map(\.name), ["Zorblax Press A", "Zorblax Press B"])
        XCTAssertFalse(out.exercises[firstCatalog...].contains(where: \.isCustom))
    }

    func test_broadenedResult_carriesTextMatchingCustoms_evenWithNoWideCatalogRows() throws {
        let userDB = try db([("Qzxv Wbrt Lift", .chest)])
        var filters = ExerciseFilters()
        filters.bucket = .quads
        let out = ExerciseSearch.run(query: "qzxv wbrt", filters: filters, userDB: userDB)
        XCTAssertTrue(out.broadenedPastFilters, "another-bucket custom is found by dropping the filter")
        XCTAssertEqual(out.exercises.map(\.name), ["Qzxv Wbrt Lift"])
    }

    /// Regression guard on the merge: with no custom exercises, every query
    /// returns exactly what the catalog-only search returns.
    func test_noCustomExercises_resultsMatchTheCatalogOnlySearch() throws {
        let empty = UserDatabase(path: ":memory:")
        var chestPush = ExerciseFilters(); chestPush.bucket = .chest; chestPush.category = .push
        var quadsLegs = ExerciseFilters(); quadsLegs.bucket = .quads; quadsLegs.category = .legs
        var modality = ExerciseFilters(); modality.modality = try someModality()
        let cases: [(String, ExerciseFilters)] = [
            ("", ExerciseFilters()), ("bench press", ExerciseFilters()), ("pull ups", chestPush),
            ("dumbbell shoulder press", quadsLegs), ("weighted dips", chestPush),
            ("squat", modality), ("zzzxqwvk", ExerciseFilters()), ("", quadsLegs),
        ]
        for (query, filters) in cases {
            let merged = ExerciseSearch.run(query: query, filters: filters, userDB: empty)
            let catalog = ExerciseSearch.run(query: query, filters: filters)
            XCTAssertEqual(merged.exercises.map(\.id), catalog.exercises.map(\.id), "'\(query)' \(filters)")
            XCTAssertEqual(merged.broadenedPastFilters, catalog.broadenedPastFilters, "'\(query)'")
            XCTAssertEqual(merged.tier, catalog.tier, "'\(query)'")
        }
    }

    /// The case the broaden rule was extended for: under a modality filter the
    /// catalog only half-matches ("curl" lands, "qzxv" does not), and the
    /// custom exercise that matches every word is excluded by that filter.
    /// The literal custom hit beats the `.partial` rows, so the search widens.
    func test_customLiteralHit_beatsPartialFilteredRows() throws {
        let userDB = try db([("Qzxv Curl", .biceps)])
        var filters = ExerciseFilters()
        filters.modality = "strength"
        let catalogOnly = ExerciseSearch.run(query: "qzxv curl", filters: filters)
        XCTAssertEqual(catalogOnly.tier, .partial, "fixture: the filtered catalog pass is partial-only")
        XCTAssertFalse(catalogOnly.exercises.isEmpty, "fixture: partial rows exist")
        XCTAssertFalse(catalogOnly.broadenedPastFilters, "fixture: catalog alone does not widen")

        let out = ExerciseSearch.run(query: "qzxv curl", filters: filters, userDB: userDB)
        XCTAssertTrue(out.broadenedPastFilters)
        XCTAssertEqual(out.exercises.first?.name, "Qzxv Curl")
        XCTAssertEqual(out.tier, .partial, "tier still reports the catalog")
    }

    /// A custom that passes the filters is a real hit and never forces a widen,
    /// even when the catalog rows beside it are partial.
    func test_customPassingTheFilters_doesNotForceABroaden() throws {
        let userDB = try db([("Qzxv Curl", .biceps)])
        var filters = ExerciseFilters()
        filters.bucket = .biceps
        let out = ExerciseSearch.run(query: "qzxv curl", filters: filters, userDB: userDB)
        XCTAssertFalse(out.broadenedPastFilters)
        XCTAssertEqual(out.exercises.first?.name, "Qzxv Curl")
    }

    /// `userDB: nil` (the import-matching picker) never returns a custom row,
    /// even with the app's store, which the cache holds, full of them.
    func test_nilUserDB_returnsNoCustomExercises() throws {
        let store = try db([("Qzxv Wbrt Lift", .chest), ("Zorblax Press", nil)])
        let saved = ExerciseLookupCache.shared.userDB
        ExerciseLookupCache.shared.userDB = store
        defer { ExerciseLookupCache.shared.userDB = saved }
        var modality = ExerciseFilters(); modality.modality = try someModality()
        for (query, filters) in [("", ExerciseFilters()), ("press", ExerciseFilters()),
                                 ("qzxv wbrt", ExerciseFilters()), ("qzxv wbrt", modality)] {
            let out = ExerciseSearch.run(query: query, filters: filters, userDB: nil)
            XCTAssertFalse(out.exercises.contains { $0.id < 0 }, "'\(query)'")
        }
    }
}
