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

    // MARK: - Build-65 expansion: age + velocity + recovery + duration

    func test_bodySection_includesAgeWhenSet() {
        var m = TrainingMemory()
        m.weightKg = 80.0
        m.gender = .male
        m.age = 32
        let s = CoachContext.bodySection(memory: m) ?? ""
        XCTAssertTrue(s.contains("age: 32"), "BODY should include age — was missing before build 65. Got: \(s)")
    }

    func test_strengthSection_emitsVelocityWhenBothWindowsHaveData() {
        var m = TrainingMemory()
        m.weightKg = BodyMetrics.lbToKg(180)
        m.gender = .male
        m.usesImperial = true
        let now = Date()
        let cal = Calendar.current
        // Prior window (~6 weeks ago): 225×5 → est 1RM ~262.5
        let oldSession = savedSession(
            name: "Bench Press",
            sets: [("225", "5")],
            startTime: cal.date(byAdding: .weekOfYear, value: -6, to: now)!
        )
        // Recent window (1 week ago): 245×5 → est 1RM ~285.8 → +23 lb gain
        let newSession = savedSession(
            name: "Bench Press",
            sets: [("245", "5")],
            startTime: cal.date(byAdding: .day, value: -7, to: now)!
        )
        let s = CoachContext.strengthSection(
            memory: m,
            sessions: [oldSession, newSession],
            now: now
        ) ?? ""
        XCTAssertTrue(s.contains("/4w"), "velocity should appear: \(s)")
        // Should be a positive change — "+" prefix
        XCTAssertTrue(s.contains("+"), "positive velocity should be marked with +: \(s)")
    }

    func test_strengthSection_velocityFlatWithinNoiseFloor() {
        var m = TrainingMemory()
        m.weightKg = BodyMetrics.lbToKg(180)
        m.gender = .male
        m.usesImperial = true
        let now = Date()
        let cal = Calendar.current
        // 225×5 in both windows — same est 1RM, should show ≈
        let old = savedSession(
            name: "Bench Press", sets: [("225", "5")],
            startTime: cal.date(byAdding: .weekOfYear, value: -6, to: now)!
        )
        let new = savedSession(
            name: "Bench Press", sets: [("225", "5")],
            startTime: cal.date(byAdding: .day, value: -7, to: now)!
        )
        let s = CoachContext.strengthSection(memory: m, sessions: [old, new], now: now) ?? ""
        XCTAssertTrue(s.contains("≈"), "plateau within 5lb noise floor should render as ≈. Got: \(s)")
    }

    // MARK: - Recovery trend

    func test_recoveryTrendSection_nilWithLessThanTwoEntries() {
        let s = CoachContext.recoveryTrendSection(soreness: [], now: Date())
        XCTAssertNil(s)
    }

    func test_recoveryTrendSection_flagsRecurringHurtAreas() {
        // Build 107 switched soreness areas from joint vocab (knee, shoulder)
        // to muscle-bucket slugs (quads, back, shoulders). Coach summaries
        // filter to MuscleBucket.sorenessPrimarySlugs on read so legacy
        // joint-tagged entries don't leak through.
        let now = Date()
        let cal = Calendar.current
        let entries: [SorenessEntry] = (1...5).map { dayOffset in
            var e = SorenessEntry(date: cal.date(byAdding: .day, value: -dayOffset, to: now)!)
            e.areas = ["quads"]
            e.energy = "normal"
            return e
        }
        let s = CoachContext.recoveryTrendSection(soreness: entries, now: now) ?? ""
        XCTAssertTrue(s.contains("RECOVERY TREND"))
        XCTAssertTrue(s.contains("quads"), "recurring 'quads' should be flagged: \(s)")
        XCTAssertTrue(s.contains("5x"), "should count the recurrences: \(s)")
        XCTAssertTrue(s.contains("normal"), "energy histogram should appear: \(s)")
    }

    // MARK: - Pattern frequency

    func test_patternFrequencySection_nilWithNoRecentSessions() {
        XCTAssertNil(CoachContext.patternFrequencySection(sessions: [], now: Date()))
    }

    // MARK: - averageRecentDurationMinutes

    func test_averageRecentDurationMinutes_nilUnderThreeSessions() {
        let s = [savedSession(name: "X", sets: [("100", "5")])]
        XCTAssertNil(CoachContext.averageRecentDurationMinutes(sessions: s))
    }

    func test_averageRecentDurationMinutes_averagesLast8() {
        // 4 sessions @ 30 min each (1800 sec).
        let sessions: [SavedSession] = (1...4).map { idx in
            let start = Date().addingTimeInterval(-Double(idx) * 86400)
            return SavedSession(
                templateId: "t", name: "Push", category: "",
                startTime: start, exercises: [], feel: nil, note: nil,
                endTime: start.addingTimeInterval(1800), duration: 1800
            )
        }
        XCTAssertEqual(CoachContext.averageRecentDurationMinutes(sessions: sessions), 30)
    }

    // MARK: - Season summary (build 78 — season was missing from coach context)

    func test_seasonSummary_noSportsFallsBackToDefault() {
        var m = TrainingMemory()
        m.sports = []
        m.defaultSeason = .preSeason
        XCTAssertEqual(CoachContext.seasonSummary(memory: m), "pre-season")
    }

    func test_seasonSummary_allSportsSamePhaseCollapses() {
        var m = TrainingMemory()
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        let running = Sport.catalog.first { $0.slug == "running" }!
        m.sports = [climbing, running]
        m.seasonsBySport = [climbing: .offSeason, running: .offSeason]
        m.defaultSeason = .maintenance
        XCTAssertEqual(CoachContext.seasonSummary(memory: m), "off-season")
    }

    func test_seasonSummary_mixedPhasesRenderEachSport() {
        var m = TrainingMemory()
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        let skiing = Sport.catalog.first { $0.slug == "snow-sports" }!
        m.sports = [climbing, skiing]
        m.seasonsBySport = [climbing: .inSeason, skiing: .preSeason]
        m.defaultSeason = .maintenance
        let s = CoachContext.seasonSummary(memory: m)
        XCTAssertTrue(s.contains("climbing in-season"), "got: \(s)")
        XCTAssertTrue(s.contains("skiing / snowboarding pre-season"), "got: \(s)")
        XCTAssertTrue(s.contains("otherwise: year-round / maintenance"), "got: \(s)")
    }

    func test_snapshot_includesPeakDateWhenSet() {
        var m = TrainingMemory()
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        m.sports = [climbing]
        m.primarySport = climbing
        m.seasonsBySport = [climbing: .eventPrep]
        m.peakDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())
        let snap = CoachContext.snapshot(
            activeTab: .today,
            memory: m,
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: []
        )
        XCTAssertTrue(snap.contains("peak date:"), "Peak date should appear when set. Got:\n\(snap)")
        XCTAssertTrue(snap.contains("in 10 days"), "Peak date should show days remaining. Got:\n\(snap)")
    }

    func test_snapshot_omitsPeakDateWhenNil() {
        var m = TrainingMemory()
        m.peakDate = nil
        let snap = CoachContext.snapshot(
            activeTab: .today,
            memory: m,
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: []
        )
        XCTAssertFalse(snap.contains("peak date:"), "Peak date line should be hidden when nil")
    }

    func test_snapshot_includesSeasonLine() {
        var m = TrainingMemory()
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        m.sports = [climbing]
        m.primarySport = climbing
        m.seasonsBySport = [climbing: .offSeason]
        let snap = CoachContext.snapshot(
            activeTab: .today,
            memory: m,
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: []
        )
        XCTAssertTrue(snap.contains("season: off-season"),
                      "USER PROFILE must include season line — was missing pre-build-78. Got:\n\(snap)")
    }

    // MARK: - Injury sections (build 87)

    func test_structuredInjuries_emitsHumanReadableName() {
        var m = TrainingMemory()
        m.userInjuries = [UserInjury(slug: "patellar-tendinopathy")]
        let block = CoachContext.structuredInjuriesSection(memory: m) ?? ""
        XCTAssertTrue(block.contains("STRUCTURED INJURIES"))
        XCTAssertTrue(block.contains("Patellar Tendinopathy"),
                      "Should emit the human name, not the slug. Got: \(block)")
        XCTAssertFalse(block.contains("patellar-tendinopathy"),
                       "Raw slug should never appear in the structured block")
    }

    func test_structuredInjuries_includesSeverityAndSideWhenSet() {
        var m = TrainingMemory()
        m.userInjuries = [
            UserInjury(slug: "acl-injury", severity: .moderate, side: .left, onsetDate: nil)
        ]
        let block = CoachContext.structuredInjuriesSection(memory: m) ?? ""
        XCTAssertTrue(block.contains("moderate"), "Severity rendered: \(block)")
        XCTAssertTrue(block.contains("left"), "Side rendered: \(block)")
    }

    func test_structuredInjuries_nilWhenEmpty() {
        XCTAssertNil(CoachContext.structuredInjuriesSection(memory: TrainingMemory()))
    }

    func test_injuryFilters_resolvesExerciseNames() {
        var m = TrainingMemory()
        m.userInjuries = [UserInjury(slug: "acl-injury")]
        let p = DemographicProfile.from(m)
        let block = CoachContext.injuryFiltersSection(profile: p, memory: m) ?? ""
        XCTAssertTrue(block.contains("INJURY FILTERS"))
        XCTAssertTrue(block.contains("ACL Sprain/Tear"),
                      "Header should use the human name. Got: \(block)")
        // The block should list at least one actual exercise name (not an id).
        // We don't pin the exact name because coach.db can shuffle, but the
        // block must NOT be just the header + slug.
        let lines = block.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.count >= 2, "Expected header + at least one injury line")
    }

    func test_snapshot_neverRendersRawSlugInConstraintsBlock() {
        var m = TrainingMemory()
        m.userInjuries = [UserInjury(slug: "acl-injury")]
        let snap = CoachContext.snapshot(
            activeTab: .today,
            memory: m,
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: []
        )
        XCTAssertFalse(snap.contains("- acl-injury"),
                       "Slug should be promoted to STRUCTURED INJURIES, not dumped raw. Got:\n\(snap)")
        XCTAssertTrue(snap.contains("ACL Sprain/Tear"),
                      "Snapshot should contain the human name for the injury")
    }

    func test_snapshot_legacyFreeText_stillSurfacesInConstraintsBlock() {
        var m = TrainingMemory()
        m.constraints = ["bad ankle"]
        let snap = CoachContext.snapshot(
            activeTab: .today,
            memory: m,
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: []
        )
        XCTAssertTrue(snap.contains("CONSTRAINTS (free-text)"))
        XCTAssertTrue(snap.contains("bad ankle"))
    }

    // MARK: - Sport logs

    func test_snapshot_includesRecentSportLogs() {
        // User climbed Monday for 75 min hard, with a note. Coach should
        // see name, date, duration, intensity, and note — same level of
        // detail RECENT SESSIONS gives for lift days.
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let monday = cal.date(byAdding: .day, value: -2, to: now)!
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        let log = SportLogEntry(
            date: cal.startOfDay(for: monday),
            sport: climbing,
            durationMinutes: 75,
            intensity: .hard,
            note: "bouldering V4",
            loggedAt: monday.addingTimeInterval(3600)
        )

        let snap = CoachContext.snapshot(
            now: now,
            activeTab: .today,
            memory: TrainingMemory(),
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: [],
            recentSportLogs: [log]
        )

        XCTAssertTrue(snap.contains("RECENT SPORT LOGS"),
                      "Block header must appear. Got:\n\(snap)")
        XCTAssertTrue(snap.contains("Climbing"),
                      "Sport name must render. Got:\n\(snap)")
        XCTAssertTrue(snap.contains("75 min"),
                      "Duration must render. Got:\n\(snap)")
        XCTAssertTrue(snap.contains("hard"),
                      "Intensity must render. Got:\n\(snap)")
        XCTAssertTrue(snap.contains("bouldering V4"),
                      "Note must surface. Got:\n\(snap)")
    }

    func test_snapshot_omitsSportLogBlockWhenEmpty() {
        let snap = CoachContext.snapshot(
            activeTab: .today,
            memory: TrainingMemory(),
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: [],
            recentSportLogs: []
        )
        XCTAssertFalse(snap.contains("RECENT SPORT LOGS"),
                       "Block must be hidden when there are no logs — prompt budget matters")
    }

    func test_snapshot_sportLogs_capsAtFiveMostRecent() {
        // Seven logs across seven days; only the five most-recent must
        // appear. Matches the RECENT SESSIONS cap so the coach sees a
        // consistent window across surfaces.
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        let logs: [SportLogEntry] = (1...7).map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: now)!
            return SportLogEntry(
                date: day,
                sport: climbing,
                durationMinutes: offset * 10, // 10, 20, 30… distinguishable
                intensity: .moderate,
                note: nil,
                loggedAt: day
            )
        }

        let snap = CoachContext.snapshot(
            now: now,
            activeTab: .today,
            memory: TrainingMemory(),
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: [],
            recentSportLogs: logs
        )

        // The two oldest (60 min, 70 min) must NOT appear.
        XCTAssertFalse(snap.contains("60 min"),
                       "Sixth-oldest log must be trimmed. Got:\n\(snap)")
        XCTAssertFalse(snap.contains("70 min"),
                       "Seventh-oldest log must be trimmed. Got:\n\(snap)")
        // The most-recent five (10–50 min) must.
        for mins in [10, 20, 30, 40, 50] {
            XCTAssertTrue(snap.contains("\(mins) min"),
                          "Recent log \(mins) min must surface. Got:\n\(snap)")
        }
    }

    // MARK: - Plan exercise visibility

    func test_snapshot_includesExercisesForNonTodayWorkoutDays() {
        // Today is a sport day (climbing) — no generatedWorkout on today.
        // Tomorrow is a Push day with two named exercises. The coach used to
        // only render today's exercises, so when a user opened the coach on
        // a climbing day and asked about tomorrow's Push session, the coach
        // truthfully said "I don't have the individual exercise lists." This
        // pins that exercises for future workout days now surface too.
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let pushWorkout = GeneratedWorkout(
            title: "Push Day",
            summary: "2 movements",
            exercises: [
                GeneratedExercise(id: "ex-0", exerciseId: 11, name: "Bench Press",
                                  pattern: "horizontal_push", isCompound: true,
                                  sets: 5, reps: "5", restSeconds: 180, notes: nil),
                GeneratedExercise(id: "ex-1", exerciseId: 12, name: "Overhead Press",
                                  pattern: "vertical_push", isCompound: true,
                                  sets: 4, reps: "8", restSeconds: 120, notes: nil),
            ],
            estimatedMinutes: 45,
            provenance: "test"
        )
        let days = [
            DayPlan(date: now, kind: .sport, title: "Climbing"),
            DayPlan(date: tomorrow, kind: .lift, title: "Push Day",
                    generatedWorkout: pushWorkout),
        ]
        let plan = WeekPlan(days: days, generatedAt: now, inputsHash: "test")

        let snap = CoachContext.snapshot(
            now: now,
            activeTab: .today,
            memory: TrainingMemory(),
            plan: plan,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: []
        )

        XCTAssertTrue(snap.contains("Bench Press"),
                      "Tomorrow's Push exercises must appear in the snapshot. Got:\n\(snap)")
        XCTAssertTrue(snap.contains("Overhead Press"),
                      "Tomorrow's Push exercises must appear in the snapshot. Got:\n\(snap)")
        XCTAssertTrue(snap.contains("5 × 5"),
                      "Sets × reps must be rendered for non-today days. Got:\n\(snap)")
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
