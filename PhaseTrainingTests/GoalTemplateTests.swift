// GoalTemplateTests.swift — PR 11 of the weekly-coach roadmap.
//
// Coverage:
//   - GoalTemplate metric wiring (exercise name, multiplier per goal).
//   - UserGoal.progress: strength goals vs bodyweight (reaches 1.0 at
//     the target multiple), unknown bodyweight → nil (not zero), 5k
//     time scaling, climbs count, clamping above 1.0.
//   - TrainingMemory round-trip: userGoals survives encode/decode;
//     pre-PR-11 JSON (no userGoals key) decodes to [].
//   - SavedSession tags: JSON round-trip; pre-PR-11 JSON without the
//     key decodes to []; SQLite v2 migration persists tags.

import XCTest
@testable import PhaseTraining

final class GoalTemplateTests: XCTestCase {

    // MARK: - Template wiring

    func test_strengthGoals_carryExerciseAndMultiplier() {
        XCTAssertEqual(GoalTemplate.benchBodyweight.exerciseName, "Bench Press")
        XCTAssertEqual(GoalTemplate.benchBodyweight.loadMultiplier, 1.0)
        XCTAssertEqual(GoalTemplate.deadliftTwoXBodyweight.loadMultiplier, 2.0)
        XCTAssertEqual(GoalTemplate.squatOnePointFiveXBodyweight.loadMultiplier, 1.5)
        XCTAssertEqual(GoalTemplate.ohpThreeQuartersBodyweight.loadMultiplier, 0.75)
    }

    func test_nonStrengthGoals_haveNoStrengthMetric() {
        XCTAssertNil(GoalTemplate.fiveKUnder25.exerciseName)
        XCTAssertNil(GoalTemplate.fiveKUnder25.loadMultiplier)
        XCTAssertNil(GoalTemplate.climbsHundredPerMonth.exerciseName)
    }

    // MARK: - Progress computation

    private func goal(_ t: GoalTemplate) -> UserGoal {
        UserGoal(templateId: t, createdAt: Date())
    }

    func test_strengthProgress_atTargetReachesOne() {
        // 80 kg bodyweight, bench target = BW → 80 kg e1RM = done.
        let p = goal(.benchBodyweight).progress(
            bestE1RM: ["bench press": 80.0], bodyweightKg: 80.0,
            fastestFiveKSeconds: nil, climbsLast30Days: 0)
        XCTAssertEqual(p ?? 0, 1.0, accuracy: 0.0001)
    }

    func test_strengthProgress_belowTargetScalesLinearly() {
        // 60 kg e1RM vs 80 kg target → 0.75.
        let p = goal(.benchBodyweight).progress(
            bestE1RM: ["bench press": 60.0], bodyweightKg: 80.0,
            fastestFiveKSeconds: nil, climbsLast30Days: 0)
        XCTAssertEqual(p ?? 0, 0.75, accuracy: 0.0001)
    }

    func test_strengthProgress_withoutBodyweightIsNilNotZero() {
        // Unknown bodyweight ≠ no progress — the bar should say "log
        // your weight", not show an empty bar.
        let p = goal(.benchBodyweight).progress(
            bestE1RM: ["bench press": 80.0], bodyweightKg: nil,
            fastestFiveKSeconds: nil, climbsLast30Days: 0)
        XCTAssertNil(p)
    }

    func test_strengthProgress_withoutExerciseHistoryIsNil() {
        let p = goal(.deadliftTwoXBodyweight).progress(
            bestE1RM: [:], bodyweightKg: 80.0,
            fastestFiveKSeconds: nil, climbsLast30Days: 0)
        XCTAssertNil(p)
    }

    func test_pullUpProgress_targetIsBodyweightItself() {
        // e1RM of the weighted pull-up pattern vs BW: at 80 kg e1RM and
        // 80 kg BW → done.
        let p = goal(.pullUpUnweighted).progress(
            bestE1RM: ["pull-up": 80.0], bodyweightKg: 80.0,
            fastestFiveKSeconds: nil, climbsLast30Days: 0)
        XCTAssertEqual(p ?? 0, 1.0, accuracy: 0.0001)
    }

    func test_fiveKProgress_fasterThanTargetIsDone() {
        // 22:00 (1320 s) beats the 25:00 target.
        let p = goal(.fiveKUnder25).progress(
            bestE1RM: [:], bodyweightKg: nil,
            fastestFiveKSeconds: 22 * 60, climbsLast30Days: 0)
        XCTAssertEqual(p ?? 0, 1.0, accuracy: 0.0001)
    }

