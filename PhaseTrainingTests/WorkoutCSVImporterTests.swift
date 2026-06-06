// WorkoutCSVImporterTests.swift — characterization tests for the Phase 3
// CSV import entry point, `WorkoutCSVImporter.import(url:db:coach:)`.
//
// Each test writes a temp CSV to disk and drives the importer end-to-end
// against an isolated in-memory UserDatabase (same isolation pattern as
// ImportedWorkoutsDatabaseTests / BackupManagerTests) so the real
// Documents/user.db is never touched. CoachDatabase.shared is used
// READ-ONLY for name resolution; fixtures use "Zz ..." exercise names
// guaranteed absent from coach.db so `nameMatchRate` stays deterministic
// regardless of catalog drift. The one positive-resolution test probes the
// catalog first and self-skips if the canonical name ever disappears.
//
// All dates in fixtures are fixed literals ("+0000" offset, the shape
// Fitbod emits) so assertions never depend on the wall clock. Persistence
// is verified through date-window-free surfaces (importedSetsSummary /
// importedWorkoutSummary / importedSetsLifetimePeaks) — the windowed
// recentImportedWorkouts(within:) compares against Date() and would drift.

import XCTest
@testable import PhaseTraining

final class WorkoutCSVImporterTests: XCTestCase {

    // MARK: - Helpers

    private let header = FitbodCSVParser.expectedHeader

    /// Write CSV text to a unique temp file; removed at teardown.
    private func writeTempCSV(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutCSVImporterTests-\(UUID().uuidString)")
            .appendingPathExtension("csv")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Happy-path fixture mirroring the real export's quirks (leading-space
    /// padded Reps, trailing warmup row): 6 working sets across 3 exercises
    /// with strictly decreasing set counts (3/2/1) so `topExercises`
    /// ordering is deterministic, plus 1 cardio row and 1 warmup row.
    private var happyCSV: String {
        """
        \(header)
        2026-01-15 18:30:00 +0000,Zz Alpha Press, 8,80.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-15 18:30:00 +0000,Zz Alpha Press, 8,80.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-15 18:30:00 +0000,Zz Alpha Press, 6,82.5,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-15 18:30:00 +0000,Zz Beta Row, 10,40.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-15 18:30:00 +0000,Zz Beta Row, 10,40.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-17 19:00:00 +0000,Zz Gamma Squat, 5,100.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-17 19:00:00 +0000,Zz Cardio Run, 0,0.0,1200.0,3000.0,0.0,0.0,false,, 1.0
        2026-01-15 18:30:00 +0000,Zz Alpha Press, 5,60.0,0.0,0.0,0.0,0.0,true,, 1.0
        """
    }

    // MARK: - Happy path

    func test_happyPath_importsStrengthAndCardioRows() async throws {
        let url = try writeTempCSV(happyCSV)
        let db = UserDatabase(path: ":memory:")

        let result = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)

        XCTAssertEqual(result.source, .fitbodCSV)
        XCTAssertEqual(result.setsInserted, 6, "7 strength rows minus 1 warmup")
        XCTAssertEqual(result.workoutsInserted, 1, "Duration>0 + no weight/reps routes to imported_workouts")
        XCTAssertTrue(result.parseErrors.isEmpty, "unexpected parse errors: \(result.parseErrors)")

        // Deterministic ordering: set counts strictly decrease (3/2/1).
        XCTAssertEqual(result.topExercises.map { $0.name }, ["Zz Alpha Press", "Zz Beta Row", "Zz Gamma Squat"])
        XCTAssertEqual(result.topExercises.map { $0.sets }, [3, 2, 1])

        // Date range spans both streams (strength sets + cardio workout).
        XCTAssertEqual(result.dateRange?.oldest, utcDate(2026, 1, 15, 18, 30))
        XCTAssertEqual(result.dateRange?.newest, utcDate(2026, 1, 17, 19, 0))

        // Both streams actually landed in user.db.
        let setSummary = db.importedSetsSummary()
        XCTAssertEqual(setSummary?.count, 6)
        XCTAssertEqual(setSummary?.perSource, ["fitbodCSV": 6])
        XCTAssertEqual(setSummary?.oldest, utcDate(2026, 1, 15, 18, 30))
        XCTAssertEqual(setSummary?.newest, utcDate(2026, 1, 17, 19, 0))
        XCTAssertEqual(db.importedWorkoutSummary()?.count, 1)
    }

