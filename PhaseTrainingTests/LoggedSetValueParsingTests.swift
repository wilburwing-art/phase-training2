// LoggedSetValueParsingTests.swift — characterization coverage for
// LoggedSet.weightValue / repsValue free-text parsing edges not exercised
// by LoggedSetParsingTests, plus SessionStore.clearActive semantics.

import XCTest
@testable import PhaseTraining

final class LoggedSetValueParsingTests: XCTestCase {

    // Mirrors SessionStore.activeKey (private in production code).
    private static let activeKey = "pt_active_session"

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func set(_ weight: String, _ reps: String = "5") -> LoggedSet {
        LoggedSet(num: 1, weight: weight, reps: reps, rpe: "", done: true)
    }

    private func makeActiveSession() -> ActiveSession {
        ActiveSession(
            templateId: "t1",
            name: "Push",
            category: "Push",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [
                LoggedExercise(
                    id: "bench", name: "Bench Press", type: "Barbell", unit: "lbs",
                    targetSets: 1, targetReps: 5, rest: 120,
                    sets: [LoggedSet(num: 1, weight: "225", reps: "5", rpe: "8", done: true)],
                    prevSets: []
                )
            ],
            feel: nil,
            note: nil
        )
    }

    private func makeSavedSession(start: Date = Date(timeIntervalSince1970: 1_690_000_000)) -> SavedSession {
        SavedSession(
            templateId: "t-saved",
            name: "Pull",
            category: "Pull",
            startTime: start,
            exercises: [
                LoggedExercise(
                    id: "row", name: "Barbell Row", type: "Barbell", unit: "lbs",
                    targetSets: 1, targetReps: 8, rest: 90,
                    sets: [LoggedSet(num: 1, weight: "185", reps: "8", rpe: "7", done: true)],
                    prevSets: []
                )
            ],
            feel: "OK",
            note: nil,
            endTime: start.addingTimeInterval(3600),
            duration: 3600
        )
    }

    // MARK: - weightValue

    func test_weightValue_lowercaseBodyweightSentinel_isNil() {
        // LoggedSetParsingTests covers "BW"/"bodyweight"; the lowercase form
        // matches LoggedExercise.bodyweightUnit and must also yield nil so
        // `?? 0` callers treat it as zero external load.
        XCTAssertNil(set("bw").weightValue)
    }

    func test_weightValue_whitespaceOnly_isNil() {
        XCTAssertNil(set("   ").weightValue)
        XCTAssertNil(set("\t").weightValue)
    }

    func test_weightValue_leadingDotDecimal() {
        // ".5" survives the digit/dot prefix and Double(".5") accepts it.
        XCTAssertEqual(set(".5").weightValue, 0.5)
    }

    func test_weightValue_spaceSeparatedUnit_stopsAtSpace() {
        // The numeric prefix ends at the first non-digit/non-dot character,
        // so a space-separated unit parses the same as an attached one.
        XCTAssertEqual(set("185 lbs").weightValue, 185)
        XCTAssertEqual(set("60 kg").weightValue, 60)
    }

    func test_weightValue_textBeforeNumber_isNil() {
        // The parser is leading-number only: any non-numeric lead blocks the
        // prefix entirely. Embedded/late numbers are not rescued.
        XCTAssertNil(set("kg60").weightValue)
        XCTAssertNil(set("about 135").weightValue)
    }

    func test_weightValue_garbageWords_isNil() {
        XCTAssertNil(set("heavy").weightValue)
        XCTAssertNil(set(".").weightValue)
    }

    func test_weightValue_signCharacters() {
        // A bare "+" leaves nothing to parse; nil, no crash.
        XCTAssertNil(set("+").weightValue)
        // Only a leading "+" is tolerated — "-" is not in the tolerance list,
        // so a negative entry reads as garbage rather than a negative load.
        XCTAssertNil(set("-135").weightValue)
    }

    func test_weightValue_malformedNumerics_isNil() {
        // Double-dot prefix survives the character filter but Double rejects it.
        XCTAssertNil(set("12.5.3").weightValue)
        // Lone commas (no dot present) all convert to decimal points, producing
        // a multi-dot string that Double rejects.
        XCTAssertNil(set("1,2,3").weightValue)
    }

