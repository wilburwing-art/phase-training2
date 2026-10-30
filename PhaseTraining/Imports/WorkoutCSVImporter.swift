// WorkoutCSVImporter.swift — Phase 3 entry point for CSV strength history.
//
// Detects format from the header row, dispatches to the matching parser,
// resolves exercise names against coach.db, and persists both
// `imported_sets` (strength) and `imported_workouts` (cardio rows) in a
// single transaction via UserDatabase. Per the personalization-two-axes
// skill, this only feeds Phase 2's data-derived readiness/peak axis — it
// never touches the user's self-reported `ExperienceLevel`.
//
// v1 supports Fitbod only. Hevy and Strava parsers will land in Phase
// 3.5 — their `ImportSource` cases are already defined and the dispatch
// switch below is the single seam where they plug in.

import Foundation

enum WorkoutCSVImporter {

    /// Outcome of a single import call. Surfaced verbatim by the
    /// Settings → Imports screen.
    struct Result {
        let source: ImportSource
        let setsInserted: Int
        let workoutsInserted: Int
        let nameMatchRate: Double      // 0..1 across distinct names
        let dateRange: (oldest: Date, newest: Date)?
        let parseErrors: [(line: Int, raw: String, reason: String)]
        /// Top 3 most-set exercises (resolved name OR raw name fallback).
        let topExercises: [(name: String, sets: Int)]
        /// Warmup rows the parser dropped — surfaced so the user can tell a
        /// big "skipped" number (possible column drift) from a clean import.
        let warmupsSkipped: Int
        /// Eras of pounds typed in kg mode that were converted on the way
        /// in (`ImportUnitCorrection`), so the summary can say so.
        var unitCorrections: [ImportUnitCorrection.Report] = []
        /// How weights without a stated unit were read (Strong), so a wrong
        /// guess is visible in the summary.
        var unitNote: String? = nil
    }