    func test_fiveKProgress_nilWithoutARun() {
        XCTAssertNil(goal(.fiveKUnder25).progress(
            bestE1RM: [:], bodyweightKg: 80.0,
            fastestFiveKSeconds: nil, climbsLast30Days: 0))
    }

    func test_climbsProgress_scalesWithCount() {
        let p = goal(.climbsHundredPerMonth).progress(
            bestE1RM: [:], bodyweightKg: nil,
            fastestFiveKSeconds: nil, climbsLast30Days: 60)
        XCTAssertEqual(p ?? 0, 0.6, accuracy: 0.0001)
        let done = goal(.climbsHundredPerMonth).progress(
            bestE1RM: [:], bodyweightKg: nil,
            fastestFiveKSeconds: nil, climbsLast30Days: 140)
        XCTAssertEqual(done ?? 0, 1.0, accuracy: 0.0001)  // clamped
    }

    // MARK: - TrainingMemory round-trip

    func test_userGoals_surviveCodableRoundTrip() throws {
        var m = TrainingMemory()
        m.userGoals = [goal(.benchBodyweight), goal(.fiveKUnder25)]
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(TrainingMemory.self, from: data)
        XCTAssertEqual(back.userGoals.map(\.templateId), [.benchBodyweight, .fiveKUnder25])
    }

    func test_userGoals_absentOnLegacyJSON_decodesEmpty() throws {
        // A pre-PR-11 memory JSON: no userGoals key at all.
        let m = TrainingMemory()
        let data = try JSONEncoder().encode(m)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "userGoals")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(TrainingMemory.self, from: legacy)
        XCTAssertTrue(back.userGoals.isEmpty)
    }

    // MARK: - SavedSession tags (JSON layer)

    func test_sessionTags_roundTripThroughCodable() throws {
        let s = SavedSession(
            templateId: "t", name: "Push", category: "lift",
            startTime: Date(timeIntervalSince1970: 1_770_000_000),
            exercises: [], feel: nil, note: nil,
            endTime: Date(timeIntervalSince1970: 1_770_003_600),
            duration: 3_600,
            sessionTags: [SessionTag.maxAttempt.rawValue, SessionTag.testDay.rawValue]
        )
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        let back = try d.decode(SavedSession.self, from: e.encode(s))
        XCTAssertEqual(back.sessionTags, s.sessionTags)
    }

    func test_sessionTags_absentOnLegacyJSON_decodesEmpty() throws {
        let s = SavedSession(
            templateId: "t", name: "Push", category: "lift",
            startTime: Date(timeIntervalSince1970: 1_770_000_000),
            exercises: [], feel: nil, note: nil,
            endTime: Date(timeIntervalSince1970: 1_770_003_600),
            duration: 3_600
        )
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        var json = try JSONSerialization.jsonObject(with: e.encode(s)) as! [String: Any]
        json.removeValue(forKey: "sessionTags")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        let back = try d.decode(SavedSession.self, from: legacy)
        XCTAssertTrue(back.sessionTags.isEmpty)
    }

    // MARK: - SQLite layer (migration v2 + round-trip)

    private func freshUserDB() -> UserDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("goaltests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return UserDatabase(path: dir.appendingPathComponent("user.db").path)
    }

    func test_sessionTags_surviveSQLiteSaveLoad() {
        let db = freshUserDB()
        let tags = [SessionTag.techniqueFocus.rawValue]
        let s = SavedSession(
            templateId: "t", name: "Push", category: "lift",
            startTime: Date(timeIntervalSince1970: 1_770_000_000),
            exercises: [], feel: nil, note: nil,
            endTime: Date(timeIntervalSince1970: 1_770_003_600),
            duration: 3_600, sessionTags: tags
        )
        XCTAssertTrue(db.saveSession(s))
        let loaded = db.listSavedSessions().first
        XCTAssertEqual(loaded?.sessionTags, tags)
    }

    func test_sessionTags_defaultEmptyOnUntaggedSave() {
        let db = freshUserDB()
        let s = SavedSession(
            templateId: "t", name: "Push", category: "lift",
            startTime: Date(timeIntervalSince1970: 1_770_000_000),
            exercises: [], feel: nil, note: nil,
            endTime: Date(timeIntervalSince1970: 1_770_003_600),
            duration: 3_600
        )
        XCTAssertTrue(db.saveSession(s))
        XCTAssertEqual(db.listSavedSessions().first?.sessionTags, [])
    }
}