// PlanStoreSeamsTests.swift — characterization tests for PlanStore's
// non-generation seams:
//
//   - makeGeneratorContext / buildGeneratorContext: the public context seam
//     WeeklyCheckInFlow uses, and the store-wiring + soreness-window rules
//     behind it.
//   - applyCustomRoutineOverrides + composeWorkout(fromCustom:) (build 105):
//     exercised through generate(from:) since both are private post-processing
//     steps. Includes the override-exclusion contract (nil refinedByLLMAt →
//     refinementCandidates skips the day) that keeps the background LLM pass
//     from rerolling a user's saved-workout pick.
//   - captureRolloverIfNeeded: once-per-week-transition snapshot, idempotent.
//   - reloadFromDefaults: backup-restore re-read path; corrupt/absent blobs
//     degrade to a safe empty state.

import XCTest
@testable import PhaseTraining

final class PlanStoreSeamsTests: XCTestCase {

    // MARK: - Fixtures

    /// Fixed Monday anchor (2026-05-11) so week math is deterministic.
    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        return Calendar.current.date(from: c)!
    }

    private func freshDefaults(_ tag: String = #function) -> UserDefaults {
        let suite = "PlanStoreSeamsTests.\(tag).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeStore(today: Date? = nil, tag: String = #function) -> PlanStore {
        PlanStore(defaults: freshDefaults(tag), today: today ?? monday())
    }

    private func gymMemory() -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 3
        return m
    }

    /// Isolated SessionStore (in-memory SQLite, fresh suite) for wiring into
    /// PlanStore. Tests assign `savedSessions` directly.
    private func emptySessionStore() -> SessionStore {
        SessionStore(defaults: freshDefaults("session-stub"),
                     userDB: UserDatabase(path: ":memory:"))
    }

    /// Isolated CustomRoutineStore with the given routines pre-loaded.
    private func customStore(with routines: [CustomRoutine]) -> CustomRoutineStore {
        let s = CustomRoutineStore(defaults: freshDefaults("custom-stub"),
                                   userDB: UserDatabase(path: ":memory:"))
        s.routines = routines
        return s
    }

    private func savedSession(name: String, weight: String, reps: String,
                              startTime: Date) -> SavedSession {
        let logged = LoggedExercise(
            id: name, name: name, type: nil, unit: "lbs",
            targetSets: 1, targetReps: 5, rest: 90,
            sets: [LoggedSet(num: 1, weight: weight, reps: reps, rpe: "", done: true)],
            prevSets: [])
        return SavedSession(
            templateId: "t", name: name, category: "",
            startTime: startTime, exercises: [logged], feel: nil, note: nil,
            endTime: startTime.addingTimeInterval(3600), duration: 3600)
    }

    private func customExercise(_ idx: Int, exerciseId: Int,
                                sets: Int?, reps: String?, rest: String?,
                                notes: String? = nil) -> CustomRoutineExercise {
        CustomRoutineExercise(id: "cex-\(idx)", exerciseId: exerciseId,
                              name: "Exercise \(idx)", position: idx,
                              sets: sets, reps: reps, rest: rest,
                              notes: notes, supersetGroup: nil)
    }

    /// Hand-built 7-day plan anchored to `start`. Lift days carry a minimal
    /// GeneratedWorkout so rollover snapshots have realistic shape.
    private func makePlan(_ kinds: [DayKind], anchoredTo start: Date,
                          hash: String = "fixture") -> WeekPlan {
        precondition(kinds.count == 7)
        let cal = Calendar.current
        let days = (0..<7).map { i -> DayPlan in
            let kind = kinds[i]
            return DayPlan(
                date: cal.date(byAdding: .day, value: i, to: start) ?? start,
                kind: kind,
                title: kind == .lift ? "Push day" : "Rest",
                routineId: nil,
                generatedWorkout: kind == .lift ? GeneratedWorkout(
                    title: "Push day", summary: "", exercises: [],
                    estimatedMinutes: 60, provenance: "") : nil)
        }
        return WeekPlan(days: days, generatedAt: start, inputsHash: hash)
    }

    /// Matches PlanStore's persistence codec (secondsSince1970 dates).
    private func planEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    // MARK: - makeGeneratorContext (store wiring)

    func test_makeGeneratorContext_returnsEmptyWhenSessionStoreAbsent() {
        let store = makeStore()
        // Even with soreness on the memory, an unwired sessionStore must
        // short-circuit to .empty — the documented test/preview behavior.
        var memory = gymMemory()
        var sore = SorenessEntry(date: Calendar.current.date(byAdding: .day, value: -1, to: monday())!)
        sore.areas = ["quads"]
        memory.soreness = [sore]

        let ctx = store.makeGeneratorContext(memory: memory, today: monday())
        XCTAssertEqual(ctx, GeneratorContext.empty,
                       "no sessionStore wired → exactly the .empty context")
        XCTAssertTrue(ctx.isEmpty)
    }

    func test_makeGeneratorContext_wiresSessionHistoryIntoPriorBestAndReadiness() {
        let today = monday()
        let store = makeStore()
        let sessions = emptySessionStore()
        sessions.savedSessions = [
            savedSession(name: "Bench Press", weight: "225", reps: "5",
                         startTime: Calendar.current.date(byAdding: .day, value: -3, to: today)!)
        ]
        store.sessionStore = sessions

        let ctx = store.makeGeneratorContext(memory: gymMemory(), today: today)
        XCTAssertEqual(ctx.priorBest["bench press"]?.weight, 225)
        XCTAssertEqual(ctx.priorBest["bench press"]?.reps, 5)
        XCTAssertTrue(ctx.hasReadinessData,
                      "a session 3 days ago is inside the 28-day readiness window")
    }

    func test_makeGeneratorContext_countsRecentHardSportDays() throws {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        store.sessionStore = emptySessionStore()

        let sportLogs = SportLogStore(defaults: freshDefaults("sport-stub"))
        let climbing = try XCTUnwrap(Sport.catalog.first { $0.slug == "climbing" })
        sportLogs.log(sport: climbing, on: cal.date(byAdding: .day, value: -1, to: today)!,
                      durationMinutes: 90, intensity: .hard, now: today)
        sportLogs.log(sport: climbing, on: cal.date(byAdding: .day, value: -2, to: today)!,
                      durationMinutes: 90, intensity: .hard, now: today)
        sportLogs.log(sport: climbing, on: cal.date(byAdding: .day, value: -3, to: today)!,
                      durationMinutes: 60, intensity: .moderate, now: today)
        store.sportLogStore = sportLogs

        let ctx = store.makeGeneratorContext(memory: gymMemory(), today: today)
        XCTAssertEqual(ctx.recentHardSportDays, 2,
                       "two distinct hard days in window; the moderate day doesn't count")
    }

    // MARK: - buildGeneratorContext signals (via the public seam)

    func test_generatorContext_sorenessWindow_keepsRecentDropsStale() {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        store.sessionStore = emptySessionStore()

        var memory = gymMemory()
        var recent = SorenessEntry(date: cal.date(byAdding: .day, value: -2, to: today)!)
        recent.areas = ["quads"]
        var stale = SorenessEntry(date: cal.date(byAdding: .day, value: -10, to: today)!)
        stale.areas = ["back"]
        memory.soreness = [recent, stale]

        let ctx = store.makeGeneratorContext(memory: memory, today: today)
        XCTAssertTrue(ctx.recentSoreAreas.contains("quads"),
                      "2-day-old soreness is inside the 7-day window")
        XCTAssertFalse(ctx.recentSoreAreas.contains("back"),
                       "10-day-old soreness is outside the 7-day window")
    }

    func test_generatorContext_feedbackHurtAreasFlowThrough() {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        store.sessionStore = emptySessionStore()

        var memory = gymMemory()
        memory.feedback = [FeedbackEntry(
            date: cal.date(byAdding: .day, value: -1, to: today)!,
            sessionId: "s1",
            difficulty: "right",
            hurtAreas: ["Shoulder"],
            ranLong: false, notes: nil
        )]

        let ctx = store.makeGeneratorContext(memory: memory, today: today)
        XCTAssertTrue(ctx.recentSoreAreas.contains("shoulder"),
                      "hurt areas union into recentSoreAreas, lowercased")
    }

    // MARK: - Custom-routine overrides (build 105 post-processing)

    func test_generate_customOverride_replacesLiftDayWorkout() throws {
        let today = monday()
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        let routine = CustomRoutine(
            id: "rid-legs", name: "Garage Legs",
            exercises: [customExercise(0, exerciseId: 101, sets: 4, reps: "6-8", rest: "90s")],
            createdAt: today)
        store.customStore = customStore(with: [routine])
        store.updateOverrides(today: today) { $0.customRoutineByDate[liftDay.date] = routine.id }

        let regen = store.generate(from: memory, today: today)
        let cal = Calendar.current
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: liftDay.date) })
        XCTAssertEqual(day.title, "Garage Legs")
        XCTAssertEqual(day.kind, .lift)
        XCTAssertNil(day.routineId, "override days drop any bundled-routine reference")
        XCTAssertEqual(day.generatedReason, "Your saved workout")
        XCTAssertEqual(day.generatedWorkout?.provenance, "From your saved workouts")
        XCTAssertEqual(day.generatedWorkout?.exercises.map(\.exerciseId), [101])
    }

    func test_generate_customOverride_leavesNonOverrideDaysUntouched() throws {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        let routine = CustomRoutine(
            id: "rid-legs", name: "Garage Legs",
            exercises: [customExercise(0, exerciseId: 101, sets: 3, reps: "10", rest: nil)],
            createdAt: today)
        store.customStore = customStore(with: [routine])
        store.updateOverrides(today: today) { $0.customRoutineByDate[liftDay.date] = routine.id }

        let regen = store.generate(from: memory, today: today)
        XCTAssertEqual(regen.days.count, baseline.days.count)
        for (idx, day) in regen.days.enumerated() where !cal.isDate(day.date, inSameDayAs: liftDay.date) {
            XCTAssertEqual(day.title, baseline.days[idx].title,
                           "non-override day \(idx) title should match the baseline regen")
            XCTAssertEqual(day.kind, baseline.days[idx].kind,
                           "non-override day \(idx) kind should match the baseline regen")
            XCTAssertNotEqual(day.generatedReason, "Your saved workout",
                              "only the override day carries the saved-workout reason")
        }
    }

    func test_generate_customOverride_convertsRestDayToLift() throws {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let restDay = try XCTUnwrap(baseline.days.first { $0.kind == .rest },
                                    "3-lift week should contain a rest day")

        let routine = CustomRoutine(
            id: "rid-extra", name: "Bonus Pump",
            exercises: [customExercise(0, exerciseId: 55, sets: 3, reps: "12", rest: nil)],
            createdAt: today)
        store.customStore = customStore(with: [routine])
        store.updateOverrides(today: today) { $0.customRoutineByDate[restDay.date] = routine.id }

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: restDay.date) })
        XCTAssertEqual(day.kind, .lift,
                       "a custom workout scheduled on a rest day flips the day to lift")
        XCTAssertEqual(day.title, "Bonus Pump")
        XCTAssertNotNil(day.generatedWorkout)
    }

    func test_generate_customOverride_missingRoutineIdIsNoop() throws {
        let today = monday()
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        // customStore is wired but holds no routine with this id (deleted).
        store.customStore = customStore(with: [])
        store.updateOverrides(today: today) { $0.customRoutineByDate[liftDay.date] = "ghost-id" }

        let regen = store.generate(from: memory, today: today)
        XCTAssertEqual(regen.days.map(\.title), baseline.days.map(\.title),
                       "a dangling routine id must leave every day as the planner built it")
        XCTAssertFalse(regen.days.contains { $0.generatedReason == "Your saved workout" })
    }

    func test_generate_customOverride_withoutCustomStoreIsNoop() throws {
        let today = monday()
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        // Override recorded but no customStore wired (pre-build-105 regression path).
        store.updateOverrides(today: today) { $0.customRoutineByDate[liftDay.date] = "rid-legs" }

        let regen = store.generate(from: memory, today: today)
        XCTAssertEqual(regen.days.map(\.title), baseline.days.map(\.title),
                       "no customStore → override picks gracefully have no effect")
        XCTAssertFalse(regen.days.contains { $0.generatedReason == "Your saved workout" })
    }

    // MARK: - composeWorkout(fromCustom:) mapping (via the override path)

    func test_composeFromCustom_mapsPrescriptionsAndParsesRest() throws {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let targetDate = baseline.days[0].date

        let routine = CustomRoutine(
            id: "rid-map", name: "Mapping Check",
            exercises: [
                customExercise(0, exerciseId: 11, sets: 4, reps: "6-8", rest: "2:00", notes: "slow eccentric"),
                customExercise(1, exerciseId: 22, sets: nil, reps: nil, rest: nil),
                customExercise(2, exerciseId: 33, sets: 3, reps: "10", rest: "90s"),
                customExercise(3, exerciseId: 44, sets: 3, reps: "12", rest: "1 min"),
            ],
            createdAt: today)
        store.customStore = customStore(with: [routine])
        store.updateOverrides(today: today) { $0.customRoutineByDate[targetDate] = routine.id }

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: targetDate) })
        let workout = try XCTUnwrap(day.generatedWorkout)

        XCTAssertEqual(workout.title, "Mapping Check")
        XCTAssertEqual(workout.exercises.count, 4)

        // Exercise 0: fully specified.
        let ex0 = workout.exercises[0]
        XCTAssertEqual(ex0.id, "custom-rid-map-0")
        XCTAssertEqual(ex0.exerciseId, 11)
        XCTAssertEqual(ex0.sets, 4)
        XCTAssertEqual(ex0.reps, "6-8")
        XCTAssertEqual(ex0.restSeconds, 120, "\"2:00\" parses as minutes:seconds")
        XCTAssertEqual(ex0.notes, "slow eccentric")
        XCTAssertFalse(ex0.isCompound)
        XCTAssertNil(ex0.pattern)
        XCTAssertNil(ex0.rpe)
        XCTAssertNil(ex0.tempo)
        XCTAssertEqual(ex0.source, .recipe)

        // Exercise 1: bare → fallback prescription.
        let ex1 = workout.exercises[1]
        XCTAssertEqual(ex1.sets, 3, "nil sets falls back to 3")
        XCTAssertEqual(ex1.reps, "8-12", "nil reps falls back to 8-12")
        XCTAssertEqual(ex1.restSeconds, 90, "nil rest falls back to 90s")
        XCTAssertNil(ex1.notes)

        // Rest-string variants.
        XCTAssertEqual(workout.exercises[2].restSeconds, 90, "\"90s\" parses to 90")
        XCTAssertEqual(workout.exercises[3].restSeconds, 60, "\"1 min\" parses to 60")

        // Duration estimate: 13 sets × 90s / 60 = 19 min.
        XCTAssertEqual(workout.estimatedMinutes, 19)
        XCTAssertEqual(workout.summary, "4 movements · ~19 min")
    }

    /// The override-exclusion contract from PlanStore+LLMRefinement: a
    /// custom-composed workout carries nil refinedByLLMAt AND the candidate
    /// filter skips the override day, so the background LLM pass can never
    /// reroll the user's saved-workout pick.
    func test_composeFromCustom_nilRefinedByLLMAt_excludedFromRefinementCandidates() throws {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        let routine = CustomRoutine(
            id: "rid-pin", name: "Pinned Day",
            exercises: [customExercise(0, exerciseId: 7, sets: 3, reps: "8", rest: nil)],
            createdAt: today)
        store.customStore = customStore(with: [routine])
        store.updateOverrides(today: today) { $0.customRoutineByDate[liftDay.date] = routine.id }

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: liftDay.date) })
        XCTAssertNil(day.generatedWorkout?.refinedByLLMAt,
                     "custom-composed workouts must NOT look LLM-refined")

        let candidates = store.refinementCandidates(in: regen)
        XCTAssertFalse(candidates.contains { cal.isDate($0.day.date, inSameDayAs: liftDay.date) },
                       "the override day must be excluded from refinement candidates")
        XCTAssertFalse(candidates.isEmpty,
                       "the other lift days remain refinement candidates")
        for candidate in candidates {
            XCTAssertEqual(candidate.day.kind, .lift)
            XCTAssertNil(candidate.day.generatedWorkout?.refinedByLLMAt)
        }

        // Already-refined days drop out too (refinement is per-plan-version).
        var refinedPlan = regen
        let candidateIdx = try XCTUnwrap(candidates.first?.index)
        refinedPlan.days[candidateIdx].generatedWorkout?.refinedByLLMAt = today
        let after = store.refinementCandidates(in: refinedPlan)
        XCTAssertEqual(after.count, candidates.count - 1,
                       "stamping refinedByLLMAt removes that day from the candidate set")
    }

    func test_composeFromCustom_emptyNameAndSingleExerciseFallbacks() throws {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let targetDate = baseline.days[0].date

        let routine = CustomRoutine(
            id: "rid-unnamed", name: "",
            exercises: [customExercise(0, exerciseId: 9, sets: nil, reps: nil, rest: nil)],
            createdAt: today)
        store.customStore = customStore(with: [routine])
        store.updateOverrides(today: today) { $0.customRoutineByDate[targetDate] = routine.id }

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: targetDate) })
        XCTAssertEqual(day.title, "Custom workout", "empty routine name falls back")
        XCTAssertEqual(day.generatedWorkout?.title, "Custom workout")
        XCTAssertEqual(day.generatedWorkout?.summary, "1 movement · ~15 min",
                       "singular movement label + 15-minute floor on the estimate")
        XCTAssertEqual(day.generatedWorkout?.estimatedMinutes, 15)
    }

    // MARK: - captureRolloverIfNeeded

    func test_captureRollover_capturesPastWeekOnce_idempotentOnRepeat() {
        let today = monday()
        let cal = Calendar.current
        let lastMonday = cal.date(byAdding: .day, value: -7, to: today)!
        let store = makeStore()
        // Assign directly (not setPlan) so nothing has snapshotted yet —
        // mirrors a persisted plan loaded from a prior week.
        store.plan = makePlan([.lift, .rest, .lift, .rest, .lift, .rest, .rest],
                              anchoredTo: lastMonday)

        store.captureRolloverIfNeeded(today: today)
        XCTAssertEqual(store.pastPlans.count, 1)
        XCTAssertTrue(cal.isDate(store.pastPlans[0].weekStart, inSameDayAs: lastMonday))
        XCTAssertEqual(store.pastPlans[0].capturedAt, today)

        // Repeat call (e.g. app re-foregrounded Tuesday) — no second capture,
        // and the original snapshot is preserved, not replaced.
        store.captureRolloverIfNeeded(today: cal.date(byAdding: .day, value: 1, to: today)!)
        XCTAssertEqual(store.pastPlans.count, 1, "rollover capture is once per week transition")
        XCTAssertEqual(store.pastPlans[0].capturedAt, today,
                       "repeat call must not re-capture over the existing snapshot")
    }

    func test_captureRollover_skipsCurrentWeekPlan() {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        store.plan = makePlan([.lift, .rest, .lift, .rest, .lift, .rest, .rest],
                              anchoredTo: today)

        // Mid-week call against the in-flight week — setPlan owns that capture.
        store.captureRolloverIfNeeded(today: cal.date(byAdding: .day, value: 2, to: today)!)
        XCTAssertTrue(store.pastPlans.isEmpty,
                      "the current week must not be snapshotted by the rollover path")
    }

    func test_captureRollover_noopWithoutPlan() {
        let store = makeStore()
        XCTAssertNil(store.plan)
        store.captureRolloverIfNeeded(today: monday())
        XCTAssertTrue(store.pastPlans.isEmpty)
    }

    func test_init_capturesRolloverFromPersistedPriorWeekPlan() throws {
        let today = monday()
        let cal = Calendar.current
        let lastMonday = cal.date(byAdding: .day, value: -7, to: today)!
        let defaults = freshDefaults()

        // Persist a prior-week plan the way PlanStore would have.
        let stalePlan = makePlan([.lift, .rest, .lift, .rest, .lift, .rest, .rest],
                                 anchoredTo: lastMonday, hash: "prior-week")
        defaults.set(try planEncoder().encode(stalePlan), forKey: "pt_week_plan")

        // Opening the app on the new Monday: init must snapshot the old week.
        let store = PlanStore(defaults: defaults, today: today)
        XCTAssertEqual(store.pastPlans.count, 1)
        XCTAssertTrue(cal.isDate(store.pastPlans[0].weekStart, inSameDayAs: lastMonday))
        XCTAssertEqual(store.plan?.inputsHash, "prior-week",
                       "the stale plan stays loaded — capture doesn't clear it")
    }

    // MARK: - reloadFromDefaults

    func test_reloadFromDefaults_roundTripsPlanAndOverrides() {
        let today = monday()
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: today)
        let memory = gymMemory()
        let generated = store.generate(from: memory, today: today)
        store.updateOverrides(today: today) { o in
            o.unavailableDays.insert(.friday)
            o.customRoutineByDate[today] = "rid-1"
        }

        // Clobber the in-memory state WITHOUT touching defaults — simulates
        // the live store having drifted from what a backup-restore just wrote.
        store.plan = nil
        store.overrides = WeekOverrides(weekStart: today.addingTimeInterval(-7 * 86_400))

        store.reloadFromDefaults(today: today)
        XCTAssertEqual(store.plan?.inputsHash, generated.inputsHash)
        XCTAssertEqual(store.plan?.days.map(\.title), generated.days.map(\.title))
        XCTAssertTrue(store.overrides.unavailableDays.contains(.friday))
        XCTAssertEqual(store.overrides.customRoutineId(for: today), "rid-1")
        XCTAssertTrue(Calendar.current.isDate(store.overrides.weekStart, inSameDayAs: today))
    }

    func test_reloadFromDefaults_corruptBlobsYieldSafeEmptyState() {
        let today = monday()
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: today)
        _ = store.generate(from: gymMemory(), today: today)
        XCTAssertNotNil(store.plan)

        defaults.set(Data("definitely not json".utf8), forKey: "pt_week_plan")
        defaults.set(Data([0xFF, 0x00, 0x42]), forKey: "pt_week_overrides")

        store.reloadFromDefaults(today: today)
        XCTAssertNil(store.plan, "undecodable plan blob → nil plan, no crash")
        XCTAssertTrue(Calendar.current.isDate(store.overrides.weekStart, inSameDayAs: today))
        XCTAssertTrue(store.overrides.dayOverrides.isEmpty)
        XCTAssertTrue(store.overrides.customRoutineByDate.isEmpty)
    }

    func test_reloadFromDefaults_absentKeysClearPlan() {
        let today = monday()
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: today)
        _ = store.generate(from: gymMemory(), today: today)
        XCTAssertNotNil(store.plan)

        defaults.removeObject(forKey: "pt_week_plan")
        defaults.removeObject(forKey: "pt_week_overrides")

        store.reloadFromDefaults(today: today)
        XCTAssertNil(store.plan, "a restore that wiped the plan key must clear the live plan")
        XCTAssertTrue(store.overrides.unavailableDays.isEmpty)
    }

    func test_reloadFromDefaults_staleWeekOverridesResetToCurrentWeek() throws {
        let today = monday()
        let cal = Calendar.current
        let lastMonday = cal.date(byAdding: .day, value: -7, to: today)!
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: today)

        // Persist overrides anchored to LAST week — fresh-every-week semantics
        // say these must be discarded on reload.
        var stale = WeekOverrides(weekStart: lastMonday)
        stale.unavailableDays.insert(.friday)
        defaults.set(try planEncoder().encode(stale), forKey: "pt_week_overrides")

        store.reloadFromDefaults(today: today)
        XCTAssertTrue(cal.isDate(store.overrides.weekStart, inSameDayAs: today),
                      "stale weekStart → fresh overrides anchored to the current Monday")
        XCTAssertTrue(store.overrides.unavailableDays.isEmpty,
                      "last week's unavailable days must not leak into this week")
    }

    // MARK: - Prescription refresh (shape B of the saved-workout load options)

    /// Two REAL coach.db exercises from the horizontal-push pool — refresh
    /// tests must resolve real rows (a fake id hits the dangling-id keep
    /// path) and priorBest keys on the real lowercased name.
    private func realPushPair() throws -> (a: Exercise, b: Exercise) {
        let pool = CoachDatabase.shared.exercises(matchingPattern: "horizontal-push")
        let a = try XCTUnwrap(pool.first, "coach.db must have horizontal-push exercises")
        let b = try XCTUnwrap(pool.dropFirst().first)
        return (a, b)
    }

    /// Store with a 2-exercise custom routine scheduled on the first lift
    /// day, plus the given refresh mode. Returns the override date.
    private func refreshFixture(mode: PrescriptionRefreshMode?,
                                notes: String? = nil,
                                today: Date) throws -> (store: PlanStore, memory: TrainingMemory, date: Date) {
        let (a, b) = try realPushPair()
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        let routine = CustomRoutine(
            id: "rid-refresh",
            name: "Refresh Check",
            exercises: [
                CustomRoutineExercise(id: "cex-0", exerciseId: a.id, name: a.name,
                                      position: 0, sets: 4, reps: "8-12", rest: "90s",
                                      notes: notes, supersetGroup: nil),
                CustomRoutineExercise(id: "cex-1", exerciseId: b.id, name: b.name,
                                      position: 1, sets: 3, reps: "10", rest: "60s",
                                      notes: nil, supersetGroup: nil),
            ],
            createdAt: today)
        store.customStore = customStore(with: [routine])
        store.updateOverrides(today: today) {
            $0.customRoutineByDate[liftDay.date] = routine.id
            if let mode { $0.setPrescriptionRefresh(mode, for: liftDay.date) }
        }
        return (store, memory, liftDay.date)
    }

    func test_generate_refreshFull_keepsExerciseIdentityAndOrder() throws {
        let today = monday()
        let cal = Calendar.current
        let (a, b) = try realPushPair()
        let (store, memory, date) = try refreshFixture(mode: .fullRefresh, today: today)

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: date) })
        let workout = try XCTUnwrap(day.generatedWorkout)

        XCTAssertEqual(workout.exercises.map(\.exerciseId), [a.id, b.id],
                       "fullRefresh must never re-pick or reorder exercises")
        XCTAssertEqual(workout.exercises.map(\.name), [a.name, b.name])
        XCTAssertEqual(workout.exercises.map(\.id), ["custom-rid-refresh-0", "custom-rid-refresh-1"],
                       "stored row ids survive (session pairing depends on them)")
    }

    func test_generate_refreshFull_appliesGeneratorPrescriptions_andKeepsUserNote() throws {
        let today = monday()
        let cal = Calendar.current
        let (store, memory, date) = try refreshFixture(
            mode: .fullRefresh, notes: "keep elbows in", today: today)

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: date) })
        let row0 = try XCTUnwrap(day.generatedWorkout?.exercises.first)

        // Generator-grade markers compose never produces: RPE + tempo cues.
        XCTAssertNotNil(row0.rpe, "fullRefresh rows carry the generator's RPE cue")
        XCTAssertNotNil(row0.tempo, "fullRefresh rows carry the generator's tempo cue")
        // The user's own note is merged, not clobbered.
        XCTAssertTrue(row0.notes?.contains("keep elbows in") == true,
                      "user note must survive the refresh; got \(row0.notes ?? "nil")")
        XCTAssertNil(day.generatedWorkout?.refinedByLLMAt,
                     "refreshed workouts must NOT look LLM-refined")
    }

    func test_generate_refreshFull_survivesSecondGenerate_andIsDeterministic() throws {
        let today = monday()
        let cal = Calendar.current
        let (store, memory, date) = try refreshFixture(mode: .fullRefresh, today: today)

        let first = store.generate(from: memory, today: today)
        let second = store.generate(from: memory, today: today)
        let d1 = try XCTUnwrap(first.days.first { cal.isDate($0.date, inSameDayAs: date) })
        let d2 = try XCTUnwrap(second.days.first { cal.isDate($0.date, inSameDayAs: date) })

        XCTAssertEqual(d1.generatedWorkout?.exercises, d2.generatedWorkout?.exercises,
                       "the refresh is re-derived identically on every generate()")
    }

    func test_generate_refreshWeightsOnly_preservesSetsRepsRest_recomputesTarget() throws {
        let today = monday()
        let cal = Calendar.current
        let (a, _) = try realPushPair()
        let (store, memory, date) = try refreshFixture(mode: .weightsOnly, today: today)
        let sessions = emptySessionStore()
        sessions.savedSessions = [
            savedSession(name: a.name, weight: "225", reps: "5",
                         startTime: cal.date(byAdding: .day, value: -3, to: today)!)
        ]
        store.sessionStore = sessions

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: date) })
        let row0 = try XCTUnwrap(day.generatedWorkout?.exercises.first)

        XCTAssertEqual(row0.sets, 4, "weightsOnly keeps stored sets")
        XCTAssertEqual(row0.reps, "8-12", "weightsOnly keeps stored reps")
        XCTAssertEqual(row0.restSeconds, 90, "weightsOnly keeps stored rest")
        XCTAssertNil(row0.rpe, "weightsOnly must not add prescription cues")
        XCTAssertNil(row0.tempo)
        XCTAssertTrue(row0.notes?.contains("target:") == true,
                      "weightsOnly recomputes the overload target; got \(row0.notes ?? "nil")")
    }

    func test_generate_refreshWeightsOnly_noPriorBest_leavesRowUntouched() throws {
        let today = monday()
        let cal = Calendar.current
        let (store, memory, date) = try refreshFixture(mode: .weightsOnly, today: today)
        // No sessionStore wired → empty context → no priorBest.

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: date) })
        let row0 = try XCTUnwrap(day.generatedWorkout?.exercises.first)

        XCTAssertEqual(row0.sets, 4)
        XCTAssertEqual(row0.reps, "8-12")
        XCTAssertEqual(row0.restSeconds, 90)
        XCTAssertNil(row0.notes, "no priorBest and no user note → row unchanged")
    }

    func test_generate_refresh_unresolvableExerciseId_keepsStoredRow() throws {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        let routine = CustomRoutine(
            id: "rid-dangle", name: "Dangling",
            exercises: [CustomRoutineExercise(id: "cex-0", exerciseId: 999_999,
                                              name: "Ghost Press", position: 0,
                                              sets: 5, reps: "6", rest: "120s",
                                              notes: nil, supersetGroup: nil)],
            createdAt: today)
        store.customStore = customStore(with: [routine])
        store.updateOverrides(today: today) {
            $0.customRoutineByDate[liftDay.date] = routine.id
            $0.setPrescriptionRefresh(.fullRefresh, for: liftDay.date)
        }

        let regen = store.generate(from: memory, today: today)
        let day = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: liftDay.date) })
        let row = try XCTUnwrap(day.generatedWorkout?.exercises.first)

        XCTAssertEqual(row.sets, 5, "unresolvable id keeps the stored prescription")
        XCTAssertEqual(row.reps, "6")
        XCTAssertEqual(row.restSeconds, 120)
        XCTAssertNil(row.rpe)
    }

    func test_generate_refreshWithoutCustomOverride_isNoop() throws {
        let today = monday()
        let cal = Calendar.current
        let store = makeStore()
        let memory = gymMemory()
        let baseline = store.generate(from: memory, today: today)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        // Refresh intent WITHOUT a custom override on the date.
        store.updateOverrides(today: today) {
            $0.setPrescriptionRefresh(.fullRefresh, for: liftDay.date)
        }
        let regen = store.generate(from: memory, today: today)
        let before = try XCTUnwrap(baseline.days.first { cal.isDate($0.date, inSameDayAs: liftDay.date) })
        let after = try XCTUnwrap(regen.days.first { cal.isDate($0.date, inSameDayAs: liftDay.date) })

        XCTAssertEqual(before.generatedWorkout?.exercises, after.generatedWorkout?.exercises,
                       "refresh is gated on the custom override existing")
    }

    func test_refreshedDay_excludedFromRefinementCandidates() throws {
        let today = monday()
        let cal = Calendar.current
        let (store, memory, date) = try refreshFixture(mode: .fullRefresh, today: today)

        let regen = store.generate(from: memory, today: today)
        let candidates = store.refinementCandidates(in: regen)
        XCTAssertFalse(candidates.contains { cal.isDate($0.day.date, inSameDayAs: date) },
                       "a refreshed custom day stays excluded from LLM refinement")
    }
}
