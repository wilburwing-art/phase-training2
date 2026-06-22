// ExerciseSwapMemoryTests.swift — the swap-memory feature: capture (a swap
// writes a preference into TrainingMemory) and consume (the generator weights
// its picks by that preference). See the slot picker's applyAffinityWeighting
// and MemoryStore.recordSwap.

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

    // MARK: - Consume (generator weights picks by affinity)

    private func liftMemory() -> TrainingMemory {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        return m
    }

    /// Generate a push day across `seeds` distinct seeds and tally how often
    /// each exercise name is picked. Affinity flows through the context exactly
    /// as PlanStore.buildGeneratorContext wires it in production.
    private func pickFrequencies(memory: TrainingMemory,
                                 affinities: [String: Int],
                                 seeds: Int) -> [String: Int] {
        let profile = DemographicProfile.from(memory)
        var ctx = GeneratorContext.empty
        ctx.exerciseAffinities = affinities
        var freq: [String: Int] = [:]
        for i in 0..<seeds {
            let w = WorkoutGenerator.generateLift(
                liftIndex: 0, totalLifts: 3,
                memory: memory, profile: profile,
                hashSeed: "swap-consume-\(i)", context: ctx)
            for ex in w.exercises { freq[ex.name, default: 0] += 1 }
        }
        return freq
    }

    /// Pick a deterministic target that appears in some-but-not-all seeds —
    /// `freq < seeds` guarantees its slot has alternatives to gain/lose share
    /// from. Highest such frequency wins (most statistical power), ties by name.
    private func partiallyPicked(in freq: [String: Int], seeds: Int, min: Int) -> String? {
        freq.filter { $0.value >= min && $0.value < seeds }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .first?.key
    }

    func test_boostingExercise_increasesItsPickFrequency() throws {
        let m = liftMemory()
        let seeds = 30
        let baseline = pickFrequencies(memory: m, affinities: [:], seeds: seeds)
        guard let target = partiallyPicked(in: baseline, seeds: seeds, min: 1) else {
            throw XCTSkip("No partially-picked exercise to boost in this catalog slice")
        }
        let boosted = pickFrequencies(memory: m, affinities: [target: 3], seeds: seeds)
        XCTAssertGreaterThan(boosted[target] ?? 0, baseline[target] ?? 0,
            "Boosting \(target) should raise its pick frequency across \(seeds) seeds " +
            "(\(baseline[target] ?? 0) → \(boosted[target] ?? 0))")
    }

    func test_stronglyDemotingExercise_dropsItsPickFrequency() throws {
        let m = liftMemory()
        let seeds = 30
        let baseline = pickFrequencies(memory: m, affinities: [:], seeds: seeds)
        guard let target = partiallyPicked(in: baseline, seeds: seeds, min: 2) else {
            throw XCTSkip("No partially-picked exercise to demote in this catalog slice")
        }
        // ≤ -2 sinks the candidate entirely; since its slot has alternatives
        // (freq < seeds), it should disappear from the picks.
        let demoted = pickFrequencies(memory: m, affinities: [target: -3], seeds: seeds)
        XCTAssertLessThan(demoted[target] ?? 0, baseline[target] ?? 0,
            "Strongly demoting \(target) should lower its pick frequency " +
            "(\(baseline[target] ?? 0) → \(demoted[target] ?? 0))")
    }
}
