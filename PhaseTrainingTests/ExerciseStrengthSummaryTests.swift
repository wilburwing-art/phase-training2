import XCTest
@testable import PhaseTraining

/// Every string on the exercise sheet's "Your strength" card.
final class ExerciseStrengthSummaryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    private func profile(workouts: Int = 3, lastDaysAgo: Double = 2, trend: HistoryProfile.Trend = .unknown,
                         plateau: Bool = false, step: Double? = 5, excluded: Int = 0,
                         points: Int = 3) -> HistoryProfile.ExerciseProfile {
        let last = daysAgo(lastDaysAgo)
        return .init(name: "Bench", estimate: PriorBest(weight: 135, reps: 10, date: last),   // e1RM 180
                     trend: trend, plateau: plateau, typicalStepLb: step, lastTrained: last,
                     bestE1RM: 204, bestDate: daysAgo(400), workouts: workouts, excludedSets: excluded,
                     latestBest: .init(date: last, weightLb: 135, reps: 10),
                     recentBests: (0..<points).map { .init(date: daysAgo(lastDaysAgo + Double(points - $0) * 7), e1rm: 170 + Double($0)) })
    }

    private func summary(_ p: HistoryProfile.ExerciseProfile, reps: String? = "8",
                         imperial: Bool = true) -> ExerciseStrengthSummary? {
        ExerciseStrengthSummary(profile: p, defaultReps: reps, usesImperial: imperial, now: now)
    }

    func test_estimateAndBasis() throws {
        let s = try XCTUnwrap(summary(profile()))
        XCTAssertEqual(s.estimate, "180 lb")
        XCTAssertTrue(s.basis.hasPrefix("Based on your last 3 workouts · latest 135 lb × 10 on "), s.basis)
        XCTAssertTrue(try XCTUnwrap(summary(profile(workouts: 1))).basis.hasPrefix("Based on your last workout"))
        XCTAssertTrue(try XCTUnwrap(summary(profile(workouts: 2))).basis.hasPrefix("Based on your last 2 workouts"))
        XCTAssertTrue(try XCTUnwrap(summary(profile(workouts: 9))).basis.hasPrefix("Based on your last 3 workouts"))
    }

    func test_layoffLineOnlyAfterFourWeeks() throws {
        XCTAssertNil(try XCTUnwrap(summary(profile(lastDaysAgo: 20))).layoff)
        XCTAssertEqual(try XCTUnwrap(summary(profile(lastDaysAgo: 287))).layoff,
                       "Lowered for 41 weeks off. It builds back as you log.")
    }

    func test_forRepsMatchesTheLogPill_andHidesForNonNumericReps() throws {
        let s = try XCTUnwrap(summary(profile(), reps: "6-10"))
        let pill = try XCTUnwrap(ProgressionSuggestion.fromHistory(PriorBest(weight: 135, reps: 10, date: now),
                                                                   targetReps: 8, unit: "lbs"))
        XCTAssertEqual(s.forReps, "For 8 reps: about \(pill.suggestedWeightString) lb")
        XCTAssertNil(try XCTUnwrap(summary(profile(), reps: "AMRAP")).forReps)
        XCTAssertNil(try XCTUnwrap(summary(profile(), reps: nil)).forReps)
    }

    func test_trendWording() throws {
        XCTAssertEqual(summary(profile(trend: .rising(6.58)))?.trend, "Rising 6.6% a month")
        XCTAssertEqual(summary(profile(trend: .falling(-1.53)))?.trend, "Falling 1.5% a month")
        XCTAssertEqual(summary(profile(trend: .flat(0.2), plateau: true))?.trend, "Flat over your recent workouts (plateau)")
        XCTAssertEqual(summary(profile(trend: .flat(0.2)))?.trend, "Holding steady")
        XCTAssertEqual(summary(profile())?.trend, "Not enough recent workouts to call a trend")
    }

    func test_kgRendering() throws {
        let s = try XCTUnwrap(summary(profile(), imperial: false))
        XCTAssertEqual(s.estimate, "81.5 kg")   // 180 lb = 81.65 kg -> nearest 0.5
        XCTAssertEqual(s.usualJump, "2.5 kg")   // 5 lb = 2.27 kg -> 2.5
        XCTAssertTrue(s.forReps?.hasSuffix(" kg") ?? false)
        XCTAssertEqual(s.chart.first?.value ?? 0, BodyMetrics.lbToKg(170), accuracy: 0.01)
    }

    func test_bestJumpAndExcluded() throws {
        let s = try XCTUnwrap(summary(profile(excluded: 1)))
        XCTAssertTrue(s.best.hasPrefix("Best 204 lb est. max · "), s.best)
        XCTAssertEqual(s.usualJump, "5 lb")
        XCTAssertEqual(s.excluded, "1 set left out as a likely typo")
        XCTAssertEqual(summary(profile(excluded: 3))?.excluded, "3 sets left out as likely typos")
        XCTAssertNil(summary(profile())?.excluded)
        XCTAssertNil(summary(profile(step: nil))?.usualJump)
    }

    func test_chartNeedsThreePoints_oldestFirst() throws {
        XCTAssertTrue(try XCTUnwrap(summary(profile(points: 2))).chart.isEmpty)
        let chart = try XCTUnwrap(summary(profile(points: 5))).chart
        XCTAssertEqual(chart.count, 5)
        XCTAssertEqual(chart.map(\.date), chart.map(\.date).sorted())
    }

    func test_noEstimate_noCard() {
        let p = profile()
        let bodyweight = HistoryProfile.ExerciseProfile(
            name: p.name, estimate: nil, trend: p.trend, plateau: false, typicalStepLb: nil,
            lastTrained: p.lastTrained, bestE1RM: 0, bestDate: p.bestDate, workouts: 1, excludedSets: 0,
            latestBest: p.latestBest, recentBests: [])
        XCTAssertNil(summary(bodyweight))
    }
}
