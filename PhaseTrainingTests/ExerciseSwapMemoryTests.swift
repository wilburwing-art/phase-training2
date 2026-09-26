// ExerciseSwapMemoryTests.swift — the swap-memory feature: capture (a swap
// writes a preference into TrainingMemory) and consume (the season engine's
// candidate comparator ranks by it, and the swap picker lists past choices
// first). See MemoryStore.recordSwap, AthleteState.exerciseAffinities,
// SportSeasonGenerator.rotationTier and ExerciseSearch.preferenceOrdered.

import XCTest
@testable import PhaseTraining

final class ExerciseSwapMemoryTests: XCTestCase {

    // MARK: - Capture (MemoryStore.recordSwap)

    private func freshStore(_ suite: String) -> MemoryStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return MemoryStore(defaults: defaults)
    }

    func test_recordSwap_boostsReplacementImmediately() {
        let store = freshStore("test.swap.boost")
        store.recordSwap(out: "Barbell Bench Press", in: "Dumbbell Bench Press")
        XCTAssertEqual(store.memory.exerciseAffinities["Dumbbell Bench Press"], 1,
                       "The swapped-in exercise should gain +1 affinity right away")
    }

    func test_recordSwap_isNoOpWhenNamesMatch() {
        let store = freshStore("test.swap.same")
        // Case-insensitive equal — a swap to the same exercise carries no signal.
        store.recordSwap(out: "Bench Press", in: "bench press")
        XCTAssertTrue(store.memory.exerciseAffinities.isEmpty)
        XCTAssertTrue(store.memory.swapAwayCounts.isEmpty)
    }

    func test_recordSwap_demotesOriginalOnlyAtThreshold() {
        let store = freshStore("test.swap.demote")
        let threshold = MemoryStore.swapAwayDemoteThreshold

        // Swap away from "Leg Press" toward a different exercise each time so
        // the replacement bumps don't touch the original.
        for i in 0..<(threshold - 1) {
            store.recordSwap(out: "Leg Press", in: "Alt Quad Lift \(i)")
        }
        XCTAssertNil(store.memory.exerciseAffinities["Leg Press"],
                     "Original must NOT be demoted before the threshold")
        XCTAssertEqual(store.memory.swapAwayCounts["Leg Press"], threshold - 1)

        store.recordSwap(out: "Leg Press", in: "Alt Quad Lift final")
        XCTAssertEqual(store.memory.exerciseAffinities["Leg Press"], -1,
                       "Original is demoted by one once swaps-away hit the threshold")
        XCTAssertEqual(store.memory.swapAwayCounts["Leg Press"], threshold)
    }

    func test_swapAwayCounts_roundTripsThroughCodable() throws {
        var m = TrainingMemory()
        m.swapAwayCounts = ["Squat": 2]
        m.exerciseAffinities = ["Front Squat": 3]
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(TrainingMemory.self, from: data)
        XCTAssertEqual(decoded.swapAwayCounts["Squat"], 2)
        XCTAssertEqual(decoded.exerciseAffinities["Front Squat"], 3)
    }

    // MARK: - Consume (season engine ranks candidates by affinity)
    //
    // The previous consume tests drove WorkoutGenerator.generateLift with no
    // primary sport, which returns an empty "Rest" day, so every run hit
    // XCTSkip and nothing was ever asserted. These drive the live engine and
    // fail instead of skipping when the fixture finds no target.

    private let slug = "alpine-skiing"
    private let season: SeasonPhase = .offSeason

    private func skier(week: Int, affinities: [String: Int]) -> AthleteState {
        var m = TrainingMemory()
        let sport = Sport(slug: slug, name: "Alpine Skiing")
        m.primarySport = sport
        m.seasonsBySport = [sport: season]
        m.defaultSeason = season
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        m.exerciseAffinities = affinities
        return AthleteState.from(m, variant: .inbounds, weekNumber: week)
    }

    /// Tally movement picks over 30 weeks x 3 sessions, keyed by exercise id.
    private func pickFrequencies(affinities: [String: Int]) -> [Int: Int] {
        var freq: [Int: Int] = [:]
        for week in 1...30 {
            let a = skier(week: week, affinities: affinities)
            for s in SportSeasonGenerator.generateWeek(a) {
                for ex in s.exercises { freq[ex.exerciseId, default: 0] += 1 }
            }
        }
        return freq
    }

    private var pool: [SportMovement] {
        CoachDatabase.shared.sportMovements(sport: slug).filter { $0.allowedPhases.contains(season) }
    }

    /// A movement whose primary demand has other primary movements competing
    /// for it, picked in some samples but not all: its share can move.
    private func contestedMovement(in freq: [Int: Int]) -> SportMovement? {
        let maxFreq = freq.values.max() ?? 0
        return pool.filter { m in
            let rivals = pool.filter { $0.primaryDemand == m.primaryDemand && $0.exerciseId != m.exerciseId }
            let f = freq[m.exerciseId] ?? 0
            return !rivals.isEmpty && f > 0 && f < maxFreq
        }.max { (freq[$0.exerciseId] ?? 0, $1.name) < (freq[$1.exerciseId] ?? 0, $0.name) }
    }

    func test_positiveAffinity_raisesPickFrequency() throws {
        let baseline = pickFrequencies(affinities: [:])
        let target = try XCTUnwrap(contestedMovement(in: baseline),
                                   "fixture found no contested movement; the test would assert nothing")
        let boosted = pickFrequencies(affinities: [target.name: 3])
        XCTAssertGreaterThan(boosted[target.exerciseId] ?? 0, baseline[target.exerciseId] ?? 0,
            "Boosting \(target.name) should raise its picks " +
            "(\(baseline[target.exerciseId] ?? 0) to \(boosted[target.exerciseId] ?? 0))")
    }

    func test_rejectedMovement_isNotPickedWhenRivalsExist() throws {
        let baseline = pickFrequencies(affinities: [:])
        let target = try XCTUnwrap(contestedMovement(in: baseline),
                                   "fixture found no contested movement; the test would assert nothing")
        let rejected = pickFrequencies(affinities: [target.name: AthleteState.affinitySinkThreshold])
        XCTAssertLessThan(rejected[target.exerciseId] ?? 0, baseline[target.exerciseId] ?? 0,
            "Rejecting \(target.name) should cut its picks " +
            "(\(baseline[target.exerciseId] ?? 0) to \(rejected[target.exerciseId] ?? 0))")
    }

    func test_rejectedSoleMovement_stillServesItsDemand() throws {
        let baseline = pickFrequencies(affinities: [:])
        let sole = try XCTUnwrap(pool.first { m in
            (baseline[m.exerciseId] ?? 0) > 0
                && !pool.contains { $0.primaryDemand == m.primaryDemand && $0.exerciseId != m.exerciseId }
        }, "fixture found no sole-primary movement; the test would assert nothing")
        let rejected = pickFrequencies(affinities: [sole.name: -5])
        XCTAssertEqual(rejected[sole.exerciseId] ?? 0, baseline[sole.exerciseId] ?? 0,
            "\(sole.name) is the only primary movement for its demand; rejecting it must not drop the demand")
    }

    func test_affinitiesForUnknownNames_changeNothing() {
        for week in 1...5 {
            let plain = SportSeasonGenerator.generateWeek(skier(week: week, affinities: [:]))
            let noisy = SportSeasonGenerator.generateWeek(skier(week: week, affinities: ["Not A Real Lift": 4]))
            XCTAssertEqual(plain, noisy, "week \(week): an affinity matching no movement changed the session")
        }
    }

    func test_affinityKeys_foldCase() {
        let a = skier(week: 1, affinities: ["Goblet Squat": 1, "goblet squat": 2])
        XCTAssertEqual(a.affinity(for: "GOBLET SQUAT"), 3)
    }

    // MARK: - Consume (swap picker browse order)

    func test_preferenceOrdered_floatsChosenExercisesAndKeepsTieOrder() {
        let all = CoachDatabase.shared.searchExercises(
            search: nil, muscleSlugs: [], patternSlugs: [], modality: nil, difficulty: nil,
            environment: nil, compoundOnly: nil, userSportSlugs: []).exercises
        XCTAssertGreaterThan(all.count, 10)
        let favorite = all[7], liked = all[3], disliked = all[0]
        let out = ExerciseSearch.preferenceOrdered(
            all, affinities: [favorite.name: 3, liked.name: 1, disliked.name: -4])
        XCTAssertEqual(out[0].id, favorite.id)
        XCTAssertEqual(out[1].id, liked.id)
        XCTAssertEqual(out.count, all.count)
        let rest = out.dropFirst(2).map(\.id)
        let expected = all.map(\.id).filter { $0 != favorite.id && $0 != liked.id }
        XCTAssertEqual(rest, expected, "ties, including negatives, keep catalog order")
    }
}
