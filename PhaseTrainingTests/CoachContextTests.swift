import XCTest
@testable import PhaseTraining

final class CoachContextTests: XCTestCase {

    // MARK: - bodySection

    func test_bodySection_nilWhenAllFieldsSkipped() {
        var m = TrainingMemory()
        m.heightCm = nil
        m.weightKg = nil
        m.gender = nil
        XCTAssertNil(CoachContext.bodySection(memory: m))
    }

    func test_bodySection_imperialFormatting() {
        var m = TrainingMemory()
        m.heightCm = 178
        m.weightKg = 80.0
        m.gender = .male
        m.usesImperial = true
        let s = CoachContext.bodySection(memory: m) ?? ""
        XCTAssertTrue(s.contains("BODY"))
        XCTAssertTrue(s.contains("5′ 10″"), "expected imperial height, got: \(s)")
        XCTAssertTrue(s.contains("176.4 lb"), "expected imperial weight, got: \(s)")
        XCTAssertTrue(s.contains("male"))
    }

    func test_bodySection_metricFormatting() {
        var m = TrainingMemory()
        m.heightCm = 178
        m.weightKg = 80.0
        m.gender = .female
        m.usesImperial = false
        let s = CoachContext.bodySection(memory: m) ?? ""
        XCTAssertTrue(s.contains("178 cm"))
        XCTAssertTrue(s.contains("80.0 kg"))
        XCTAssertTrue(s.contains("female"))
    }

    // MARK: - strengthSection

    func test_strengthSection_nilWithoutBodyweight() {
        var m = TrainingMemory()
        m.weightKg = nil
        m.gender = .male
        let sessions = [
            savedSession(name: "Bench Press", sets: [("225", "5")])
        ]
        XCTAssertNil(CoachContext.strengthSection(memory: m, sessions: sessions))
    }

    func test_strengthSection_includesRatioAndTier() {
        var m = TrainingMemory()
        m.weightKg = BodyMetrics.lbToKg(180)
        m.gender = .male
        m.usesImperial = true
        // 225×5 → Epley 262.5 lb → 262.5/180 ≈ 1.46× BW → intermediate (≥1.25, <1.75)
        let sessions = [
            savedSession(name: "Bench Press", sets: [("225", "5")])
        ]
        let s = CoachContext.strengthSection(memory: m, sessions: sessions) ?? ""
        XCTAssertTrue(s.contains("STRENGTH"))
        XCTAssertTrue(s.contains("Bench Press"))
        XCTAssertTrue(s.contains("1.46× BW"), "expected ratio in output, got: \(s)")
        XCTAssertTrue(s.contains("intermediate"))
        XCTAssertTrue(s.contains("lb"), "expected imperial unit, got: \(s)")
    }

    func test_strengthSection_skipsTiersWhenGenderMissing() {
        var m = TrainingMemory()
        m.weightKg = BodyMetrics.lbToKg(180)
        m.gender = nil
        let sessions = [savedSession(name: "Bench Press", sets: [("225", "5")])]
        let s = CoachContext.strengthSection(memory: m, sessions: sessions) ?? ""
        // No tier text — only the ratio.
        XCTAssertTrue(s.contains("1.46× BW"))
        XCTAssertFalse(s.contains("intermediate"))
        XCTAssertTrue(s.contains("gender not set"))
    }

    // MARK: - familiaritySection

    func test_familiaritySection_nilUnderThreshold() {
        // Fewer than 3 unique exercises = no signal worth surfacing.
        let sessions = [
            savedSession(name: "Bench Press", sets: [("225", "5")]),
            savedSession(name: "Back Squat", sets: [("315", "5")])
        ]
        XCTAssertNil(CoachContext.familiaritySection(sessions: sessions, now: Date()))
    }

    func test_familiaritySection_sortsBySetCount() {
        // Three distinct exercises across multiple sessions — bench should
        // have more sets than the others.
        let bench1 = savedSession(name: "Bench Press", sets: [("225", "5"), ("225", "5"), ("225", "5")])
        let bench2 = savedSession(name: "Bench Press", sets: [("230", "5"), ("230", "5")])
        let row = savedSession(name: "Barbell Row", sets: [("185", "5")])
        let squat = savedSession(name: "Back Squat", sets: [("315", "5"), ("315", "5")])
        let s = CoachContext.familiaritySection(
            sessions: [bench1, bench2, row, squat],
            now: Date()
        ) ?? ""
        XCTAssertTrue(s.contains("EXERCISE FAMILIARITY"))
        let benchIdx = s.range(of: "Bench Press")!.lowerBound
        let squatIdx = s.range(of: "Back Squat")!.lowerBound
        let rowIdx = s.range(of: "Barbell Row")!.lowerBound
        XCTAssertLessThan(benchIdx, squatIdx, "bench (5 sets) should rank above squat (2)")
        XCTAssertLessThan(squatIdx, rowIdx, "squat (2 sets) should rank above row (1)")
    }

    func test_familiaritySection_excludesOlderThanWindow() {
        let cal = Calendar.current
        let now = Date()
        let old = savedSession(
            name: "Bench Press",
            sets: [("225", "5")],
            startTime: cal.date(byAdding: .day, value: -120, to: now)!
        )
        let recent1 = savedSession(name: "Squat", sets: [("315", "5")])
        let recent2 = savedSession(name: "Row", sets: [("185", "5")])
        let recent3 = savedSession(name: "OHP", sets: [("135", "5")])
        let s = CoachContext.familiaritySection(
            sessions: [old, recent1, recent2, recent3],
            now: now
        ) ?? ""
        XCTAssertFalse(s.contains("Bench Press"), "120-day-old session should be excluded")
        XCTAssertTrue(s.contains("Squat"))
    }

    // MARK: - Helpers

    private func savedSession(
        name: String,
        sets: [(weight: String, reps: String)],
        startTime: Date = Date().addingTimeInterval(-3600)
    ) -> SavedSession {
        let logged = LoggedExercise(
            id: name, name: name, type: nil, unit: "lbs",
            targetSets: sets.count, targetReps: 5, rest: 90,
            sets: sets.enumerated().map { i, s in
                LoggedSet(num: i + 1, weight: s.weight, reps: s.reps, rpe: "", done: true)
            },
            prevSets: []
        )
        return SavedSession(
            templateId: "t", name: name, category: "",
            startTime: startTime,
            exercises: [logged], feel: nil, note: nil,
            endTime: startTime.addingTimeInterval(3600), duration: 3600
        )
    }
}
