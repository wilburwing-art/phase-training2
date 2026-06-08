// WorkoutCSVImporter.swift — Phase 3 entry point for CSV strength history.
//
// Detects format from the header row, dispatches to the matching parser,
// resolves exercise names against coach.db, and persists both
// `imported_sets` (strength) and `imported_workouts` (cardio rows) in a
// single transaction via UserDatabase. Per the personalization-three-axes
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
    }

    enum Failure: Error, LocalizedError {
        case unreadable(String)
        case unknownFormat
        case headerMismatch(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "Couldn't read the file: \(why)"
            case .unknownFormat: return "Unrecognized CSV format. v1 supports Fitbod exports."
            case .headerMismatch(let detail): return "CSV header didn't match the expected Fitbod shape. \(detail)"
            }
        }
    }

    /// Import a CSV from a security-scoped URL (e.g. from `.fileImporter`).
    /// Caller is responsible for `startAccessingSecurityScopedResource`
    /// on the URL before invoking and stopping after.
    static func `import`(url: URL, db: UserDatabase = .shared, coach: CoachDatabase = .shared) async throws -> Result {
        let csv: String
        do {
            csv = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }

        // Format detection: header row.
        let firstLine = csv.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let source = detectSource(headerLine: firstLine)
        guard let source else { throw Failure.unknownFormat }

        switch source {
        case .fitbodCSV:
            return try await runFitbod(csv: csv, db: db, coach: coach)
        case .hevyCSV, .stravaCSV:
            // Stubbed for Phase 3.5; format detected, parser not yet wired.
            throw Failure.unknownFormat
        case .healthKit:
            // HK isn't a CSV source — shouldn't reach here.
            throw Failure.unknownFormat
        }
    }

    private static func detectSource(headerLine: String) -> ImportSource? {
        if headerLine == FitbodCSVParser.expectedHeader { return .fitbodCSV }
        // Hevy + Strava header signatures land in Phase 3.5.
        return nil
    }

    private static func runFitbod(csv: String, db: UserDatabase, coach: CoachDatabase) async throws -> Result {
        let parsed = FitbodCSVParser.parse(csv, source: .fitbodCSV) { rawName in
            coach.exerciseId(forImportName: rawName)
        }

        if parsed.totalRows == 0 && !parsed.errors.isEmpty {
            // Header was rejected upstream — surface as a typed failure.
            throw Failure.headerMismatch(parsed.errors.first?.reason ?? "header rejected")
        }

        // Persist both streams. Wrapped in implicit transactions per
        // UserDatabase's insertImportedSets/insertImportedWorkouts.
        db.insertImportedSets(parsed.sets)
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
            source: .fitbodCSV,
            setsInserted: parsed.sets.count,
            workoutsInserted: parsed.workouts.count,
            nameMatchRate: parsed.nameMatchRate,
            dateRange: dateRange,
            parseErrors: parsed.errors,
            topExercises: Array(top),
            warmupsSkipped: parsed.warmupsSkipped
        )
    }
}
