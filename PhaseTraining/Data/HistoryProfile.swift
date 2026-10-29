// HistoryProfile.swift — one pass over everything the lifter has recorded.
//
// Native sessions and imported sets go through the same cleaning and the
// same per-exercise analysis, so every consumer reads one answer:
// `GeneratorContext.priorBest`, the Log/Today "from history" suggestion,
// and (later) the exercise strength card, season-engine row weights and
// personal step sizes.
//
// Cleaning never deletes. A flagged set stays in its store and in History;
// it is only kept out of estimates, trends, steps and bests, and it is
// listed in `audit` so the History check sheet can show what was left out.
// Rules, measured against a real 2016-2026 Fitbod export after its unit era
// was converted (6 outliers, 1 duplicate block in ~5,000 sets):
//   - impossible: reps over 100 or more than 1,500 lb
//   - outlier: in a workout block of 3+ sets of one exercise, a set heavier
//     than 1.6x the block's median (a "2250" typed for 225)
//   - duplicate: the same exercise with an identical (weight, reps) sequence
//     at two timestamps within 36 hours; the later block is left out
// The thresholds are judgment calls; the History check list is where a
// wrong call shows up.

import Foundation

struct HistoryProfile: Equatable {

    enum Reason: Equatable {
        case impossible
        case outlier(blockMedianLb: Double)
        case duplicate(of: Date)
    }

    struct Flag: Equatable, Identifiable {
        let id: String
        let exercise: String
        let date: Date
        let weightLb: Double
        let reps: Int
        let reason: Reason
    }

    struct Layoff: Equatable {
        let from: Date
        let to: Date
        var days: Int { Int((to.timeIntervalSince(from) / 86_400).rounded()) }
    }

    struct Audit: Equatable {
        let flags: [Flag]
        let layoffs: [Layoff]

        var outlierSets: Int { flags.filter { if case .outlier = $0.reason { return true } else { return false } }.count }
        var impossibleSets: Int { flags.filter { $0.reason == .impossible }.count }
        /// Duplicate workouts, counted per (exercise, date) block.
        var duplicateBlocks: Int {
            Set(flags.compactMap { f -> String? in
                if case .duplicate = f.reason { return "\(f.exercise)|\(f.date.timeIntervalSince1970)" }
                return nil
            }).count
        }
        var isClean: Bool { flags.isEmpty }
    }

    enum Trend: Equatable {
        /// Percent change in estimated 1RM per month.
        case rising(Double), falling(Double), flat(Double)
        case unknown
    }

    /// One logged set, in lb.
    struct SetRecord: Equatable {
        let date: Date
        let weightLb: Double
        let reps: Int
    }

    /// One workout's best estimated 1RM, in lb.
    struct Point: Equatable {
        let date: Date
        let e1rm: Double
    }

    static let recentPoints = 12

    struct ExerciseProfile: Equatable {
        let name: String
        /// `ProvenStrength.estimate` over the cleaned evidence.
        let estimate: PriorBest?
        let trend: Trend
        let plateau: Bool
        /// The lifter's own usual jump between working weights, in lb.
        let typicalStepLb: Double?
        let lastTrained: Date
        let bestE1RM: Double
        let bestDate: Date
        let workouts: Int
        let excludedSets: Int
        /// Best set (by estimated 1RM) of the most recent workout.
        let latestBest: SetRecord
        /// Up to `recentPoints` session-best estimates, oldest first.
        let recentBests: [Point]
    }

    /// Keyed like every per-exercise map (`ExerciseKey`).
    let exercises: [String: ExerciseProfile]
    let audit: Audit

    static let empty = HistoryProfile(exercises: [:], audit: Audit(flags: [], layoffs: []))

    func profile(forExerciseNamed name: String) -> ExerciseProfile? {
        ExerciseKey.lookup(exercises, name: name)
    }

    /// Estimates only, in the shape `GeneratorContext.priorBest` uses.
    var priorBest: [String: PriorBest] {
        exercises.compactMapValues(\.estimate)
    }

    // MARK: - Tunables

    static let outlierRatio = 1.6
    static let duplicateWindow: TimeInterval = 36 * 3600
    static let maxReps = 100
    static let maxWeightLb = 1500.0
    static let layoffDays = 56.0
    static let trendWorkouts = 8
    static let trendWindowWeeks = 26.0
    static let trendMinWorkouts = 4
    static let trendMinSpanDays = 21.0
    static let flatPercentPerMonth = 1.0
    static let plateauWorkouts = 6
    static let stepWindowDays = 730.0
    static let stepMinJumps = 3

