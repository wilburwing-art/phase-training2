import XCTest
@testable import PhaseTraining

/// The weekly discount after time off, measured from the lifter's own
/// comebacks, gated on enough breaks and clamped to 0.5-1.5%.
final class DetrainingRateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    private func session(_ name: String, _ d: Double, _ lb: Double, reps: Int = 5) -> SavedSession {
        let set = LoggedSet(num: 1, weight: lb.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(lb))" : "\(lb)",
                            reps: "\(reps)", rpe: "", done: true)
        return SavedSession(templateId: "t", name: name, category: "c", startTime: daysAgo(d),
                            exercises: [LoggedExercise(id: "e", name: name, type: nil, unit: "lbs", targetSets: 1,
                                                       targetReps: reps, rest: 90, sets: [set], prevSets: [])],
                            feel: nil, note: nil, endTime: daysAgo(d), duration: 1800)
    }

    /// `breaks` ten-week breaks. Each exercise is trained twice at 200 lb
    /// before a break and returns at `back` lb, three weeks clear of the next
    /// break so the 14-day return window sees only the return. Pairs = breaks x exercises.
    private func comebacks(breaks: Int, exercises: Int, back: Double, extra: [SavedSession] = []) -> HistoryProfile {
        var sessions = extra
        for k in 0..<breaks {
            let pre = 700 - Double(k) * 98
            for e in 0..<exercises {
                let name = "Zz Lift \(e)"
                sessions += [session(name, pre, 200), session(name, pre - 7, 200), session(name, pre - 77, back)]
            }
        }
        return HistoryProfile.build(sessions: sessions, imported: [], now: now)
    }

    func test_twoBreaksAreNotEnough() {
        let p = comebacks(breaks: 2, exercises: 6, back: 194)
        XCTAssertEqual(p.audit.layoffs.count, 2)
        XCTAssertFalse(p.detraining.isPersonal)
        XCTAssertEqual(p.detraining.perWeek, ProvenStrength.discountPerWeek)
        XCTAssertEqual(p.detraining.pairs, 12, "still measured, just not used")
    }

    func test_threeBreaksGiveAPersonalRate() throws {
        // 97% after 10 weeks: 3% over 6 weeks past the 4-week grace.
        let p = comebacks(breaks: 3, exercises: 4, back: 194)
        XCTAssertTrue(p.detraining.isPersonal)
        XCTAssertEqual(p.detraining.breaks, 3)
        XCTAssertEqual(p.detraining.pairs, 12)
        XCTAssertEqual(p.detraining.perWeek, 0.005, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(p.detraining.measured), 0.005, accuracy: 1e-9)
    }

    func test_steepLossesClampToTheSteepestRate() throws {
        let p = comebacks(breaks: 3, exercises: 4, back: 170)  // 15% over 6 weeks = 2.5%
        XCTAssertEqual(p.detraining.perWeek, 0.015)
        XCTAssertEqual(try XCTUnwrap(p.detraining.measured), 0.025, accuracy: 1e-9)
        XCTAssertEqual(HistoryCheckSheet.rateLine(p.detraining),
                       "In 3 past breaks you lost about 2.5% of your strength a week. That is more than the largest loss the app assumes, so estimates use 1.5% a week.")
    }

    func test_tinyLossesClampToTheGentlestRate() throws {
        let p = comebacks(breaks: 3, exercises: 4, back: 199)
        XCTAssertEqual(p.detraining.perWeek, 0.005)
        XCTAssertEqual(try XCTUnwrap(p.detraining.measured), 0.005 / 6, accuracy: 1e-9)
        XCTAssertEqual(HistoryCheckSheet.rateLine(p.detraining),
                       "In 3 past breaks you lost about 0.1% of your strength a week. That is less than the smallest loss the app assumes, so estimates use 0.5% a week.")
    }

    /// 12 breaks listed, 5 measured: say why the other 7 were not used.
    func test_rateLineExplainsUnmeasuredBreaks() {
        let p = comebacks(breaks: 3, exercises: 4, back: 199)
        XCTAssertEqual(HistoryCheckSheet.rateLine(p.detraining, totalBreaks: 10),
                       "In 3 past breaks you lost about 0.1% of your strength a week. The other 7 didn't have the same lift logged just before and just after, so they couldn't be measured. That is less than the smallest loss the app assumes, so estimates use 0.5% a week.")
    }

    func test_breakLengthReadsInWeeksThenMonths() {
        XCTAssertEqual(HistoryCheckSheet.length(days: 58), "8 weeks")
        XCTAssertEqual(HistoryCheckSheet.length(days: 71), "10 weeks")
        XCTAssertEqual(HistoryCheckSheet.length(days: 92), "3 months")
        XCTAssertEqual(HistoryCheckSheet.length(days: 181), "6 months")
        XCTAssertEqual(HistoryCheckSheet.length(days: 469), "15 months")
    }

    func test_unmatchedListFoldsALongTail() {
        let names: [(name: String, sets: Int)] = [("A", 50), ("B", 9), ("C", 4), ("D", 3), ("E", 2), ("F", 1)]
        let split = UnmatchedNamesSheet.split(names)
        XCTAssertEqual(split.main.map(\.name), ["A", "B"])
        XCTAssertEqual(split.tail.map(\.name), ["C", "D", "E", "F"])
        // Three or fewer small names are not worth a fold.
        let short = UnmatchedNamesSheet.split(Array(names.prefix(5)))
        XCTAssertEqual(short.main.count, 5)
        XCTAssertTrue(short.tail.isEmpty)
    }

    func test_matchLineCountsSetsNotNames() {
        XCTAssertEqual(CSVImportSection.matchLine(totalSets: 4723, unmatchedSets: 507, unmatchedNames: 64),
                       "89% of sets count toward suggestions · 64 names left to match")
        XCTAssertEqual(CSVImportSection.matchLine(totalSets: 1000, unmatchedSets: 1, unmatchedNames: 1),
                       "99% of sets count toward suggestions · 1 name left to match", "never rounds up to 100")
        XCTAssertEqual(CSVImportSection.matchLine(totalSets: 10, unmatchedSets: 0, unmatchedNames: 0),
                       "100% of sets count toward suggestions · every name matched")
    }

    func test_skipReasonsGroupMostFrequentFirst() {
        let g = CSVImportSection.groupedReasons(["Plank: no reps logged", "Side Bridge: no reps logged",
                                                 "Plank: no reps logged", "empty Exercise"])
        XCTAssertEqual(g.map(\.reason), ["Plank: no reps logged", "Side Bridge: no reps logged", "empty Exercise"])
        XCTAssertEqual(g.first?.count, 2)
    }

    func test_anImplausibleReturnIsDropped() {
        var odd: [SavedSession] = []
        for k in 0..<3 {
            let pre = 700 - Double(k) * 98
            odd += [session("Zz Odd", pre, 200), session("Zz Odd", pre - 7, 200), session("Zz Odd", pre - 77, 500)]
        }
        let p = comebacks(breaks: 3, exercises: 4, back: 194, extra: odd)
        XCTAssertEqual(p.detraining.pairs, 12, "a 2.5x return is a unit or name mixup")
        XCTAssertEqual(p.detraining.perWeek, 0.005, accuracy: 1e-9)
    }

    func test_estimatesUseThePersonalRate() throws {
        // Last trained 70 days ago: 6 weeks past grace at 0.5% = 97%.
        let p = comebacks(breaks: 3, exercises: 4, back: 194, extra: [session("Zz Old", 70, 300)])
        let est = try XCTUnwrap(p.profile(forExerciseNamed: "Zz Old")?.estimate)
        XCTAssertEqual(StrengthStandards.epley1RM(weight: est.weight, reps: est.reps),
                       StrengthStandards.epley1RM(weight: 300, reps: 5) * 0.97, accuracy: 0.01)
        XCTAssertNil(HistoryCheckSheet.rateLine(.standard))
    }
}
