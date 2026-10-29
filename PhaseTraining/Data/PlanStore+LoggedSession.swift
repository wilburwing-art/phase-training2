// PlanStore+LoggedSession.swift — what a saved session changes about the week.
//
// Two reactions, both run from `SessionStore.onSessionSaved`:
//
// 1. Rotation follows what was logged. `recentPicks` is stamped with the
//    exercises the athlete actually did, at the session's time. Generation no
//    longer stamps its own picks, so a skipped workout does not count as
//    recent and a full rebuild does not reshuffle untouched days.
//
// 2. An off-plan session takes over the day it covered. Log legs on Tuesday
//    when Tuesday was upper body and Wednesday is legs: Wednesday is done in
//    all but name, so Tuesday and Wednesday swap and the upper-body session
//    Tuesday skipped moves to Wednesday. Done through `swap`, so the move
//    survives regeneration and the move banner explains it.

import Foundation

extension PlanStore {

    /// Muscle groups a session has to load (set-equivalents, primary 1.0 and
    /// secondary 0.5) before it counts as having trained them.
    static let coveredBucketLoad = 3.0

    /// Share of a planned workout's sets the log has to cover.
    static let coveredShare = 0.5

    /// Stamp the logged exercises into the variety memory.
    func recordLoggedPicks(_ session: SavedSession) {
        let db = CoachDatabase.shared
        let ids = session.exercises
            .filter { $0.sets.contains { $0.done && !$0.isWarmup } }
            .compactMap { ex in
                db.listExercises(search: ex.name)
                    .first { $0.name.caseInsensitiveCompare(ex.name) == .orderedSame }?.id
            }
        recentPicks?.record(exerciseIds: ids, at: session.startTime)
    }

    /// MuscleBucket raw values the session trained enough to count.
    static func coveredBuckets(by session: SavedSession,
                               resolve: MuscleVolume.NameResolver = MuscleVolume.defaultResolve) -> Set<String> {
        var load: [String: Double] = [:]
        for exposure in MuscleFreshness.exposures(from: [session], resolve: resolve) {
            for (slug, l) in exposure.loads {
                guard let bucket = MuscleBucket.bucket(forSlug: slug)?.rawValue else { continue }
                load[bucket, default: 0] += l
            }
        }
        return Set(load.filter { $0.value >= coveredBucketLoad }.keys)
    }

    /// Share of `workout`'s sets whose prime mover is in `buckets`.
    static func coverage(of workout: GeneratedWorkout, by buckets: Set<String>) -> Double {
        let total = workout.exercises.reduce(0) { $0 + $1.sets }
        guard total > 0 else { return 0 }
        let covered = workout.exercises
            .filter { !WorkoutGenerator.primaryMuscleBuckets(exerciseId: $0.exerciseId).isDisjoint(with: buckets) }
            .reduce(0) { $0 + $1.sets }
        return Double(covered) / Double(total)
    }

    /// If `session` ran off plan and covered a later lift day this week, swap
    /// that day with the session's day. Returns the covered day's date.
    @discardableResult
    func takeOverCoveredDay(for session: SavedSession, abandoned: Bool,
                            memory: TrainingMemory,
                            today: Date = Date(),
                            resolve: MuscleVolume.NameResolver = MuscleVolume.defaultResolve) -> Date? {
        guard !abandoned, let plan,
              let outcome = dayOutcomes.first(where: { $0.sessionId == session.id }),
              outcome.kind == .switched || outcome.kind == .unplanned
        else { return nil }
        let cal = Calendar.current
        guard let logDay = plan.days.first(where: { cal.isDate($0.date, inSameDayAs: session.startTime) }),
              logDay.kind == .lift || logDay.kind == .rest
        else { return nil }
        let buckets = Self.coveredBuckets(by: session, resolve: resolve)
        guard !buckets.isEmpty else { return nil }
        // A log that also covers the day's own plan replaced that session; it
        // did not do a later one early.
        if logDay.kind == .lift, let own = logDay.generatedWorkout,
           Self.coverage(of: own, by: buckets) >= Self.coveredShare {
            return nil
        }
        let logStart = cal.startOfDay(for: logDay.date)
        guard let covered = plan.days.first(where: { day in
            cal.startOfDay(for: day.date) > logStart
                && day.kind == .lift
                && !day.protected
                && day.routineId == nil
                && overrides.customRoutineId(for: day.date) == nil
                && day.generatedWorkout.map { Self.coverage(of: $0, by: buckets) >= Self.coveredShare } == true
        }) else { return nil }
        swap(sourceDate: logDay.date, targetDate: covered.date, memory: memory, today: today)
        lastMove?.coveredTitle = covered.title
        return covered.date
    }
}