    // MARK: - Build

    private struct Entry {
        let id: String
        let key: String
        let name: String
        let date: Date
        let weightLb: Double
        let reps: Int
    }

    static func build(sessions: [SavedSession], imported: [ImportedSet], now: Date) -> HistoryProfile {
        let kgToLb = 1 / ImportUnitCorrection.kgPerLb
        var entries: [Entry] = []
        var rawNames: [String: Set<String>] = [:]
        var workoutDates: Set<Date> = []

        for session in sessions {
            workoutDates.insert(session.startTime)
            for (e, ex) in session.exercises.enumerated() {
                let key = ExerciseKey.id(for: ex.name) ?? ExerciseKey.raw(ex.name)
                rawNames[key, default: []].insert(ExerciseKey.raw(ex.name))
                for (s, set) in ex.sets.enumerated() where set.done && !set.isWarmup {
                    guard let w = set.weightValue, w > 0, let r = set.repsValue, r > 0 else { continue }
                    entries.append(Entry(id: "\(session.id)-\(e)-\(s)", key: key, name: ex.name,
                                         date: session.startTime, weightLb: w, reps: r))
                }
            }
        }
        let catalog = CoachDatabase.shared
        var catalogNames: [Int: String] = [:]
        for set in imported.sorted(by: { ($0.performedAt, $0.setNum) < ($1.performedAt, $1.setNum) }) {
            workoutDates.insert(set.performedAt)
            guard let id = set.exerciseId, let kg = set.weight, kg > 0, let r = set.reps, r > 0 else { continue }
            if catalogNames[id] == nil { catalogNames[id] = catalog.exercise(id: id)?.name ?? set.exerciseNameRaw }
            entries.append(Entry(id: set.id, key: "id:\(id)", name: catalogNames[id]!,
                                 date: set.performedAt, weightLb: kg * kgToLb, reps: r))
        }

        let flags = clean(entries)
        let flagged = Set(flags.map(\.id))
        let clean = entries.filter { !flagged.contains($0.id) }
        let excludedByKey = Dictionary(grouping: entries.filter { flagged.contains($0.id) }, by: \.key)
            .mapValues(\.count)

        var exercises: [String: ExerciseProfile] = [:]
        for (key, rows) in Dictionary(grouping: clean, by: \.key) {
            guard let p = profile(rows, excluded: excludedByKey[key] ?? 0, now: now) else { continue }
            if key.hasPrefix("id:") {
                exercises[key] = p
                if rawNames[key] == nil {
                    // Imported-only: key it by its catalog name too.
                    let raw = ExerciseKey.raw(p.name)
                    exercises[raw] = exercises[raw] ?? p
                }
            }
            for raw in rawNames[key] ?? [] { exercises[raw] = p }
        }

        let dates = workoutDates.sorted()
        let layoffs = zip(dates, dates.dropFirst()).compactMap { a, b -> Layoff? in
            b.timeIntervalSince(a) / 86_400 > layoffDays ? Layoff(from: a, to: b) : nil
        }
        return HistoryProfile(exercises: exercises,
                              audit: Audit(flags: flags.sorted { $0.date > $1.date }, layoffs: layoffs))
    }

    // MARK: - Cleaning

    private static func clean(_ entries: [Entry]) -> [Flag] {
        var flags: [Flag] = []
        func flag(_ e: Entry, _ reason: Reason) {
            flags.append(Flag(id: e.id, exercise: e.name, date: e.date, weightLb: e.weightLb, reps: e.reps, reason: reason))
        }

        var possible: [Entry] = []
        for e in entries {
            if e.reps > maxReps || e.weightLb > maxWeightLb { flag(e, .impossible) } else { possible.append(e) }
        }

        // Blocks keep the order the sets were logged in.
        var order: [String] = []
        var blocks: [String: [Entry]] = [:]
        for e in possible {
            let id = "\(e.key)|\(e.date.timeIntervalSince1970)"
            if blocks[id] == nil { order.append(id) }
            blocks[id, default: []].append(e)
        }

        var kept: [String: [Entry]] = [:]
        for id in order {
            let block = blocks[id]!
            guard block.count >= 3, let m = median(block.map(\.weightLb)) else { kept[id] = block; continue }
            kept[id] = block.filter { e in
                if e.weightLb > outlierRatio * m { flag(e, .outlier(blockMedianLb: m)); return false }
                return true
            }
        }

        // Duplicates: compare each block with the earlier blocks of the same
        // exercise inside the window.
        let byExercise = Dictionary(grouping: order.compactMap { id in kept[id].flatMap { $0.isEmpty ? nil : $0 } },
                                    by: { $0[0].key })
        for blocksForKey in byExercise.values {
            let sorted = blocksForKey.sorted { $0[0].date < $1[0].date }
            for (i, block) in sorted.enumerated() {
                let sig = signature(block)
                if let earlier = sorted[..<i].last(where: {
                    block[0].date.timeIntervalSince($0[0].date) <= duplicateWindow && signature($0) == sig
                }) {
                    for e in block { flag(e, .duplicate(of: earlier[0].date)) }
                }
            }
        }
        return flags
    }

