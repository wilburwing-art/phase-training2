// WeekPlanIdentityTests.swift — characterization tests for WeekPlan.swift's
// identity + date helpers:
//
//   1. GeneratedWorkout.stableTemplateId — composition-keyed template id that
//      SessionStore's getPreviousSession lookup relies on. Must depend ONLY
//      on the ordered exerciseIds, and must be stable across process restarts
//      (golden values pinned below — they were computed once and must never
//      drift, or last week's weights stop carrying forward).
//   2. WeekPlan.today(now:calendar:) — startOfDay-normalized day lookup.
//   3. WeekPlan.rangeLabel — "MMM d–MMM d" header label.
//
// All dates are explicit fixed anchors; no raw Date() feeds any assertion.

import XCTest
@testable import PhaseTraining

final class WeekPlanIdentityTests: XCTestCase {

    // MARK: - Fixtures

    private func exercise(id: Int, name: String = "Bench Press",
                          sets: Int = 3, reps: String = "8",
                          rpe: String? = nil) -> GeneratedExercise {
        GeneratedExercise(id: "ex-\(id)", exerciseId: id, name: name,
                          pattern: "horizontal_push", isCompound: false,
                          sets: sets, reps: reps, restSeconds: 90, rpe: rpe)
    }

    private func workout(exerciseIds: [Int],
                         title: String = "Push day",
                         names: [String]? = nil) -> GeneratedWorkout {
        GeneratedWorkout(
            title: title,
            summary: "\(exerciseIds.count) movements",
            exercises: exerciseIds.enumerated().map { i, exId in
                exercise(id: exId, name: names?[i] ?? "Exercise \(exId)")
            },
            estimatedMinutes: 45,
            provenance: "test")
    }

