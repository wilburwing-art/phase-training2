import XCTest
@testable import PhaseTraining

/// The history-aware suggestion behind the Log pill and the Today tile:
/// rep-gap remap, plateau "add a rep", and the lifter's own weight step.
final class ProgressionSuggestionProfileTests: XCTestCase {

    private let now = Date()

    private func sets(_ w: Double, _ r: Int, count: Int = 3) -> [LoggedSet] {
        (1...count).map { LoggedSet(num: $0, weight: "\(w)", reps: "\(r)", rpe: "", done: true) }
    }

    private func profile(estimate: PriorBest? = nil, step: Double? = nil, plateau: Bool = false)
        -> HistoryProfile.ExerciseProfile {
        .init(name: "x", estimate: estimate, trend: plateau ? .flat(0) : .unknown, plateau: plateau,
              typicalStepLb: step, lastTrained: now, bestE1RM: 0, bestDate: now, workouts: 6, excludedSets: 0,
              latestBest: .init(date: now, weightLb: 0, reps: 0), recentBests: [])
    }

    private func suggest(_ prev: [LoggedSet], target: Int, name: String = "Barbell Back Squat",
                         unit: String = "lbs", profile p: HistoryProfile.ExerciseProfile?) -> ProgressionSuggestion.Result? {
        ProgressionSuggestion.suggest(prevSets: prev, targetReps: target, exerciseName: name, unit: unit, profile: p)
    }

    func test_noProfile_isTheOldRule() {
        let old = ProgressionSuggestion.suggest(prevSets: sets(185, 5), targetReps: 5, exerciseName: "Barbell Back Squat", unit: "lbs")
        XCTAssertEqual(suggest(sets(185, 5), target: 5, profile: nil), old)
        XCTAssertEqual(old?.suggestedWeight, 190)
    }

    func test_sameReps_useTheLinearRule() {
        let r = suggest(sets(185, 5), target: 6, profile: profile(estimate: PriorBest(weight: 185, reps: 5, date: now)))
        XCTAssertEqual(r?.basis, .lastSession)
        XCTAssertEqual(r?.suggestedWeight, 185, "5 reps against a 6-rep target is a miss by 1: hold")
    }

    func test_aRepGap_mapsTheEstimateToTodaysReps() throws {
        // Last time 135 x 10 (e1RM 180); today asks for 5.
        let est = PriorBest(weight: 135, reps: 10, date: now)
        let r = try XCTUnwrap(suggest(sets(135, 10), target: 5, profile: profile(estimate: est)))
        XCTAssertEqual(r.basis, .repRemap)
        XCTAssertEqual(r.label, "for 5 reps")
        XCTAssertEqual(r.suggestedWeight, ProgressionSuggestion.fromHistory(est, targetReps: 5, unit: "lbs")?.suggestedWeight)
        XCTAssertGreaterThan(r.suggestedWeight, 140, "the old rule said 140, too light for 5 reps")
        // The other direction: a lighter load for more reps.
        let more = try XCTUnwrap(suggest(sets(225, 5), target: 12, profile: profile(estimate: PriorBest(weight: 225, reps: 5, date: now))))
        XCTAssertEqual(more.basis, .repRemap)
        XCTAssertLessThan(more.suggestedWeight, 225)
    }

    func test_personalStep_replacesTheTable() {
        // Dumbbell curl: table says +2.5, the lifter's dumbbells go up by 5.
        let r = suggest(sets(25, 10), target: 10, name: "Dumbbell Curl", profile: profile(step: 5))
        XCTAssertEqual(r?.suggestedWeight, 30)
        XCTAssertEqual(r?.label, "+5")
        let backOff = suggest(sets(25, 6), target: 10, name: "Dumbbell Curl", profile: profile(step: 5))
        XCTAssertEqual(backOff?.suggestedWeight, 20)
    }

    func test_personalStep_capsAJumpTooBigForTheWeight() {
        // A 20 lb step on a 60 lb lift: bigger than 2x table (5) and 10% (6) -> table.
        XCTAssertEqual(ProgressionSuggestion.personalStep(profile: profile(step: 20), workingWeight: 60, unit: "lbs", compound: false), 2.5)
        // On a 225 lb squat a 10 lb step is fine (<= 22.5).
        XCTAssertEqual(ProgressionSuggestion.personalStep(profile: profile(step: 10), workingWeight: 225, unit: "lbs", compound: true), 10)
    }

    func test_personalStep_inKg_snapsTo1_25() {
        XCTAssertEqual(ProgressionSuggestion.personalStep(profile: profile(step: 5), workingWeight: 60, unit: "kg", compound: true), 2.5)
        XCTAssertEqual(ProgressionSuggestion.personalStep(profile: profile(step: 2.5), workingWeight: 20, unit: "kg", compound: false), 1.25)
    }

    func test_plateau_addsARep_onlyWhenTheTargetWasHit() {
        let hit = suggest(sets(185, 5), target: 5, profile: profile(step: 5, plateau: true))
        XCTAssertEqual(hit?.basis, .addRep)
        XCTAssertEqual(hit?.suggestedWeight, 185)
        let missed = suggest(sets(185, 3), target: 5, profile: profile(step: 5, plateau: true))
        XCTAssertEqual(missed?.basis, .lastSession)
        XCTAssertEqual(missed?.suggestedWeight, 180, "missed by 2 backs off as before")
    }

