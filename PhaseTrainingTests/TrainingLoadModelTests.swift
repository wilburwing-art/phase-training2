// TrainingLoadModelTests.swift — B1a shadow twin.
//
// Model math against hand-computed values, prediction using only earlier
// days, the fit recovering known parameters from synthetic training, the
// frozen prediction on a recorded outcome, the scorecard, unit conversion,
// and an opt-in replay over the owner's real Fitbod history.

import XCTest
@testable import PhaseTraining

final class TrainingLoadModelTests: XCTestCase {

    private let day0 = Date(timeIntervalSince1970: 1_700_006_400) // a UTC midnight
    private func at(_ day: Int, hour: Double = 17) -> Date {
        day0.addingTimeInterval(Double(day) * 86_400 + hour * 3600)
    }
    private let onePattern: (String) -> String = { _ in "squat" }

    // MARK: - Math

    func test_singleImpulse_decaysWithEachTimeConstant() {
        let sets = [LoadSet(date: at(0), exercise: "Air Squat", weight: 0, reps: 10)]
        let m = TrainingLoadModel(sets: sets, patternFor: onePattern)
        let base = TrainingLoadModel.day(day0)
        let s = m.state(pattern: "squat", day: base + 10)
        // One day of impulse normalises to exactly 1.
        XCTAssertEqual(s.fitness, exp(-10.0 / 42), accuracy: 1e-9)
        XCTAssertEqual(s.fatigue, exp(-10.0 / 7), accuracy: 1e-9)
        XCTAssertEqual(s.performance, exp(-10.0 / 42) - 2 * exp(-10.0 / 7), accuracy: 1e-9)
    }

    func test_stateExcludesTheDayItself() {
        let sets = [LoadSet(date: at(0), exercise: "Squat", weight: 200, reps: 5)]
        let m = TrainingLoadModel(sets: sets, patternFor: onePattern)
        XCTAssertEqual(m.state(pattern: "squat", day: TrainingLoadModel.day(day0)).fitness, 0)
    }

    func test_gainZero_isExactlyTheLastValueBaseline() throws {
        let sets = [LoadSet(date: at(0), exercise: "Squat", weight: 200, reps: 5),
                    LoadSet(date: at(3), exercise: "Squat", weight: 210, reps: 5)]
        var p = TwinParams.defaults; p.gain = 0
        let m = TrainingLoadModel(sets: sets, params: p, patternFor: onePattern)
        let pred = try XCTUnwrap(m.predict(exercise: "squat", day: TrainingLoadModel.day(day0) + 7))
        XCTAssertEqual(pred.predicted, pred.baseline)
        XCTAssertEqual(pred.baseline, StrengthStandards.epley1RM(weight: 210, reps: 5), accuracy: 1e-9)
    }

    func test_prediction_ignoresSetsOnTheDayBeingPredicted() throws {
        let base = TrainingLoadModel.day(day0)
        let before = [LoadSet(date: at(0), exercise: "Squat", weight: 200, reps: 5)]
        let sameDay = before + [LoadSet(date: at(5), exercise: "Squat", weight: 400, reps: 5)]
        let a = try XCTUnwrap(TrainingLoadModel(sets: before, patternFor: onePattern).predict(exercise: "Squat", day: base + 5))
        let b = try XCTUnwrap(TrainingLoadModel(sets: sameDay, patternFor: onePattern).predict(exercise: "Squat", day: base + 5))
        XCTAssertEqual(a, b)
    }

    func test_noHistory_meansNoPrediction_andNeutralReadiness() {
        let m = TrainingLoadModel(sets: [], patternFor: onePattern)
        XCTAssertNil(m.predict(exercise: "Squat", day: 100))
        XCTAssertEqual(m.readiness(exercises: ["Squat"], day: 100), 0.5)
    }

    // MARK: - Fit recovers known parameters

