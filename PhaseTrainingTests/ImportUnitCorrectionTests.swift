import XCTest
@testable import PhaseTraining

/// An era of pounds typed while the source app was in kg mode reads 2.2x too
/// heavy. Found in a real 2016-2026 Fitbod export; these pin the rule.
final class ImportUnitCorrectionTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_500_000_000)
    private let kgPerLb = ImportUnitCorrection.kgPerLb

    /// `n` weekly sessions from `week`, three exercises each. `typedInKg`
    /// stores the number as kg (what Fitbod does in kg mode); otherwise the
    /// number is pounds converted to kg the way Fitbod stores it.
    private func era(fromWeek week: Int, sessions n: Int, numbers: [String: Double],
                     typedInKg: Bool) -> [ImportedSet] {
        (0..<n).flatMap { i -> [ImportedSet] in
            let at = t0.addingTimeInterval(Double(week + i) * 7 * 86_400)
            return numbers.map { name, number in
                ImportedSet(id: "\(name)-\(week + i)", source: .fitbodCSV, exerciseId: nil,
                            exerciseNameRaw: name, performedAt: at, setNum: 1,
                            weight: typedInKg ? number : number * kgPerLb, reps: 5, rir: nil, rpe: nil)
            }
        }
    }

    private let lifts: [String: Double] = ["Bench": 180, "Squat": 225, "Row": 135]

    func test_typedUnit_readsTheGrid() {
        XCTAssertEqual(ImportUnitCorrection.typedUnit(kg: 80), .kg)
        XCTAssertEqual(ImportUnitCorrection.typedUnit(kg: 22.5), .kg)
        XCTAssertEqual(ImportUnitCorrection.typedUnit(kg: 135 * kgPerLb), .lb)
        XCTAssertEqual(ImportUnitCorrection.typedUnit(kg: 12.5 * kgPerLb), .lb)
        XCTAssertNil(ImportUnitCorrection.typedUnit(kg: 0))
    }

    func test_poundsInKgEra_nextToAPoundEra_isConverted() {
        // The same pound numbers, first stored as kg, then stored properly.
        let sets = era(fromWeek: 0, sessions: 6, numbers: lifts, typedInKg: true)
            + era(fromWeek: 10, sessions: 6, numbers: lifts, typedInKg: false)
        let (fixed, reports) = ImportUnitCorrection.apply(sets)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.correctedSets, 18)
        XCTAssertEqual(reports.first?.from, t0)
        let bench = fixed.filter { $0.exerciseNameRaw == "Bench" }.compactMap(\.weight)
        for kg in bench { XCTAssertEqual(kg / kgPerLb, 180, accuracy: 0.01) }
    }

    func test_interleavedKgAndLbWorkouts_areConverted() {
        // 2017 in the real export: kg-mode and lb-mode workouts alternated
        // week to week, so no run of kg sessions was long enough on its own.
        var sets: [ImportedSet] = []
        for w in 0..<12 {
            sets += era(fromWeek: w, sessions: 1, numbers: lifts, typedInKg: w % 2 == 0)
        }
        let (fixed, reports) = ImportUnitCorrection.apply(sets)
        XCTAssertEqual(reports.first?.correctedSets, 18)
        for kg in fixed.filter({ $0.exerciseNameRaw == "Squat" }).compactMap(\.weight) {
            XCTAssertEqual(kg / kgPerLb, 225, accuracy: 0.01)
        }
    }

    func test_secondPassIsANoOp() {
        let sets = era(fromWeek: 0, sessions: 6, numbers: lifts, typedInKg: true)
            + era(fromWeek: 10, sessions: 6, numbers: lifts, typedInKg: false)
        let once = ImportUnitCorrection.apply(sets).sets
        let twice = ImportUnitCorrection.apply(once)
        XCTAssertEqual(twice.sets, once)
        XCTAssertTrue(twice.reports.isEmpty)
    }

    func test_aKgLifter_isLeftAlone() {
        let sets = era(fromWeek: 0, sessions: 12, numbers: ["Bench": 80, "Squat": 100, "Row": 60], typedInKg: true)
        let (fixed, reports) = ImportUnitCorrection.apply(sets)
        XCTAssertTrue(reports.isEmpty)
        XCTAssertEqual(fixed, sets)
    }

    func test_aGenuineSwitchWithoutTheJump_isLeftAlone() {
        // Real kg numbers (80 kg bench), then the same strength typed in lb.
        let sets = era(fromWeek: 0, sessions: 6, numbers: ["Bench": 80, "Squat": 100, "Row": 60], typedInKg: true)
            + era(fromWeek: 10, sessions: 6, numbers: ["Bench": 176.5, "Squat": 220.5, "Row": 132.5], typedInKg: false)
        XCTAssertTrue(ImportUnitCorrection.apply(sets).reports.isEmpty)
    }
}