    // MARK: - Autoregulation reaches the on-screen suggestion (P4 item 5)

    private func attempt(_ name: String, daysAgo: Double, done: Int, of target: Int,
                         weight: Double = 100, reps: Int = 5, now: Date) -> SavedSession {
        let when = now.addingTimeInterval(-daysAgo * 86_400)
        let sets = (0..<target).map { i in
            LoggedSet(num: i + 1, weight: "\(Int(weight))", reps: "\(reps)", rpe: "", done: i < done)
        }
        return SavedSession(templateId: "t", name: name, category: "c", startTime: when,
                            exercises: [LoggedExercise(id: "e", name: name, type: nil, unit: "lbs",
                                                       targetSets: target, targetReps: reps, rest: 90,
                                                       sets: sets, prevSets: [])],
                            feel: nil, note: nil, endTime: when, duration: 1800)
    }

    private func suggestion(_ sessions: [SavedSession], now: Date) -> ProgressionSuggestion.Result? {
        let profile = HistoryProfile.build(sessions: sessions, imported: [], now: now)
        let last = sessions.first!.exercises[0]
        return ProgressionSuggestion.suggest(
            prevSets: last.sets, targetReps: 5, exerciseName: "Zz Squat", unit: "lb",
            profile: profile.profile(forExerciseNamed: "Zz Squat"))
    }

    func test_twoSessionsUnderEightyPercentSoftenTheSuggestion() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weak = [attempt("Zz Squat", daysAgo: 2, done: 3, of: 5, now: now),
                    attempt("Zz Squat", daysAgo: 6, done: 3, of: 5, now: now)]
        let ok = [attempt("Zz Squat", daysAgo: 2, done: 4, of: 5, now: now),
                  attempt("Zz Squat", daysAgo: 6, done: 4, of: 5, now: now)]
        let eased = try XCTUnwrap(suggestion(weak, now: now))
        let normal = try XCTUnwrap(suggestion(ok, now: now))
        XCTAssertEqual(normal.suggestedWeight, 105, "80% completion is not under the bar")
        XCTAssertEqual(eased.suggestedWeight, 97.5, "105 less 5%, snapped down to 2.5")
        XCTAssertLessThan(eased.suggestedWeight, normal.suggestedWeight)
    }

    func test_twoCleanSessionsAmplifyTheSuggestion() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let strong = [attempt("Zz Squat", daysAgo: 2, done: 5, of: 5, now: now),
                      attempt("Zz Squat", daysAgo: 6, done: 5, of: 5, now: now)]
        let r = try XCTUnwrap(suggestion(strong, now: now))
        XCTAssertEqual(r.suggestedWeight, 110, "105 plus 5 lb")
    }

    func test_aSingleWeakSessionChangesNothing() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let one = [attempt("Zz Squat", daysAgo: 2, done: 2, of: 5, now: now)]
        let r = try XCTUnwrap(suggestion(one, now: now))
        XCTAssertEqual(r.suggestedWeight, 105)
    }

    // MARK: - Imported effort steers suggestions (P4 item 6)

    private func importedHistory(rir: Double?, rpe: Double?, now: Date) throws -> HistoryProfile.ExerciseProfile {
        guard let squat = CoachDatabase.shared.exerciseId(forImportName: "Back Squat") else {
            throw XCTSkip("no Back Squat in the catalog")
        }
        let kg = 225 * ImportUnitCorrection.kgPerLb
        let sets = (0..<3).map { i in
            ImportedSet(id: "s\(i)", source: .fitbodCSV, exerciseId: squat, exerciseNameRaw: "Back Squat",
                        performedAt: now.addingTimeInterval(-3 * 86_400), setNum: i + 1,
                        weight: kg, reps: 5, rir: rir, rpe: rpe)
        }
        let profile = HistoryProfile.build(sessions: [], imported: sets, now: now)
        return try XCTUnwrap(profile.profile(forExerciseNamed: "Back Squat"))
    }

    func test_importedEffortReachesTheProfile() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(try importedHistory(rir: 3, rpe: nil, now: now).latestBest.rir, 3)
        XCTAssertEqual(try importedHistory(rir: nil, rpe: 7, now: now).latestBest.rir, 3, "RPE 7 is 3 in reserve")
        XCTAssertEqual(try importedHistory(rir: nil, rpe: 7, now: now).estimate?.rir, 3)
        XCTAssertNil(try importedHistory(rir: nil, rpe: nil, now: now).latestBest.rir)
    }

    func test_importedEasySetsRaiseTheFirstSuggestion() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func load(_ p: HistoryProfile.ExerciseProfile) throws -> Double {
            let est = try XCTUnwrap(p.estimate)
            return try XCTUnwrap(ProgressionSuggestion.fromHistory(est, targetReps: 5, unit: "lb")).suggestedWeight
        }
        let unrated = try load(importedHistory(rir: nil, rpe: nil, now: now))
        let easy = try load(importedHistory(rir: 3, rpe: nil, now: now))
        let failure = try load(importedHistory(rir: 0, rpe: nil, now: now))
        XCTAssertGreaterThan(easy, unrated)
        XCTAssertEqual(failure, unrated, "a set at failure is taken as it stands")
    }
}