    /// Synthetic lifter whose every top set is exactly what the model with
    /// `truth` predicts, with a varying weekly schedule so the time constants
    /// are identifiable. The fit must pick `truth` out of the grid.
    func test_fit_recoversTheGeneratingParameters() {
        let truth = TwinParams(tauFitness: 42, tauFatigue: 7, fatigueWeight: 2, gain: 0.04)
        var sets: [LoadSet] = [LoadSet(date: at(0), exercise: "Squat", weight: 200 / (1 + 5.0 / 30), reps: 5)]
        let pattern: [Int] = [1, 2, 2, 3, 1, 4, 2, 1, 3, 2]   // gaps between sessions
        var day = 0, i = 0
        while day < 240 {
            day += pattern[i % pattern.count]; i += 1
            let model = TrainingLoadModel(sets: sets, params: truth, patternFor: onePattern)
            let target = model.predict(exercise: "Squat", day: TrainingLoadModel.day(day0) + day)!.predicted
            let w = target / (1 + 5.0 / 30)
            for _ in 0..<(i % 3 == 0 ? 5 : 3) {
                sets.append(LoadSet(date: at(day), exercise: "Squat", weight: w, reps: 5))
            }
        }
        let base = TrainingLoadModel.day(day0)
        let fitted = TrainingLoadModel.fit(sets: sets, calibration: (base + 100)...(base + 220),
                                           patternFor: onePattern)
        XCTAssertEqual(fitted, truth)
        let score = TrainingLoadModel(sets: sets, params: fitted, patternFor: onePattern).score(days: (base + 100)...(base + 240))
        XCTAssertGreaterThan(score.n, 20)
        XCTAssertEqual(score.maeModel, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(score.maeBaseline, 0)
    }

    func test_fit_withTooFewPairs_returnsDefaults() {
        let sets = [LoadSet(date: at(0), exercise: "Squat", weight: 200, reps: 5),
                    LoadSet(date: at(2), exercise: "Squat", weight: 205, reps: 5)]
        let base = TrainingLoadModel.day(day0)
        XCTAssertEqual(TrainingLoadModel.fit(sets: sets, calibration: base...(base + 10), patternFor: onePattern),
                       .defaults)
    }

    // MARK: - Inputs

    func test_importedKilograms_becomePounds() throws {
        let row = ImportedSet(id: "x", source: .fitbodCSV, exerciseId: nil, exerciseNameRaw: "Squat",
                              performedAt: at(0), setNum: 1, weight: 100, reps: 5, rir: nil, rpe: nil)
        let s = try XCTUnwrap(TwinInputs.sets(from: [row]).first)
        XCTAssertEqual(s.weight, 220.462, accuracy: 1e-6)
    }

    // MARK: - Frozen on the outcome

    private func saved(day: Int, weight: String, reps: String = "5", name: String = "Barbell Back Squat") -> SavedSession {
        let ex = LoggedExercise(id: "gex-a", name: name, type: nil, unit: "lbs", targetSets: 3, targetReps: 5, rest: 120,
                                sets: (1...3).map { LoggedSet(num: $0, weight: weight, reps: reps, rpe: "", done: true) },
                                prevSets: [])
        return SavedSession(templateId: "gen-x", name: "Lower", category: "Generated", startTime: at(day),
                            exercises: [ex], feel: nil, note: nil, endTime: at(day, hour: 18), duration: 3600)
    }

    func test_recordOutcome_freezesATwinPrediction_fromEarlierHistoryOnly() throws {
        let suite = "twin-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let sessions = SessionStore(defaults: d, userDB: UserDatabase(path: ":memory:"))
        let plan = PlanStore(defaults: d, today: at(10))
        plan.sessionStore = sessions
        plan.importedSetsProvider = { [] }
        // Set directly: saveCompleted stamps real wall-clock times.
        sessions.savedSessions = [(0, "200"), (3, "205"), (7, "210")].map { saved(day: $0.0, weight: $0.1) }
        let today = saved(day: 10, weight: "215")
        plan.recordOutcome(for: today, abandoned: false, now: at(10))
        let twin = try XCTUnwrap(plan.dayOutcomes.first?.twin)
        let row = try XCTUnwrap(twin.exercises.first)
        XCTAssertEqual(row.actual ?? 0, StrengthStandards.epley1RM(weight: 215, reps: 5), accuracy: 1e-9)
        XCTAssertNotEqual(row.baseline, row.actual, "the baseline must come from an earlier session")
    }

    func test_scorecard_comparesModelAndBaseline() {
        func o(_ kind: DayOutcomeKind, pred: Double, base: Double, actual: Double?, r: Double) -> DayOutcome {
            var x = DayOutcome(sessionId: pred + base, date: at(0), kind: kind, plannedDayKind: .lift,
                               plannedTitle: nil, plannedExercises: [], plannedWorkingSets: 0, plannedMinutes: nil,
                               targetMinutes: nil, loggedTemplateId: "", loggedTitle: "", loggedExercises: [],
                               completedWorkingSets: 0, durationMinutes: 0, swaps: [], dropped: [], added: [],
                               recordedAt: at(0))
            x.twin = TwinPrediction(params: .defaults, readiness: r,
                                    exercises: [TwinExercisePrediction(exercise: "S", predicted: pred, baseline: base, actual: actual)])
            return x
        }
        let card = TwinScorecard.from([o(.asPlanned, pred: 100, base: 90, actual: 102, r: 0.7),
                                       o(.modified, pred: 100, base: 110, actual: 104, r: 0.4),
                                       o(.abandoned, pred: 1, base: 1, actual: nil, r: 0.2)])
        XCTAssertEqual(card.pairs.n, 2)
        XCTAssertEqual(card.pairs.maeModel, 3, accuracy: 1e-9)      // (2 + 4) / 2
        XCTAssertEqual(card.pairs.maeBaseline, 9, accuracy: 1e-9)   // (12 + 6) / 2
        XCTAssertEqual(card.readinessByKind[.abandoned], 0.2)
    }

    // MARK: - Replay over real history (opt-in)

    /// Reads a Fitbod export if one exists on this Mac and prints the
    /// go/no-go report. Read-only; never touches the app's database.
    func test_replay_realFitbodHistory() throws {
        let env = ProcessInfo.processInfo.environment
        let candidates = [env["TWIN_FITBOD_CSV"], env["TEST_RUNNER_TWIN_FITBOD_CSV"],
                          "/Users/wilburpyn/repos/workout-plan/data/fitbod-history.csv"].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw XCTSkip("No Fitbod export found; set TWIN_FITBOD_CSV to run the real-history replay.")
        }
        let csv = try String(contentsOfFile: path, encoding: .utf8)
        let parsed = FitbodCSVParser.parse(csv, nameResolver: { ExerciseLookupCache.shared.exerciseID(forName: $0) })
        let sets = TwinInputs.sets(from: parsed.sets)
        XCTAssertGreaterThan(sets.count, 1000, "export parsed to too few sets to judge anything")
        let report = try XCTUnwrap(TwinReplay.run(sets: sets))
        print("""
        TWIN-REPLAY sets=\(sets.count) trainingDays=\(report.trainingDays) holdoutPairs=\(report.holdout.n)
        TWIN-REPLAY fitted=\(report.fitted)
        TWIN-REPLAY maeFitted=\(String(format: "%.2f", report.holdout.maeModel)) \
        maeDefaults=\(String(format: "%.2f", report.holdoutWithDefaults.maeModel)) \
        maeBaseline=\(String(format: "%.2f", report.holdout.maeBaseline)) \
        improvement=\(String(format: "%+.2f%%", report.holdout.improvement * 100)) \
        verdict=\(report.holdout.improvement > 0 ? "GO" : "NO-GO")
        """)
        XCTAssertGreaterThan(report.holdout.n, 20, "holdout too thin to judge")
    }
}