    func test_weightValue_multipleThousandsGroups() {
        // Both separators present: every comma strips as thousands grouping.
        XCTAssertEqual(set("1,234,567.5").weightValue, 1_234_567.5)
    }

    func test_weightValue_plusAndEuropeanDecimalCombined() {
        // Leading "+" strip and lone-comma-as-decimal compose.
        XCTAssertEqual(set("+60,5").weightValue, 60.5)
    }

    // MARK: - repsValue

    func test_repsValue_zero_isZeroNotNil() {
        // "0" is a parseable number — distinct from blank/garbage (nil).
        // Downstream PR math separately guards reps > 0.
        XCTAssertEqual(set("135", "0").repsValue, 0)
    }

    func test_repsValue_amrapPlusNotation_takesLeadingNumber() {
        // "10+" (program notation for "10 or more") yields the base count;
        // the trailing "+" ends the numeric prefix.
        XCTAssertEqual(set("135", "10+").repsValue, 10)
    }

    func test_repsValue_freeTextAfterNumber() {
        XCTAssertEqual(set("135", "12 reps").repsValue, 12)
        XCTAssertEqual(set("135", "8 each side").repsValue, 8)
    }

    func test_repsValue_decimalEntry_roundsToNearest() {
        // .rounded() is to-nearest-or-away-from-zero before Int(exactly:).
        XCTAssertEqual(set("135", "8.4").repsValue, 8)
        XCTAssertEqual(set("135", "8.5").repsValue, 9)
    }

    func test_repsValue_leadingPlus() {
        XCTAssertEqual(set("135", "+5").repsValue, 5)
    }

    func test_repsValue_negativeAndGarbage_isNil() {
        XCTAssertNil(set("135", "-5").repsValue)
        XCTAssertNil(set("135", "x5").repsValue)
        XCTAssertNil(set("135", "max").repsValue)
        XCTAssertNil(set("135", "   ").repsValue)
    }

    // MARK: - SessionStore.clearActive

    func test_clearActive_clearsMemoryAndPersistedBlob() {
        let store = SessionStore(defaults: defaults, userDB: UserDatabase(path: ":memory:"))
        store.saveActive(makeActiveSession())

        // Precondition: the autosave blob landed in defaults.
        XCTAssertNotNil(defaults.data(forKey: Self.activeKey))
        XCTAssertNotNil(store.active)

        store.clearActive()

        XCTAssertNil(store.active)
        XCTAssertNil(defaults.data(forKey: Self.activeKey),
                     "clearActive must remove the persisted autosave blob")
        XCTAssertNil(store.loadActive())
    }

    func test_clearActive_persistsAcrossInstanceSwap() {
        let userDB = UserDatabase(path: ":memory:")
        let store1 = SessionStore(defaults: defaults, userDB: userDB)
        store1.saveActive(makeActiveSession())
        store1.clearActive()

        // A fresh store over the same defaults must NOT resurrect the session.
        let store2 = SessionStore(defaults: defaults, userDB: userDB)
        XCTAssertNil(store2.active)
        XCTAssertNil(store2.loadActive())
    }

    func test_clearActive_isIdempotentWhenNoActiveSession() {
        let store = SessionStore(defaults: defaults, userDB: UserDatabase(path: ":memory:"))
        XCTAssertNil(store.active)

        store.clearActive()
        store.clearActive()

        XCTAssertNil(store.active)
        XCTAssertNil(defaults.data(forKey: Self.activeKey))
    }

    func test_clearActive_doesNotTouchSavedSessions() {
        let userDB = UserDatabase(path: ":memory:")
        let store = SessionStore(defaults: defaults, userDB: userDB)
        store.saveAll([makeSavedSession()])
        let before = store.savedSessions
        XCTAssertEqual(before.count, 1, "fixture sanity")

        store.saveActive(makeActiveSession())
        store.clearActive()

        XCTAssertEqual(store.savedSessions, before,
                       "clearActive must not mutate the saved-history cache")

        // The SQLite rows are untouched too: a fresh store over the same DB
        // lists the same history with no active session.
        let store2 = SessionStore(defaults: defaults, userDB: userDB)
        XCTAssertEqual(store2.savedSessions, before)
        XCTAssertNil(store2.active)
    }
}
