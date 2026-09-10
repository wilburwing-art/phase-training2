// AutoregulationTests.swift — PR 10B of the weekly-coach roadmap.
//
// Coverage:
//   - classify(): amplify at 2 full-completion target-hit attempts,
//     soften at sub-80% mean across the window, neutral otherwise,
//     neutral with < window attempts.
//   - buildAttemptHistory(): per-session attempt extraction from
//     SavedSession rows (completion ratio, warmup exclusion, ordering).
//   - progressiveOverloadHint integration: soften drops the target,
//     amplify raises it, stepDown is never overridden.
//
// Glue mirrors GeneratorContext tests' SavedSession fixtures.

import XCTest
@testable import PhaseTraining

final class AutoregulationTests: XCTestCase {

    // MARK: - Fixtures

    private func attempt(completion: Double, reps: Int, targetReps: Int) -> AutoregulationEngine.Attempt {
        AutoregulationEngine.Attempt(completion: completion, reps: reps, targetReps: targetReps)
    }

    private func session(date: Date, exercise: String, targetSets: Int, targetReps: Int,
                         doneSets: Int, weight: Double, reps: Int) -> SavedSession {
        let sets = (0..<targetSets).map { i in
            LoggedSet(num: i + 1, weight: String(Int(weight)), reps: String(reps),
                      rpe: "", done: i < doneSets)
        }
        let ex = LoggedExercise(
            id: "ex-1", name: exercise, type: nil, unit: "lbs",
            targetSets: targetSets, targetReps: targetReps, rest: 90,
            sets: sets, prevSets: []
        )
        return SavedSession(
            templateId: "t", name: "Push", category: "lift",
            startTime: date, exercises: [ex], feel: nil, note: nil,
            endTime: date.addingTimeInterval(3_600), duration: 3_600
        )
    }

    // MARK: - classify

    func test_classify_amplifyAtTwoFullTargetHitAttempts() {
        let out = AutoregulationEngine.classify([
            attempt(completion: 1.0, reps: 8, targetReps: 8),
            attempt(completion: 1.0, reps: 8, targetReps: 8),
        ])
        XCTAssertEqual(out, .amplify)
    }

    func test_classify_softenWhenMeanCompletionUnderBar() {
        // Mean 0.625 < 0.80.
        let out = AutoregulationEngine.classify([
            attempt(completion: 0.5, reps: 6, targetReps: 8),
            attempt(completion: 0.75, reps: 7, targetReps: 8),
        ])
        XCTAssertEqual(out, .soften)
    }

    func test_classify_neutralWhenOneGoodOneBlown() {
        // Mean (1.0 + 0.6)/2 = 0.8 → NOT under the bar → neutral.
        // This is the deliberate mean-vs-min choice: one blown session
        // among decent ones shouldn't trigger; the miss path already has
        // ProgressionDecision.stepDown.
        let out = AutoregulationEngine.classify([
            attempt(completion: 0.6, reps: 5, targetReps: 8),
            attempt(completion: 1.0, reps: 8, targetReps: 8),
        ])
        XCTAssertEqual(out, .neutral)
    }

    func test_classify_neutralWithFewerThanWindowAttempts() {
        let out = AutoregulationEngine.classify([
            attempt(completion: 0.3, reps: 4, targetReps: 8),
        ])
        XCTAssertEqual(out, .neutral)
    }

    func test_classify_emptyHistoryIsNeutral() {
        XCTAssertEqual(AutoregulationEngine.classify([]), .neutral)
    }

    func test_classify_amplifyRequiresTargetRepsHit() {
        // Full completion but reps below target → no amplify.
        let out = AutoregulationEngine.classify([
            attempt(completion: 1.0, reps: 6, targetReps: 8),
            attempt(completion: 1.0, reps: 6, targetReps: 8),
        ])
        XCTAssertEqual(out, .soften == out ? .soften : .neutral)
    }

    // MARK: - buildAttemptHistory

    func test_buildAttemptHistory_extractsPerSessionAttempts() {
        let d1 = Date(timeIntervalSince1970: 1_760_000_000)
        let d2 = d1.addingTimeInterval(3 * 86_400)
        let s1 = session(date: d1, exercise: "Bench Press", targetSets: 4,
                         targetReps: 8, doneSets: 3, weight: 185, reps: 8)
        let s2 = session(date: d2, exercise: "Bench Press", targetSets: 4,
                         targetReps: 8, doneSets: 4, weight: 185, reps: 8)
        let hist = GeneratorContext.buildAttemptHistory(sessions: [s1, s2], now: d2)
        let attempts = hist["bench press"] ?? []
        XCTAssertEqual(attempts.count, 2)
        // Newest first.
        XCTAssertEqual(attempts.first?.completion ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(attempts.last?.completion ?? 0, 0.75, accuracy: 0.0001)
    }

    func test_buildAttemptHistory_excludesWarmups() {
        let d1 = Date(timeIntervalSince1970: 1_760_000_000)
        var s = session(date: d1, exercise: "Squat", targetSets: 3,
                        targetReps: 5, doneSets: 2, weight: 225, reps: 5)
        // A done warmup set must not count toward completion.
        s.exercises[0].sets.append(LoggedSet(num: 9, weight: "135", reps: "5",
                                             rpe: "", done: true, isWarmup: true))
        let hist = GeneratorContext.buildAttemptHistory(sessions: [s], now: d1)
        XCTAssertEqual(hist["squat"]?.first?.completion ?? 0, 2.0 / 3.0, accuracy: 0.0001)
    }

    func test_buildAttemptHistory_respectsFourWeekWindow() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let old = now.addingTimeInterval(-5 * 7 * 86_400) // 5 weeks back
        let recent = now.addingTimeInterval(-3 * 86_400)
        let sOld = session(date: old, exercise: "Deadlift", targetSets: 3,
                           targetReps: 5, doneSets: 3, weight: 315, reps: 5)
        let sNew = session(date: recent, exercise: "Deadlift", targetSets: 3,
                           targetReps: 5, doneSets: 3, weight: 315, reps: 5)
        let hist = GeneratorContext.buildAttemptHistory(sessions: [sOld, sNew], now: now)
        XCTAssertEqual(hist["deadlift"]?.count, 1)
    }