    /// Monday, May 11 2026 at local midnight — fixed anchor so nothing
    /// depends on the wall clock.
    private func mondayAnchor() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        return Calendar.current.startOfDay(for: Calendar.current.date(from: c)!)
    }

    /// 7 contiguous startOfDay-stamped days from `start`.
    private func plan(startingAt start: Date,
                      calendar: Calendar = .current) -> WeekPlan {
        let s = calendar.startOfDay(for: start)
        let days: [DayPlan] = (0..<7).map { i in
            DayPlan(date: calendar.date(byAdding: .day, value: i, to: s)!,
                    kind: i % 2 == 0 ? .lift : .rest,
                    title: "Day \(i)")
        }
        return WeekPlan(days: days, generatedAt: s, inputsHash: "fixture")
    }

    private func offset(_ start: Date, days: Int, hours: Int = 0,
                        minutes: Int = 0, seconds: Int = 0,
                        calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.day = days; c.hour = hours; c.minute = minutes; c.second = seconds
        return calendar.date(byAdding: c, to: start)!
    }

    // MARK: - stableTemplateId: composition identity

    func test_stableTemplateId_sameComposition_sameId() {
        // Same exerciseIds in the same order → same id, even when every
        // cosmetic field differs (title, exercise names, sets, reps, rpe).
        let a = workout(exerciseIds: [11, 12, 13], title: "Push day",
                        names: ["Bench Press", "Overhead Press", "Dips"])
        var b = workout(exerciseIds: [11, 12, 13], title: "Regenerated push",
                        names: ["Renamed A", "Renamed B", "Renamed C"])
        b.exercises = b.exercises.map { ex in
            var e = ex
            e.sets = 5; e.reps = "3-5"; e.rpe = "9"; e.restSeconds = 240
            return e
        }
        XCTAssertEqual(a.stableTemplateId, b.stableTemplateId,
                       "id must key on exercise composition only")
    }

    func test_stableTemplateId_differentOrder_differentId() {
        // The signature joins ids in array order, so a reordered workout is
        // a different template (exercise sequencing matters to the session).
        let forward = workout(exerciseIds: [11, 12, 13])
        let reversed = workout(exerciseIds: [13, 12, 11])
        XCTAssertNotEqual(forward.stableTemplateId, reversed.stableTemplateId)
    }

    func test_stableTemplateId_differentComposition_differentId() {
        XCTAssertNotEqual(workout(exerciseIds: [11]).stableTemplateId,
                          workout(exerciseIds: [42]).stableTemplateId)
        XCTAssertNotEqual(workout(exerciseIds: [11, 12]).stableTemplateId,
                          workout(exerciseIds: [11, 12, 13]).stableTemplateId)
    }

    func test_stableTemplateId_isGenPrefixedRadix36() {
        let id = workout(exerciseIds: [11, 12, 13]).stableTemplateId
        XCTAssertTrue(id.hasPrefix("gen-"), "got \(id)")

        let suffix = String(id.dropFirst("gen-".count))
        XCTAssertFalse(suffix.isEmpty)
        let radix36 = Set("0123456789abcdefghijklmnopqrstuvwxyz")
        XCTAssertTrue(suffix.allSatisfy { radix36.contains($0) },
                      "suffix must be lowercase radix-36, got \(suffix)")
        XCTAssertNotNil(UInt64(suffix, radix: 36),
                        "suffix must round-trip as a base-36 UInt64")
    }

    func test_stableTemplateId_goldenValues_stableAcrossRestarts() {
        // Restart simulation: these values were computed once, outside this
        // process. djb2 over the comma-joined ids is pure arithmetic (no
        // Hashable.hashValue, which Swift seeds per-launch), so any process
        // — today's or next week's — must reproduce them exactly. If this
        // test goes red, persisted sessions stop matching their templates.
        XCTAssertEqual(workout(exerciseIds: [11, 12, 13]).stableTemplateId,
                       "gen-22jcrihc2yu")
        XCTAssertEqual(workout(exerciseIds: [13, 12, 11]).stableTemplateId,
                       "gen-22jcsp75d3a")
        XCTAssertEqual(workout(exerciseIds: [11]).stableTemplateId, "gen-3hmtj")
        XCTAssertEqual(workout(exerciseIds: [42]).stableTemplateId, "gen-3hmwb")
    }

    func test_stableTemplateId_survivesCodableRoundTrip() {
        // Persist-and-reload simulation: a workout decoded from its own JSON
        // (what PlanStore does on every launch) must yield the same id as
        // the freshly generated instance.
        let original = workout(exerciseIds: [11, 12, 13])
        let data = try! JSONEncoder().encode(original)
        let reloaded = try! JSONDecoder().decode(GeneratedWorkout.self, from: data)
        XCTAssertEqual(reloaded.stableTemplateId, original.stableTemplateId)
    }

    func test_stableTemplateId_emptyExercises_isDjb2Seed() {
        // Empty composition → empty signature → the djb2 seed (5381) in
        // base 36. Degenerate but must not crash or collide unpredictably.
        XCTAssertEqual(workout(exerciseIds: []).stableTemplateId, "gen-45h")
    }

    // MARK: - today(now:): inside the window

    func test_today_middayWithinWeek_returnsMatchingDay() {
        let start = mondayAnchor()
        let p = plan(startingAt: start)
        let wednesdayAfternoon = offset(start, days: 2, hours: 15, minutes: 30)

        let day = p.today(now: wednesdayAfternoon, calendar: .current)
        XCTAssertNotNil(day)
        XCTAssertEqual(day?.title, "Day 2")
        XCTAssertEqual(day?.date, p.days[2].date)
    }

    func test_today_firstDayAtExactMidnight_returnsFirstDay() {
        let start = mondayAnchor()
        let p = plan(startingAt: start)
        XCTAssertEqual(p.today(now: start, calendar: .current)?.title, "Day 0")
    }

    func test_today_lastDayLateEvening_returnsLastDay() {
        let start = mondayAnchor()
        let p = plan(startingAt: start)
        let sundayNight = offset(start, days: 6, hours: 23, minutes: 59)
        XCTAssertEqual(p.today(now: sundayNight, calendar: .current)?.title, "Day 6")
    }

    func test_today_matchesEvenWhenDayDateIsNotMidnight() {
        // The doc contract says the planner normalizes day dates to
        // startOfDay, but the lookup itself uses isDate(_:inSameDayAs:),
        // so a 6pm-stamped day still matches a 6am query the same day.
        let start = mondayAnchor()
        var p = plan(startingAt: start)
        p.days[3].date = offset(start, days: 3, hours: 18)

        let earlyMorning = offset(start, days: 3, hours: 6)
        XCTAssertEqual(p.today(now: earlyMorning, calendar: .current)?.title, "Day 3")
    }

    // MARK: - today(now:): outside the window

    func test_today_secondBeforeWeekStarts_isNil() {
        let start = mondayAnchor()
        let p = plan(startingAt: start)
        // 23:59:59 the previous day — same instant minus one second crosses
        // the startOfDay boundary into a day the plan doesn't contain.
        let justBefore = offset(start, days: 0, seconds: -1)
        XCTAssertNil(p.today(now: justBefore, calendar: .current))
    }

    func test_today_midnightAfterWeekEnds_isNil() {
        let start = mondayAnchor()
        let p = plan(startingAt: start)
        // Exactly day 8's midnight — one boundary past the last plan day.
        let nextMonday = offset(start, days: 7)
        XCTAssertNil(p.today(now: nextMonday, calendar: .current))
    }

    func test_today_emptyPlan_isNil() {
        let p = WeekPlan(days: [], generatedAt: mondayAnchor(), inputsHash: "x")
        XCTAssertNil(p.today(now: mondayAnchor(), calendar: .current))
    }

    // MARK: - rangeLabel

    /// Production formatter setup mirrored here so the expected string tracks
    /// the runner's locale exactly the way rangeLabel does.
    private func mmmD(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    func test_rangeLabel_rendersFirstAndLastDayJoinedByEnDash() {
        let p = plan(startingAt: mondayAnchor())  // May 11 – May 17, 2026
        let label = p.rangeLabel

        // Note: the doc comment claims a compact "May 14–20", but the
        // implementation renders the full "MMM d" on BOTH endpoints —
        // characterize the actual behavior.
        XCTAssertEqual(label, "\(mmmD(p.days.first!.date))–\(mmmD(p.days.last!.date))")

        let halves = label.components(separatedBy: "–")
        XCTAssertEqual(halves.count, 2, "exactly one en dash, got \(label)")
        XCTAssertFalse(halves[0].isEmpty)
        XCTAssertFalse(halves[1].isEmpty)
        XCTAssertTrue(halves[0].contains("11"), "got \(label)")
        XCTAssertTrue(halves[1].contains("17"), "got \(label)")
    }

    func test_rangeLabel_emptyPlan_isEmptyStringNotCrash() {
        let p = WeekPlan(days: [], generatedAt: mondayAnchor(), inputsHash: "x")
        XCTAssertEqual(p.rangeLabel, "")
    }

    func test_rangeLabel_yearBoundaryWeek_rendersBothEndpoints() {
        // Mon Dec 29 2025 → Sun Jan 4 2026. No year in the format, so the
        // label silently spans years — both month-day endpoints must render.
        var c = DateComponents()
        c.year = 2025; c.month = 12; c.day = 29
        let start = Calendar.current.date(from: c)!
        let p = plan(startingAt: start)

        let label = p.rangeLabel
        XCTAssertEqual(label, "\(mmmD(p.days.first!.date))–\(mmmD(p.days.last!.date))")

        let halves = label.components(separatedBy: "–")
        XCTAssertEqual(halves.count, 2, "got \(label)")
        XCTAssertTrue(halves[0].contains("29"), "got \(label)")
        XCTAssertTrue(halves[1].contains("4"), "got \(label)")
        XCTAssertNotEqual(halves[0], halves[1],
                          "endpoints must differ across the year boundary")
    }
}
