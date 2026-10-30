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
            "/Users/wilburpyn/Desktop/Desktop - Wilbur\u{2019}s MacBook Air/WorkoutExport.csv",
            ("~/Downloads/FitBodWorkoutExport.csv" as NSString).expandingTildeInPath,
            "/Users/wilburpyn/Downloads/FitBodWorkoutExport.csv",
            "/Users/wilburpyn/Downloads/Phase-Training/FitBodWorkoutExport.csv",
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
        // Real-world floor — after the Phase 3.5 alias expansion we run
        // ~67% on the user's 9-year Fitbod export. Floor at 50% catches
        // a regression to the pre-expansion ~24% baseline while leaving
        // headroom for future exports that pick up new niche names.
        XCTAssertGreaterThan(result.nameMatchRate, 0.50, "name match rate dropped below 50% (\(result.nameMatchRate)) — alias coverage regressed below the Phase 3.5 baseline?")
        XCTAssertLessThan(Double(result.errors.count) / Double(max(result.totalRows, 1)), 0.05,
                          "more than 5% of rows failed to parse — schema drift?")
    }

    /// The path from a real export to a weight suggestion: names resolve,
    /// the pounds-in-kg-mode era is converted, and the proven-strength
    /// estimate never exceeds what the lifter did recently.
    func testRealExportFeedsProvenStrength() throws {
        guard let url = locateCSV() else {
            throw XCTSkip("no real Fitbod export on this machine")
        }
        let csv = try String(contentsOf: url, encoding: .utf8)
        let coach = CoachDatabase.shared
        let parsed = FitbodCSVParser.parse(csv, source: .fitbodCSV) { coach.exerciseId(forImportName: $0) }
        let (sets, reports) = ImportUnitCorrection.apply(parsed.sets)

        let weighted = sets.filter { ($0.weight ?? 0) > 0 }
        let weightedMatch = Double(weighted.filter { $0.exerciseId != nil }.count) / Double(max(weighted.count, 1))
        let allMatch = Double(sets.filter { $0.exerciseId != nil }.count) / Double(max(sets.count, 1))
        XCTAssertGreaterThanOrEqual(weightedMatch, 0.90, "weighted sets matched: \(weightedMatch)")
        XCTAssertGreaterThanOrEqual(allMatch, 0.85, "all sets matched: \(allMatch)")

        let kgToLb = 1 / ImportUnitCorrection.kgPerLb
        let newest = sets.map(\.performedAt).max() ?? Date()
        let recentCut = Calendar.current.date(byAdding: .month, value: -6, to: newest)!
        var lines = ["unit corrections: " + reports.map { "\($0.correctedSets) sets \($0.from) → \($0.through)" }.joined(separator: "; "),
                     String(format: "matched: weighted %.1f%%, all %.1f%%", weightedMatch * 100, allMatch * 100)]
        let byExercise = Dictionary(grouping: weighted.filter { $0.exerciseId != nil }, by: { $0.exerciseId! })
        for (id, rows) in byExercise.sorted(by: { $0.value.count > $1.value.count }).prefix(12) {
            let evidence = rows.compactMap { s -> ProvenStrength.Evidence? in
                guard let kg = s.weight, let r = s.reps else { return nil }
                return .init(date: s.performedAt, weightLb: kg * kgToLb, reps: r)
            }
            guard let est = ProvenStrength.estimate(evidence, now: newest) else { continue }
            let estimate = StrengthStandards.epley1RM(weight: est.weight, reps: est.reps)
            let recentBest = evidence.filter { $0.date >= recentCut && ProvenStrength.repRange.contains($0.reps) }
                .map { StrengthStandards.epley1RM(weight: $0.weightLb, reps: $0.reps) }.max()
            let peak = evidence.filter { ProvenStrength.repRange.contains($0.reps) }
                .map { StrengthStandards.epley1RM(weight: $0.weightLb, reps: $0.reps) }.max() ?? 0
            let name = coach.exercise(id: id)?.name ?? "#\(id)"
            lines.append(String(format: "%@: estimate %.0f, recent best %@, all-time %.0f",
                                name, estimate, recentBest.map { String(format: "%.0f", $0) } ?? "—", peak))
            if let recentBest {
                XCTAssertLessThanOrEqual(estimate, recentBest + 0.01, "\(name) estimate above the last 6 months")
            }
        }

        let profile = HistoryProfile.build(sessions: [], imported: sets, now: newest)
        let audit = profile.audit
        lines.append("history check: \(audit.outlierSets) outliers, \(audit.impossibleSets) impossible, \(audit.duplicateBlocks) duplicate blocks, \(audit.layoffs.count) layoffs")
        for f in audit.flags.prefix(10) { lines.append("  flag \(f.exercise) \(f.date) \(Int(f.weightLb))x\(f.reps) \(f.reason)") }
        for name in ["Barbell Back Squat", "Lat Pulldown (Cable)", "Dumbbell Curl", "Barbell Bench Press"] {
            if let p = profile.profile(forExerciseNamed: name) {
                lines.append("  \(name): step \(p.typicalStepLb.map { "\($0)" } ?? "—"), trend \(p.trend), plateau \(p.plateau)")
            }
        }

        if url.lastPathComponent == "WorkoutExport.csv" {
            XCTAssertTrue((1...20).contains(audit.outlierSets), "outliers: \(audit.outlierSets)")
            XCTAssertGreaterThanOrEqual(audit.duplicateBlocks, 1)
            // 11, not the 12 a weighted-sets-only count gives: one gap holds a
            // bodyweight-only workout, which is still training.
            XCTAssertEqual(audit.layoffs.count, 11)
            for name in ["Barbell Back Squat", "Lat Pulldown (Cable)"] {
                XCTAssertEqual(profile.profile(forExerciseNamed: name)?.typicalStepLb, 5, name)
            }
            XCTAssertNotEqual(profile.profile(forExerciseNamed: "Barbell Back Squat")?.trend, .unknown)
            // A 10-rep last session against a 5-rep row remaps through the
            // estimate and never lands above the recent best mapped to 5.
            if let squat = profile.profile(forExerciseNamed: "Barbell Back Squat"), let est = squat.estimate {
                let tenAt = (est.weight * (1 + Double(est.reps) / 30) / (1 + 10.0 / 30) / 5).rounded() * 5
                let prev = (1...3).map { LoggedSet(num: $0, weight: "\(tenAt)", reps: "10", rpe: "", done: true) }
                let r = ProgressionSuggestion.suggest(prevSets: prev, targetReps: 5, exerciseName: "Barbell Back Squat",
                                                      unit: "lbs", profile: squat)
                XCTAssertEqual(r?.basis, .repRemap)
                let recentBestAt5 = squat.recentBests.map(\.e1rm).max().map { $0 / (1 + 5.0 / 30) } ?? 0
                XCTAssertLessThanOrEqual(r?.suggestedWeight ?? .infinity, recentBestAt5 + 0.01)
                lines.append("  squat 10 reps at \(tenAt) -> today 5 reps: \(r?.suggestedWeight ?? 0) lb (\(r?.label ?? ""))")
            }
            // Bench has only 3 workouts in its last 26 weeks: too few to call.
            XCTAssertEqual(profile.profile(forExerciseNamed: "Barbell Bench Press")?.trend, .unknown)
            // The 2016-2026 export: kg mode with pound numbers until late 2017.
            XCTAssertFalse(reports.isEmpty, "the pre-2018 era should be detected")
            let bench2017 = sets.filter {
                $0.exerciseNameRaw == "Barbell Bench Press" && $0.performedAt < Date(timeIntervalSince1970: 1_514_764_800)
            }.compactMap { s -> Double? in
                guard let kg = s.weight, let r = s.reps, ProvenStrength.repRange.contains(r) else { return nil }
                return StrengthStandards.epley1RM(weight: kg * kgToLb, reps: r)
            }.max() ?? 0
            XCTAssertLessThan(bench2017, 230, "2017 bench should read as pounds, not 2.2x")
        }
        let report = lines.joined(separator: "\n")
        print("--- proven strength from real export ---\n" + report)
        add(XCTAttachment(string: report))
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

    func testRealExportBuildsHistorySessions() throws {
        guard let url = locateCSV() else {
            throw XCTSkip("no real Fitbod export on this machine")
        }
        let csv = try String(contentsOf: url, encoding: .utf8)
        let coach = CoachDatabase.shared
        let parsed = FitbodCSVParser.parse(csv, source: .fitbodCSV) { coach.exerciseId(forImportName: $0) }
        let (sets, _) = ImportUnitCorrection.apply(parsed.sets)
        let flagged = Set(HistoryProfile.build(sessions: [], imported: sets, now: Date()).audit.flags.map(\.id))

        let started = Date()
        let sessions = ImportedHistorySessions.build(imported: sets, excluded: flagged, usesImperial: true)
        let seconds = Date().timeIntervalSince(started)
        let bests = sessions.flatMap(\.exercises).filter { $0.name == "Barbell Bench Press" }
            .flatMap(\.sets).compactMap(\.weightValue)
        let note = String(format: "history sessions: %d built in %.3f s; bench best %.1f lb",
                          sessions.count, seconds, bests.max() ?? 0)
        print(note)
        add(XCTAttachment(string: note))
        XCTAssertLessThan(seconds, 1.0)
        XCTAssertFalse(sessions.isEmpty)
        // The 397 lb bench from the kg-mode era is corrected, then the outlier rule holds the rest.
        XCTAssertLessThan(bests.max() ?? 0, 300)
    }

    /// The personal detraining rate on a real ten-year history: measured
    /// from its comebacks, and inside the clamp whatever it measures.
    func testRealExportMeasuresADetrainingRate() throws {
        guard let url = locateCSV() else {
            throw XCTSkip("no real Fitbod export on this machine")
        }
        let csv = try String(contentsOf: url, encoding: .utf8)
        let coach = CoachDatabase.shared
        let parsed = FitbodCSVParser.parse(csv, source: .fitbodCSV) { coach.exerciseId(forImportName: $0) }
        let (sets, _) = ImportUnitCorrection.apply(parsed.sets)
        let started = Date()
        let d = HistoryProfile.build(sessions: [], imported: sets, now: Date()).detraining
        let note = String(format: "detraining: %d breaks, %d pairs, measured %.4f, used %.4f, personal %@ (profile %.3f s)",
                          d.breaks, d.pairs, d.measured ?? -1, d.perWeek, d.isPersonal ? "yes" : "no",
                          Date().timeIntervalSince(started))
        print(note)
        add(XCTAttachment(string: note))
        XCTAssertTrue(ProvenStrength.DetrainingRate.range.contains(d.perWeek) || d.perWeek == ProvenStrength.discountPerWeek)
        XCTAssertGreaterThan(d.pairs, 0, "a ten-year history with breaks should yield comeback pairs")
    }
}