    // MARK: - progressiveOverloadHint integration

    /// Build a context with priorBest + attemptHistory, then compare hints.
    private func hint(prior: PriorBest, history: [AutoregulationEngine.Attempt],
                      last: LastAttempt? = nil) throws -> String? {
        var ctx = GeneratorContext.empty
        guard let exercise = ExerciseLookupCache.shared.exercise(forName: "Bench Press")
            ?? CoachDatabase.shared.listExercises().first(where: {
                $0.name.lowercased().contains("bench")
            }) else {
            // Catalog unavailable in this environment — the integration
            // path can't resolve an Exercise row; skip rather than fake.
            throw XCTSkip("Bench Press not resolvable in coach.db")
        }
        ExerciseKey.store(prior, name: exercise.name, into: &ctx.priorBest)
        if let last { ExerciseKey.store(last, name: exercise.name, into: &ctx.lastAttempt) }
        // History keyed the same way production keys it — via
        // ExerciseKey.store against the RESOLVED exercise's display name,
        // not the fixture's shorthand.
        ExerciseKey.store(history, name: exercise.name, into: &ctx.attemptHistory)
        return WorkoutGenerator.progressiveOverloadHint(
            for: exercise, context: ctx, memory: TrainingMemory(),
            prescribedReps: "8"
        )
    }

    private func lb(from hint: String?) -> Double? {
        guard let hint else { return nil }
        let digits = hint.compactMap { c -> Character? in
            c.isNumber || c == "." ? c : nil
        }
        return Double(String(digits))
    }

    func test_hint_softenReducesTarget() throws {
        // Neutral run: full history window at/above the completion bar
        // → no adjustment.
        let neutral = try hint(
            prior: PriorBest(weight: 200, reps: 8, date: Date()),
            history: [
                attempt(completion: 1.0, reps: 8, targetReps: 8),
                attempt(completion: 1.0, reps: 8, targetReps: 8),
            ])
        // Soften run: same prior (identical base decision path) but
        // sub-bar completion → ×0.95 on the target.
        let softened = try hint(
            prior: PriorBest(weight: 200, reps: 8, date: Date()),
            history: [
                attempt(completion: 0.5, reps: 6, targetReps: 8),
                attempt(completion: 0.5, reps: 6, targetReps: 8),
            ])
        guard let n = lb(from: neutral), let s = lb(from: softened) else {
            return XCTFail("expected numeric hints, got \(neutral ?? "nil") / \(softened ?? "nil")")
        }
        XCTAssertLessThan(s, n, "soften must reduce the target load")
    }

    func test_hint_amplifyRaisesTarget() throws {
        // Neutral: full completion but reps above target doesn't matter —
        // 0.9 completion keeps this BELOW the amplify bar (needs ≥1.0).
        let neutral = try hint(
            prior: PriorBest(weight: 200, reps: 8, date: Date()),
            history: [
                attempt(completion: 0.9, reps: 8, targetReps: 8),
                attempt(completion: 0.9, reps: 8, targetReps: 8),
            ])
        // Amplify: 2 attempts at full completion hitting target reps.
        let amplified = try hint(
            prior: PriorBest(weight: 200, reps: 8, date: Date()),
            history: [
                attempt(completion: 1.0, reps: 8, targetReps: 8),
                attempt(completion: 1.0, reps: 8, targetReps: 8),
            ])
        guard let n = lb(from: neutral), let a = lb(from: amplified) else {
            return XCTFail("expected numeric hints, got \(neutral ?? "nil") / \(amplified ?? "nil")")
        }
        XCTAssertEqual(a - n, 5.0, accuracy: 2.6,
                       "amplify adds +5 lb; 2.5-lb rounding absorbs fractions")
    }

    func test_hint_stepDownSurvivesAmplifyHistory() throws {
        // Last attempt at prior weight, badly missed reps → stepDown.
        // Even with an amplify-qualifying older history, the target must
        // NOT be raised above the stepDown value.
        let prior = PriorBest(weight: 200, reps: 8, date: Date())
        let last = LastAttempt(weight: 200, reps: 4, targetReps: 8, date: Date())
        let withAmplify = try hint(
            prior: prior, history: [
                attempt(completion: 1.0, reps: 8, targetReps: 8),
                attempt(completion: 1.0, reps: 8, targetReps: 8),
            ], last: last)
        let without = try hint(prior: prior, history: [], last: last)
        XCTAssertEqual(lb(from: withAmplify), lb(from: without),
                       "amplify must not override a stepDown")
    }
}