    private static func signature(_ block: [Entry]) -> [String] {
        block.map { "\(($0.weightLb * 2).rounded() / 2)x\($0.reps)" }
    }

    // MARK: - Per exercise

    private static func profile(_ rows: [Entry], excluded: Int, now: Date) -> ExerciseProfile? {
        guard let last = rows.map(\.date).max() else { return nil }
        let estimate = ProvenStrength.estimate(rows.map { .init(date: $0.date, weightLb: $0.weightLb, reps: $0.reps) },
                                               now: now)

        // Session-best estimated 1RM, oldest first.
        let bests = Dictionary(grouping: rows.filter { ProvenStrength.repRange.contains($0.reps) }, by: \.date)
            .map { date, sets in (date: date, e1rm: sets.map { StrengthStandards.epley1RM(weight: $0.weightLb, reps: $0.reps) }.max()!) }
            .sorted { $0.date < $1.date }
        guard let best = bests.max(by: { $0.e1rm < $1.e1rm }) else { return nil }

        let windowStart = last.addingTimeInterval(-trendWindowWeeks * 7 * 86_400)
        let recent = Array(bests.filter { $0.date >= windowStart }.suffix(trendWorkouts))
        let trend = trendOf(recent)
        let plateau: Bool = {
            if case .flat = trend { return recent.count >= plateauWorkouts }
            return false
        }()

        let stepStart = last.addingTimeInterval(-stepWindowDays * 86_400)
        let weights = Set(rows.filter { $0.date >= stepStart }.map { ($0.weightLb * 2).rounded() / 2 }).sorted()
        let jumps = zip(weights, weights.dropFirst()).map { $1 - $0 }.filter { $0 >= 0.5 }
        let typicalStep: Double? = jumps.count >= stepMinJumps
            ? Dictionary(grouping: jumps, by: { $0 }).max { a, b in
                a.value.count == b.value.count ? a.key > b.key : a.value.count < b.value.count
              }?.key
            : nil

        let latestRows = rows.filter { $0.date == last && ProvenStrength.repRange.contains($0.reps) }
        let latest = (latestRows.isEmpty ? rows.filter { $0.date == last } : latestRows)
            .max { StrengthStandards.epley1RM(weight: $0.weightLb, reps: $0.reps)
                 < StrengthStandards.epley1RM(weight: $1.weightLb, reps: $1.reps) }!

        return ExerciseProfile(name: rows[0].name, estimate: estimate, trend: trend, plateau: plateau,
                               typicalStepLb: typicalStep, lastTrained: last,
                               bestE1RM: best.e1rm, bestDate: best.date,
                               workouts: bests.count, excludedSets: excluded,
                               latestBest: SetRecord(date: latest.date, weightLb: latest.weightLb, reps: latest.reps),
                               recentBests: bests.suffix(recentPoints).map { Point(date: $0.date, e1rm: $0.e1rm) })
    }

    /// Least-squares slope of session-best e1RM against time, as % of the
    /// mean per month.
    static func trendOf(_ points: [(date: Date, e1rm: Double)]) -> Trend {
        guard points.count >= trendMinWorkouts,
              let first = points.first?.date, let last = points.last?.date,
              last.timeIntervalSince(first) / 86_400 >= trendMinSpanDays else { return .unknown }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.e1rm)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let sxx = zip(xs, xs).map { ($0 - mx) * ($1 - mx) }.reduce(0, +)
        guard sxx > 0, my > 0 else { return .unknown }
        let slope = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +) / sxx
        let pct = slope * 30.44 / my * 100
        if abs(pct) < flatPercentPerMonth { return .flat(pct) }
        return pct > 0 ? .rising(pct) : .falling(pct)
    }

    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