    func test_unmatchedNames_zeroMatchRate_andNoLifetimePeaks() async throws {
        let url = try writeTempCSV(happyCSV)
        let db = UserDatabase(path: ":memory:")

        let result = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)

        // "Zz ..." names are not in coach.db — every distinct strength name
        // stays unresolved, so the surfaced match rate is exactly 0.
        XCTAssertEqual(result.nameMatchRate, 0.0, accuracy: 0.001)
        // Unmatched rows persist (zero-data-loss) but with exercise_id NULL,
        // so they can never seed priorBest via lifetime peaks.
        XCTAssertEqual(db.importedSetsSummary()?.count, 6)
        XCTAssertTrue(db.importedSetsLifetimePeaks().isEmpty)
    }

    func test_resolvedCatalogName_flowsThroughToLifetimePeaks() async throws {
        // Probe-first so this test self-skips instead of coupling to
        // catalog contents (per the test-by-coverage-not-canonical-name
        // convention). Positive resolution at scale is covered by the
        // opt-in FitbodRealCSVSmokeTests.
        let coach = CoachDatabase.shared
        guard let expectedId = coach.exerciseId(forImportName: "Back Squat") else {
            throw XCTSkip("coach.db no longer resolves 'Back Squat' — skipping positive-resolution flow.")
        }

        let csv = """
        \(header)
        2026-01-17 19:00:00 +0000,Back Squat, 5,100.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-17 19:00:00 +0000,Back Squat, 5,102.5,0.0,0.0,0.0,0.0,false,, 1.0
        """
        let url = try writeTempCSV(csv)
        let db = UserDatabase(path: ":memory:")

        let result = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: coach)

        XCTAssertEqual(result.setsInserted, 2)
        XCTAssertEqual(result.nameMatchRate, 1.0, accuracy: 0.001)

        let peaks = db.importedSetsLifetimePeaks()
        XCTAssertEqual(peaks.count, 1)
        XCTAssertEqual(peaks.first?.exerciseId, expectedId)
        XCTAssertEqual(peaks.first?.weight, 102.5)
        XCTAssertEqual(peaks.first?.reps, 5)
    }

    // MARK: - Malformed rows (non-fatal)

    func test_malformedRows_skippedWithErrors_goodRowsStillImport() async throws {
        // Line 2: good row. Line 3: blank (skipped silently, not an error).
        // Line 4: comma inside Note → 12 cells. Line 5: unparseable date.
        // Line 6: empty Exercise. Line 7: non-warmup row without reps.
        // Line 8: good row.
        let csv = """
        \(header)
        2026-01-16 18:30:00 +0000,Zz Alpha Press, 8,80.0,0.0,0.0,0.0,0.0,false,, 1.0

        2026-01-16 18:30:00 +0000,Zz Comma Note, 8,80.0,0.0,0.0,0.0,0.0,false,felt heavy, tough set, 1.0
        not-a-date,Zz Bad Date, 8,80.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-16 18:30:00 +0000,, 8,80.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-16 18:30:00 +0000,Zz No Reps,,80.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-01-18 09:00:00 +0000,Zz Alpha Press, 5,90.0,0.0,0.0,0.0,0.0,false,, 1.0
        """
        let url = try writeTempCSV(csv)
        let db = UserDatabase(path: ":memory:")

        // Bad rows never throw — they surface in parseErrors.
        let result = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)

        XCTAssertEqual(result.setsInserted, 2, "the two good rows survive the four bad ones")
        XCTAssertEqual(result.workoutsInserted, 0)
        XCTAssertEqual(result.parseErrors.count, 4)
        XCTAssertEqual(result.parseErrors.map { $0.line }, [4, 5, 6, 7],
                       "errors carry 1-based physical line numbers; blank lines don't error")
        XCTAssertTrue(result.parseErrors[0].reason.contains("expected 11 cells, got 12"))
        XCTAssertTrue(result.parseErrors[1].reason.contains("unparseable date"))
        XCTAssertTrue(result.parseErrors[2].reason.contains("empty Exercise"))
        XCTAssertTrue(result.parseErrors[3].reason.contains("reps"))

        // Only the good rows persisted.
        XCTAssertEqual(db.importedSetsSummary()?.count, 2)
        XCTAssertEqual(result.topExercises.map { $0.name }, ["Zz Alpha Press"])
        XCTAssertEqual(result.topExercises.map { $0.sets }, [2])
    }

    // MARK: - Duplicate import

    func test_duplicateImport_isIdempotent_onStableIds() async throws {
        let url = try writeTempCSV(happyCSV)
        let db = UserDatabase(path: ":memory:")

        let first = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)
        let second = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)

        // Result counts report rows PARSED on that call, not net-new rows —
        // both calls see the same 6 + 1.
        XCTAssertEqual(first.setsInserted, 6)
        XCTAssertEqual(second.setsInserted, 6)
        XCTAssertEqual(first.workoutsInserted, 1)
        XCTAssertEqual(second.workoutsInserted, 1)

        // Deterministic ids + INSERT OR REPLACE → re-import replaces in
        // place. The DB holds exactly one copy of each row.
        XCTAssertEqual(db.importedSetsSummary()?.count, 6)
        XCTAssertEqual(db.importedWorkoutSummary()?.count, 1,
                       "cardio ids are deterministic too (source:cardio:ts:name) — no duplicate workouts")
    }

    // MARK: - Empty / header-only / wrong-header files

    func test_emptyFile_throwsUnknownFormat() async throws {
        let url = try writeTempCSV("")
        let db = UserDatabase(path: ":memory:")
        do {
            _ = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)
            XCTFail("empty file should not import")
        } catch let failure as WorkoutCSVImporter.Failure {
            guard case .unknownFormat = failure else {
                return XCTFail("expected .unknownFormat, got \(failure)")
            }
        }
        XCTAssertEqual(db.importedSetsSummary()?.count, 0)
    }

    func test_headerOnlyFile_succeedsWithZeroCounts() async throws {
        let url = try writeTempCSV(header + "\n")
        let db = UserDatabase(path: ":memory:")

        // A valid header with no data rows is NOT an error — it returns an
        // all-zero Result (header recognized, nothing to import).
        let result = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)

        XCTAssertEqual(result.setsInserted, 0)
        XCTAssertEqual(result.workoutsInserted, 0)
        XCTAssertTrue(result.parseErrors.isEmpty)
        XCTAssertNil(result.dateRange)
        XCTAssertTrue(result.topExercises.isEmpty)
        XCTAssertEqual(result.nameMatchRate, 0.0, accuracy: 0.001)
        XCTAssertEqual(db.importedSetsSummary()?.count, 0)
    }

    func test_wrongHeader_throwsUnknownFormat_mentioningFitbod() async throws {
        let url = try writeTempCSV("""
        Exercise,Date,Reps,Weight
        Zz Alpha Press,2026-01-01 00:00:00 +0000, 5,50.0
        """)
        let db = UserDatabase(path: ":memory:")
        do {
            _ = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)
            XCTFail("non-Fitbod header should be rejected")
        } catch let failure as WorkoutCSVImporter.Failure {
            guard case .unknownFormat = failure else {
                return XCTFail("expected .unknownFormat, got \(failure)")
            }
            XCTAssertTrue(failure.errorDescription?.contains("Fitbod") == true,
                          "error message should tell the user which format v1 supports")
        }
        XCTAssertEqual(db.importedSetsSummary()?.count, 0, "nothing persists on a rejected file")
    }

    func test_leadingBlankLine_beforeValidHeader_throwsHeaderMismatch() async throws {
        // Characterizes a detection/parse divergence: the importer's format
        // sniff skips blank lines (default split omits empties) and accepts
        // the file, but the parser reads line 1 verbatim and rejects the
        // blank header — surfaced as the typed .headerMismatch failure.
        let url = try writeTempCSV("\n" + happyCSV)
        let db = UserDatabase(path: ":memory:")
        do {
            _ = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)
            XCTFail("leading blank line should surface a header failure")
        } catch let failure as WorkoutCSVImporter.Failure {
            guard case .headerMismatch(let detail) = failure else {
                return XCTFail("expected .headerMismatch, got \(failure)")
            }
            XCTAssertTrue(detail.contains("header mismatch"))
        }
        XCTAssertEqual(db.importedSetsSummary()?.count, 0)
    }

    func test_crlfLineEndings_rejectedAsUnknownFormat() async throws {
        // CharacterSet.whitespaces is horizontal-only — the trailing \r on
        // the header line survives trimming, so the exact-match header
        // check rejects CRLF files rather than mis-mapping columns.
        let url = try writeTempCSV(happyCSV.replacingOccurrences(of: "\n", with: "\r\n"))
        let db = UserDatabase(path: ":memory:")
        do {
            _ = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)
            XCTFail("CRLF file should be rejected, not silently mis-parsed")
        } catch let failure as WorkoutCSVImporter.Failure {
            guard case .unknownFormat = failure else {
                return XCTFail("expected .unknownFormat, got \(failure)")
            }
        }
        XCTAssertEqual(db.importedSetsSummary()?.count, 0)
    }

    func test_missingFile_throwsUnreadable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutCSVImporterTests-missing-\(UUID().uuidString).csv")
        let db = UserDatabase(path: ":memory:")
        do {
            _ = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)
            XCTFail("nonexistent file should throw .unreadable")
        } catch let failure as WorkoutCSVImporter.Failure {
            guard case .unreadable(let why) = failure else {
                return XCTFail("expected .unreadable, got \(failure)")
            }
            XCTAssertFalse(why.isEmpty, "underlying read error should be surfaced verbatim")
        }
    }

    // MARK: - Unicode / quoted fields

    func test_unicodeExerciseNames_importAndPreserveRawName() async throws {
        let name = "Décliné Haltère Presse 中文"
        let csv = """
        \(header)
        2026-02-01 10:00:00 +0000,\(name), 8,40.0,0.0,0.0,0.0,0.0,false,, 1.0
        2026-02-01 10:00:00 +0000,\(name), 8,40.0,0.0,0.0,0.0,0.0,false,, 1.0
        """
        let url = try writeTempCSV(csv)
        let db = UserDatabase(path: ":memory:")

        let result = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)

        XCTAssertEqual(result.setsInserted, 2)
        XCTAssertTrue(result.parseErrors.isEmpty, "unicode names must not trip the parser")
        XCTAssertEqual(result.topExercises.map { $0.name }, [name],
                       "raw name preserved byte-for-byte (zero-data-loss policy)")
        XCTAssertEqual(db.importedSetsSummary()?.count, 2)
    }

    func test_quotedFields_quotesKeptVerbatim_quotedCommaBecomesParseError() async throws {
        // The observed Fitbod export never quotes fields, so the parser
        // splits on naive commas. Characterize both consequences:
        //  - quote characters are NOT stripped (they land in the raw name),
        //  - a comma inside quotes still splits the row → parse error
        //    (surfaced, per the parser doc, rather than silently corrupted).
        let csv = """
        \(header)
        2026-02-02 10:00:00 +0000,"Zz Quoted Press", 8,40.0,0.0,0.0,0.0,0.0,false,"solid work", 1.0
        2026-02-02 10:00:00 +0000,Zz Plain Press, 8,40.0,0.0,0.0,0.0,0.0,false,"hard, set", 1.0
        """
        let url = try writeTempCSV(csv)
        let db = UserDatabase(path: ":memory:")

        let result = try await WorkoutCSVImporter.`import`(url: url, db: db, coach: .shared)

        XCTAssertEqual(result.setsInserted, 1, "comma-free quoted row imports; quoted-comma row does not")
        XCTAssertEqual(result.topExercises.map { $0.name }, ["\"Zz Quoted Press\""],
                       "quote characters are preserved verbatim in the raw name")
        XCTAssertEqual(result.parseErrors.count, 1)
        XCTAssertEqual(result.parseErrors.first?.line, 3)
        XCTAssertTrue(result.parseErrors.first?.reason.contains("expected 11 cells, got 12") == true)
        XCTAssertEqual(db.importedSetsSummary()?.count, 1)
    }
}