    enum Failure: Error, LocalizedError {
        case unreadable(String)
        case unknownFormat
        case headerMismatch(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "Couldn't read the file: \(why)"
            case .unknownFormat: return "Unrecognized CSV format. Fitbod, Hevy and Strong exports are supported."
            case .headerMismatch(let detail): return "CSV header didn't match the expected shape. \(detail)"
            }
        }
    }

    /// Import a CSV from a security-scoped URL (e.g. from `.fileImporter`).
    /// Caller is responsible for `startAccessingSecurityScopedResource`
    /// on the URL before invoking and stopping after.
    /// `fallbackImperial` is the user's unit, used only for a Strong export
    /// that states no unit.
    static func `import`(url: URL, db: UserDatabase = .shared, coach: CoachDatabase = .shared,
                         fallbackImperial: Bool = true) async throws -> Result {
        let csv: String
        do {
            csv = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }

        // Format detection: header row.
        // .whitespacesAndNewlines, not .whitespaces — the latter is
        // HORIZONTAL only (space + tab), so a CRLF-terminated export left a
        // trailing \r on the header and the byte-exact comparison in
        // detectSource failed. A Fitbod CSV saved on Windows, or round-tripped
        // through a spreadsheet, was rejected as "unknown format" with no clue
        // why. Every mainstream export tool can emit CRLF.
        let firstLine = csv.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = detectSource(headerLine: firstLine)
        guard let source else { throw Failure.unknownFormat }

        return try run(csv: csv, source: source, db: db, coach: coach, fallbackImperial: fallbackImperial)
    }

    /// Parse and persist text already read. Split from `import(url:)` so tests
    /// run it on fixture strings.
    static func run(csv: String, source: ImportSource, db: UserDatabase = .shared, coach: CoachDatabase = .shared,
                    fallbackImperial: Bool = true) throws -> Result {
        let resolve = db.importNameResolver(coach: coach)
        switch source {
        case .fitbodCSV:
            return try runFitbod(csv: csv, db: db, coach: coach)
        case .hevyCSV:
            return try persist(HevyCSVParser.parse(csv, nameResolver: resolve), source: .hevyCSV, db: db)
        case .strongCSV:
            let parsed = StrongCSVParser.parse(csv, fallbackImperial: fallbackImperial, nameResolver: resolve)
            var result = try persist(parsed.result, source: .strongCSV, db: db)
            if parsed.unitSource == .assumed {
                result.unitNote = "Weights read as \(parsed.imperial ? "lb" : "kg"): the file doesn't say, so your unit setting was used"
            }
            return result
        case .stravaCSV:
            throw Failure.unknownFormat
        case .healthKit:
            // HK isn't a CSV source — shouldn't reach here.
            throw Failure.unknownFormat
        }
    }

    static func detectSource(headerLine: String) -> ImportSource? {
        if headerLine == FitbodCSVParser.expectedHeader { return .fitbodCSV }
        if let fields = CSVRows.parse(headerLine, delimiter: ",").first?.fields, HevyCSVParser.looksLikeHeader(fields) {
            return .hevyCSV
        }
        let strongDelimiter = StrongCSVParser.delimiter(forHeaderLine: headerLine)
        if let fields = CSVRows.parse(headerLine, delimiter: strongDelimiter).first?.fields,
           StrongCSVParser.looksLikeHeader(fields) {
            return .strongCSV
        }
        // Strava stays undetected until it has a parser: detecting a format
        // we can't read turns "unknown format" into a failure on a file we
        // claimed to recognize.
        return nil
    }

    private static func runFitbod(csv: String, db: UserDatabase, coach: CoachDatabase) throws -> Result {
        // The user's own matches (import_name_map) win over the catalog.
        let parsed = FitbodCSVParser.parse(csv, source: .fitbodCSV, nameResolver: db.importNameResolver(coach: coach))
        // A kg-mode era holding pound numbers reads 2.2x too heavy; convert
        // it before anything downstream sees it. Fitbod only: Hevy and Strong
        // state their unit.
        return try persist(parsed, source: .fitbodCSV, db: db, correctUnitEras: true)
    }

    /// Write a parse to user.db and summarize it. Shared by every format.
    private static func persist(_ parsed: FitbodCSVParser.ParseResult, source: ImportSource, db: UserDatabase,
                                correctUnitEras: Bool = false) throws -> Result {
        if parsed.totalRows == 0 && !parsed.errors.isEmpty {
            // Header was rejected upstream — surface as a typed failure.
            throw Failure.headerMismatch(parsed.errors.first?.reason ?? "header rejected")
        }

        let corrected = correctUnitEras ? ImportUnitCorrection.apply(parsed.sets) : (sets: parsed.sets, reports: [])

        // Persist both streams. Wrapped in implicit transactions per
        // UserDatabase's insertImportedSets/insertImportedWorkouts.
        db.insertImportedSets(corrected.sets)
        db.insertImportedWorkouts(parsed.workouts)

        let dateRange: (oldest: Date, newest: Date)?
        let allTimes = parsed.sets.map(\.performedAt) + parsed.workouts.map(\.startTime)
        if let oldest = allTimes.min(), let newest = allTimes.max() {
            dateRange = (oldest, newest)
        } else {
            dateRange = nil
        }

        // Top 3 most-set exercises (by resolved or raw name).
        var counts: [String: Int] = [:]
        for s in parsed.sets {
            counts[s.exerciseNameRaw, default: 0] += 1
        }
        let top = counts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { (name: $0.key, sets: $0.value) }

        return Result(
            source: source,
            setsInserted: parsed.sets.count,
            workoutsInserted: parsed.workouts.count,
            nameMatchRate: parsed.nameMatchRate,
            dateRange: dateRange,
            parseErrors: parsed.errors,
            topExercises: Array(top),
            warmupsSkipped: parsed.warmupsSkipped,
            unitCorrections: corrected.reports
        )
    }
}
