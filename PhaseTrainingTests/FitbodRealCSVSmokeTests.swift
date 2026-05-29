// FitbodRealCSVSmokeTests.swift — opt-in integration smoke against a
// real user Fitbod export. Auto-skips when the file isn't present so
// CI stays green; runs locally when ~/Downloads/FitBodWorkoutExport.csv
// exists (or FITBOD_CSV_PATH points at one).
//
// Purpose: catch regressions in the parser or CoachDatabase resolution
// against thousands of real-world rows that the hand-rolled fixture
// can't cover. Prints diagnostics (row counts, match rate, top
// exercises, error sample) so the user can eyeball coverage drift
// without firing up the simulator UI.

import XCTest
@testable import PhaseTraining

final class FitbodRealCSVSmokeTests: XCTestCase {

    private func locateCSV() -> URL? {
        // Try paths in order. iOS sim's HOME isn't the Mac user's HOME,
        // so a literal tilde won't expand correctly — fall through to the
        // hardcoded Mac path. Both TEST_RUNNER_ (xcodebuild auto-prefix)
        // and bare FITBOD_CSV_PATH are accepted so either invocation works.
        let env = ProcessInfo.processInfo.environment
        let candidates: [String] = [
            env["FITBOD_CSV_PATH"] ?? "",
            env["TEST_RUNNER_FITBOD_CSV_PATH"] ?? "",
            ("~/Downloads/FitBodWorkoutExport.csv" as NSString).expandingTildeInPath,
            "/Users/wilburpyn/Downloads/FitBodWorkoutExport.csv",
        ]
        for path in candidates where !path.isEmpty {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func testRealFitbodExportParsesAndResolvesAgainstCoachDB() throws {
        guard let url = locateCSV() else {
            throw XCTSkip("FITBOD_CSV_PATH not set and ~/Downloads/FitBodWorkoutExport.csv missing — skipping integration smoke.")
        }

        let csv = try String(contentsOf: url, encoding: .utf8)
        let coach = CoachDatabase.shared

        let result = FitbodCSVParser.parse(csv, source: .fitbodCSV) { name in
            coach.exerciseId(forImportName: name)
        }

        // Diagnostics — printed to test log so the user can read coverage
        // without standing up the importer UI.
        let attachment = """
        --- Fitbod real-export smoke ---
        file:               \(url.path)
        total_rows:         \(result.totalRows)
        strength_sets:      \(result.sets.count)
        cardio_workouts:    \(result.workouts.count)
        parse_errors:       \(result.errors.count)
        unique_names:       \(Set(result.sets.map(\.exerciseNameRaw)).count)
        match_rate:         \(String(format: "%.1f%%", result.nameMatchRate * 100))
        unmatched_examples: \(unmatchedExamples(result).joined(separator: ", "))
        top_5_by_volume:    \(topByVolume(result, n: 5))
        date_range:         \(dateRange(result))
        peak_examples:      \(peakExamples(result, coach: coach, n: 5))
        first_parse_errors: \(result.errors.prefix(3).map { "line \($0.line): \($0.reason)" }.joined(separator: " | "))
        """
        print(attachment)
        add(XCTAttachment(string: attachment))

        // Sanity assertions — looking for catastrophic regression, not
        // exact counts (the export changes over time).
        XCTAssertGreaterThan(result.totalRows, 100, "too few rows — header rejected?")
        XCTAssertGreaterThan(result.sets.count, 50, "almost nothing parsed as strength")
        // Real-world floor — 9 years of Fitbod history against a coach.db
        // that doesn't have full alias coverage for variants like
        // "Alternating Dumbbell Bench Press", "Hammerstrength Chest Press",
        // and machine names lands ~24% with the current alias set. Floor
        // catches a regression to single-digit %, not the absolute level.
        XCTAssertGreaterThan(result.nameMatchRate, 0.15, "name match rate dropped below 15% (\(result.nameMatchRate)) — alias/slug rules regressed?")
        XCTAssertLessThan(Double(result.errors.count) / Double(max(result.totalRows, 1)), 0.05,
                          "more than 5% of rows failed to parse — schema drift?")
    }

    private func unmatchedExamples(_ r: FitbodCSVParser.ParseResult) -> [String] {
        let unmatched = Set(r.sets.filter { $0.exerciseId == nil }.map(\.exerciseNameRaw))
        return Array(unmatched.sorted().prefix(5))
    }

    private func topByVolume(_ r: FitbodCSVParser.ParseResult, n: Int) -> String {
        var counts: [String: Int] = [:]
        for s in r.sets { counts[s.exerciseNameRaw, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }
            .prefix(n)
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
    }

    private func dateRange(_ r: FitbodCSVParser.ParseResult) -> String {
        let dates = r.sets.map(\.performedAt) + r.workouts.map(\.startTime)
        guard let oldest = dates.min(), let newest = dates.max() else { return "—" }
        let f = ISO8601DateFormatter()
        return "\(f.string(from: oldest)) → \(f.string(from: newest))"
    }

    private func peakExamples(_ r: FitbodCSVParser.ParseResult, coach: CoachDatabase, n: Int) -> String {
        // Heaviest matched set per resolved exercise — surfaced so the
        // user can spot-check that kg→lb conversion + name resolution
        // look right against their own recall.
        var peaks: [Int: (name: String, weightKg: Double, reps: Int)] = [:]
        for s in r.sets {
            guard let exId = s.exerciseId, let w = s.weight, let reps = s.reps else { continue }
            if let prev = peaks[exId], prev.weightKg >= w { continue }
            let name = coach.exercise(id: exId)?.name ?? s.exerciseNameRaw
            peaks[exId] = (name, w, reps)
        }
        return peaks.values
            .sorted { $0.weightKg > $1.weightKg }
            .prefix(n)
            .map { String(format: "%@: %.1f kg × %d", $0.name, $0.weightKg, $0.reps) }
            .joined(separator: ", ")
    }
}
