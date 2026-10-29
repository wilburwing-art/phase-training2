import XCTest
@testable import PhaseTraining

/// Cleaning (typos, duplicates, impossible values) and per-exercise analysis
/// (trend, plateau, typical step, layoffs) over native + imported history.
final class HistoryProfileTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    /// One native session of one exercise; each pair is (lb, reps).
    private func session(_ name: String, _ d: Double, _ sets: [(Double, Int)]) -> SavedSession {
        let logged = sets.enumerated().map { i, s in
            LoggedSet(num: i + 1, weight: s.0.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(s.0))" : "\(s.0)",
                      reps: "\(s.1)", rpe: "", done: true)
        }
        return SavedSession(templateId: "t", name: name, category: "c", startTime: daysAgo(d),
                            exercises: [LoggedExercise(id: "e", name: name, type: nil, unit: "lbs", targetSets: sets.count,
                                                       targetReps: 5, rest: 90, sets: logged, prevSets: [])],
                            feel: nil, note: nil, endTime: daysAgo(d), duration: 1800)
    }

    private func build(_ sessions: [SavedSession], imported: [ImportedSet] = []) -> HistoryProfile {
        HistoryProfile.build(sessions: sessions, imported: imported, now: now)
    }

    // MARK: - Cleaning

    func test_aTypoSetIsLeftOut_andNeverMovesTheEstimate() throws {
        let typo = build([session("Zz Squat", 2, [(225, 5), (225, 5), (900, 5)])])
        let clean = build([session("Zz Squat", 2, [(225, 5), (225, 5)])])
        XCTAssertEqual(typo.audit.outlierSets, 1)
        XCTAssertEqual(typo.audit.flags.first?.weightLb, 900)
        let a = try XCTUnwrap(typo.profile(forExerciseNamed: "Zz Squat"))
        XCTAssertEqual(a.estimate, clean.profile(forExerciseNamed: "Zz Squat")?.estimate)
        XCTAssertEqual(a.excludedSets, 1)
    }

    func test_aPyramidOrDropSetIsNotFlagged() {
        let p = build([session("Zz Bench", 2, [(135, 10), (185, 8), (225, 5), (275, 2)]),
                       session("Zz Curl", 4, [(60, 10), (40, 12), (25, 15)])])
        XCTAssertTrue(p.audit.isClean)
    }

    func test_impossibleValuesAreLeftOut() {
        let p = build([session("Zz Row", 2, [(135, 8), (1600, 5)]), session("Zz Row", 9, [(135, 150)])])
        XCTAssertEqual(p.audit.impossibleSets, 2)
    }

    func test_theLaterCopyOfADuplicateWorkoutIsLeftOut() {
        let sets: [(Double, Int)] = [(100, 8), (110, 8), (120, 6)]
        let p = build([session("Zz Press", 2.0, sets), session("Zz Press", 2.4, sets), session("Zz Press", 9, sets)])
        XCTAssertEqual(p.audit.duplicateBlocks, 1, "the 9-days-apart repeat is a real workout")
        XCTAssertEqual(p.audit.flags.first.map { Calendar.current.isDate($0.date, inSameDayAs: daysAgo(2.0)) }, true)
        XCTAssertEqual(p.profile(forExerciseNamed: "Zz Press")?.workouts, 2)
    }

    func test_importedTypoIsCaughtLikeANativeOne() throws {
        guard let squat = CoachDatabase.shared.exerciseId(forImportName: "Back Squat") else { throw XCTSkip("no Back Squat") }
        let kg = { (lb: Double) in lb * ImportUnitCorrection.kgPerLb }
        let imported = [225.0, 225, 900].enumerated().map { i, lb in
            ImportedSet(id: "s\(i)", source: .fitbodCSV, exerciseId: squat, exerciseNameRaw: "Back Squat",
                        performedAt: daysAgo(3), setNum: i + 1, weight: kg(lb), reps: 5, rir: nil, rpe: nil)
        }
        let p = build([], imported: imported)
        XCTAssertEqual(p.audit.outlierSets, 1)
        let est = try XCTUnwrap(p.profile(forExerciseNamed: "Back Squat")?.estimate)
        XCTAssertEqual(est.weight, 225, accuracy: 0.5)
    }

    // MARK: - Analysis

    private func weekly(_ name: String, _ e1rms: [Double]) -> [SavedSession] {
        // Oldest first, one a week; reps 5 so weight = e1rm / (1 + 5/30).
        var out: [SavedSession] = []
        for (i, e) in e1rms.enumerated() {
            let days = Double(e1rms.count - i) * 7
            let weight: Double = e / (1 + 5.0 / 30)
            out.append(session(name, days, [(weight, 5)]))
        }
        return out
    }

    func test_trend_risingFlatFallingUnknown() {
        func trend(_ e: [Double]) -> HistoryProfile.Trend? { build(weekly("Zz Lift", e)).profile(forExerciseNamed: "Zz Lift")?.trend }
        guard case .rising(let up)? = trend([200, 204, 208, 212, 216, 220]) else { return XCTFail("rising") }
        XCTAssertGreaterThan(up, 1)
        guard case .flat? = trend([200, 201, 199, 200, 200, 201]) else { return XCTFail("flat") }
        guard case .falling? = trend([220, 214, 208, 202, 196]) else { return XCTFail("falling") }
        XCTAssertEqual(trend([200, 205, 210]), .unknown, "3 workouts is too few")
    }

    func test_plateauNeedsSixFlatWorkouts() {
        XCTAssertEqual(build(weekly("Zz Lift", [200, 201, 199, 200, 200, 201])).profile(forExerciseNamed: "Zz Lift")?.plateau, true)
        XCTAssertEqual(build(weekly("Zz Lift", [200, 201, 199, 200, 200])).profile(forExerciseNamed: "Zz Lift")?.plateau, false)
    }

    func test_typicalStep_isTheLiftersOwnJump() {
        let fives: [SavedSession] = (0..<6).map { i in
            let days = Double(60 - i * 7)
            let lb = Double(185 + i * 5)
            return session("Zz Squat", days, [(lb, 5)])
        }
        XCTAssertEqual(build(fives).profile(forExerciseNamed: "Zz Squat")?.typicalStepLb, 5)
        let fly: [SavedSession] = (0..<5).map { i in
            let days = Double(40 - i * 7)
            let lb = 20 + Double(i) * 2.5
            return session("Zz Fly", days, [(lb, 12)])
        }
        XCTAssertEqual(build(fly).profile(forExerciseNamed: "Zz Fly")?.typicalStepLb, 2.5)
        XCTAssertNil(build([session("Zz Once", 2, [(100, 5)])]).profile(forExerciseNamed: "Zz Once")?.typicalStepLb)
    }

    func test_bestAndLastTrained() throws {
        let p = try XCTUnwrap(build([session("Zz Dl", 30, [(315, 5)]), session("Zz Dl", 3, [(275, 5)])])
            .profile(forExerciseNamed: "Zz Dl"))
        XCTAssertEqual(p.bestE1RM, StrengthStandards.epley1RM(weight: 315, reps: 5), accuracy: 0.01)
        XCTAssertEqual(p.lastTrained, daysAgo(3))
    }

    func test_latestBestAndRecentBests() throws {
        var sessions: [SavedSession] = []
        for i in 0..<14 {
            let days = Double(100 - i * 7)
            let lb = Double(100 + i * 5)
            sessions.append(session("Zz Lift", days, [(lb, 5)]))
        }
        sessions.append(session("Zz Lift", 1, [(150, 3), (140, 8)]))   // 8 reps at 140 beats 3 at 150
        let p = try XCTUnwrap(build(sessions).profile(forExerciseNamed: "Zz Lift"))
        XCTAssertEqual(p.latestBest, HistoryProfile.SetRecord(date: daysAgo(1), weightLb: 140, reps: 8))
        XCTAssertEqual(p.recentBests.count, HistoryProfile.recentPoints)
        XCTAssertEqual(p.recentBests.last?.date, daysAgo(1))
        let dates: [Date] = p.recentBests.map { $0.date }
        XCTAssertEqual(dates, dates.sorted())
    }

    func test_layoffsOverEightWeeksAreListed() {
        let p = build([session("Zz A", 200, [(100, 5)]), session("Zz A", 100, [(100, 5)]), session("Zz A", 90, [(100, 5)])])
        XCTAssertEqual(p.audit.layoffs.count, 1)
        XCTAssertEqual(p.audit.layoffs.first?.days, 100)
    }
}
