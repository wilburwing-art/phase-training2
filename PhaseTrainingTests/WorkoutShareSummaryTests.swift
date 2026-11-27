import XCTest
@testable import PhaseTraining

final class WorkoutShareSummaryTests: XCTestCase {
    private func make(
        doneSets: Int = 18,
        volume: Double = 12_450,
        imperial: Bool = true,
        prs: [WorkoutShareSummary.PR] = [],
        exercises: [WorkoutShareSummary.DoneExercise] = []
    ) -> WorkoutShareSummary {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 27; comps.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        return WorkoutShareSummary.make(
            sessionName: "Upper Body", date: date, elapsedSeconds: 2528,
            doneSets: doneSets, workingVolume: volume, usesImperial: imperial,
            prs: prs, exercises: exercises)
    }

    func testSetPluralisation() {
        XCTAssertEqual(make(doneSets: 18).setsLine, "18 sets")
        XCTAssertEqual(make(doneSets: 1).setsLine, "1 set")
    }

    func testDateAndDuration() {
        let s = make()
        XCTAssertEqual(s.dateLine, "Fri, Nov 27")
        XCTAssertEqual(s.durationLine, "42:08")
    }

    func testVolume() {
        XCTAssertNil(make(volume: 0).volumeLine)
        XCTAssertEqual(make(volume: 12_450, imperial: true).volumeLine, "12,450 lb")
        XCTAssertEqual(make(volume: 5_640, imperial: false).volumeLine, "5,640 kg")
    }

    func testPRDiffFormatting() {
        let s = make(prs: [
            .init(name: "Bench Press", diff: 10, unit: "lbs"),
            .init(name: "Squat", diff: 2.5, unit: "kg"),
        ])
        XCTAssertEqual(s.prLines, ["Bench Press +10 lbs", "Squat +2.5 kg"])
    }

    func testExercisesWithoutDoneSetsDropped() {
        let s = make(exercises: [
            .init(name: "Bench Press", doneSets: 3),
            .init(name: "Row", doneSets: 0),
            .init(name: "Curl", doneSets: 1),
        ])
        XCTAssertEqual(s.exerciseLines, ["Bench Press · 3 sets", "Curl · 1 set"])
    }

    func testExerciseCapAtSix() {
        let ex = (1...8).map { WorkoutShareSummary.DoneExercise(name: "Ex \($0)", doneSets: 2) }
        let s = make(exercises: ex)
        XCTAssertEqual(s.exerciseLines.count, 7)
        XCTAssertEqual(s.exerciseLines.first, "Ex 1 · 2 sets")
        XCTAssertEqual(s.exerciseLines.last, "+2 more")

        let six = make(exercises: Array(ex.prefix(6)))
        XCTAssertEqual(six.exerciseLines.count, 6)
        XCTAssertFalse(six.exerciseLines.contains { $0.contains("more") })
    }

    func testShareText() {
        let s = make(prs: [.init(name: "Bench Press", diff: 10, unit: "lbs")],
                     exercises: [.init(name: "Bench Press", doneSets: 3)])
        let lines = s.shareText.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "Upper Body")
        XCTAssertTrue(lines.contains("42:08 · 18 sets · 12,450 lb"))
        XCTAssertTrue(lines.contains("Bench Press +10 lbs"))
        XCTAssertEqual(lines.last, "Logged in Phase")
    }

    @MainActor
    func testImageIs1080x1350() throws {
        let ex = (1...8).map { WorkoutShareSummary.DoneExercise(name: "Ex \($0)", doneSets: 3) }
        let image = try XCTUnwrap(WorkoutShareCard.image(for: make(
            prs: [.init(name: "Bench Press", diff: 10, unit: "lbs")], exercises: ex)))
        XCTAssertEqual(Int(image.size.width * image.scale), 1080)
        XCTAssertEqual(Int(image.size.height * image.scale), 1350)
    }
}
