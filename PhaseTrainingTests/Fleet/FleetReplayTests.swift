// FleetReplayTests.swift — the phase-training2 side of the eval-rig fleet.
//
// Contract tests: an embedded athlete in the exact contract shape decodes,
// replays and yields predictions with the right shape; a generated 8-week
// athlete with planted habits exercises every engine and pins the invariants
// (likelihood in 0...1, rows only on planned days, no prediction reads its own
// day or later, deterministic output).
//
// `testReplayRunDirectory` is the real run: it reads a run directory from
// FLEET_RUN_DIR (pass it to xcodebuild as TEST_RUNNER_FLEET_RUN_DIR), replays
// every athletes/*.json and writes predictions/<id>.json. It skips when the
// variable is unset, so CI never runs it. See PLAN-next-gen.md, fleet section.
//
// The embedded fixture is hand-written to the contract: eval-rig had no
// test/fixtures/fleet/ athletes yet when this was written. Replace it with
// the simulator's own fixture once one exists.

import XCTest
@testable import PhaseTraining

final class FleetReplayTests: XCTestCase {

    private let cal = FleetContract.calendar

    // MARK: - Embedded fixture

    private static let fixture = #"""
    {
      "schema_version": 1,
      "athlete_id": "a-fixture",
      "persona": "weekday-skipper",
      "declared_session_minutes": 60,
      "truth": {
        "attendance_by_weekday": { "mon": 0.9, "tue": 0.3, "wed": 0.9, "thu": 0.9,
                                   "fri": 0.8, "sat": 0.95, "sun": 0.95 },
        "travel_attendance": 0.2,
        "overrun_minutes": 0,
        "always_dropped_exercise": null,
        "habits": ["tuesday-skipper"]
      },
      "days": [
        {
          "date": "2026-03-30",
          "planned": { "kind": "lift", "title": "Lower A", "minutes": 60,
                       "exercises": [
                         { "id": "p-0001-1", "name": "Barbell Back Squat", "sets": 2, "reps": 5 },
                         { "id": "p-0001-2", "name": "Face Pull", "sets": 2, "reps": 15 } ] },
          "travel": false,
          "session": {
            "start": "2026-03-30T17:30:00Z", "duration_minutes": 62, "abandoned": false,
            "exercises": [
              { "planned_id": "p-0001-1", "name": "Barbell Back Squat",
                "sets": [ { "weight": 95, "reps": 5, "done": true, "warmup": true },
                          { "weight": 225, "reps": 5, "done": true, "warmup": false },
                          { "weight": 225, "reps": 5, "done": true, "warmup": false } ] },
              { "planned_id": "p-0001-2", "name": "Face Pull",
                "sets": [ { "weight": 40, "reps": 15, "done": true, "warmup": false },
                          { "weight": 40, "reps": 15, "done": true, "warmup": false } ] } ] },
          "true_readiness": 0.62
        },
        { "date": "2026-03-31", "planned": { "kind": "rest", "title": "Rest", "minutes": null, "exercises": [] },
          "travel": false, "session": null, "true_readiness": 0.64 },
        {
          "date": "2026-04-01",
          "planned": { "kind": "lift", "title": "Upper A", "minutes": 60,
                       "exercises": [
                         { "id": "p-0003-1", "name": "Barbell Bench Press", "sets": 2, "reps": 5 },
                         { "id": "p-0003-2", "name": "Barbell Row", "sets": 2, "reps": 8 } ] },
          "travel": false,
          "session": {
            "start": "2026-04-01T18:00:00Z", "duration_minutes": 58.5, "abandoned": false,
            "exercises": [
              { "planned_id": "p-0003-1", "name": "Dumbbell Bench Press",
                "sets": [ { "weight": 70, "reps": 8, "done": true, "warmup": false },
                          { "weight": 70, "reps": 8, "done": true, "warmup": false } ] },
              { "planned_id": "p-0003-2", "name": "Barbell Row",
                "sets": [ { "weight": 135, "reps": 8, "done": true, "warmup": false },
                          { "weight": 135, "reps": 8, "done": true, "warmup": false } ] },
              { "planned_id": null, "name": "Dumbbell Curl",
                "sets": [ { "weight": 25, "reps": 12, "done": true, "warmup": false } ] } ] },
          "true_readiness": 0.6
        },
        { "date": "2026-04-02", "planned": null, "travel": true, "session": null, "true_readiness": 0.61 },
        {
          "date": "2026-04-03",
          "planned": { "kind": "lift", "title": "Lower B", "minutes": 45,
                       "exercises": [ { "id": "p-0005-1", "name": "Barbell Deadlift", "sets": 3, "reps": 5 } ] },
          "travel": true, "session": null, "true_readiness": 0.63
        },
        {
          "date": "2026-04-04",
          "planned": { "kind": "sport", "title": "Climb", "minutes": 120, "exercises": [] },
          "travel": false,
          "session": { "start": "2026-04-04T10:00:00Z", "duration_minutes": 120, "abandoned": false,
                       "exercises": [] },
          "true_readiness": 0.66
        },
        { "date": "2026-04-05", "planned": null, "travel": false, "session": null, "true_readiness": 0.58 },
        {
          "date": "2026-04-06",
          "planned": { "kind": "lift", "title": "Lower A", "minutes": 60,
                       "exercises": [ { "id": "p-0008-1", "name": "Barbell Back Squat", "sets": 2, "reps": 5 } ] },
          "travel": false,
          "session": {
            "start": "2026-04-06T17:30:00Z", "duration_minutes": 61, "abandoned": false,
            "exercises": [
              { "planned_id": "p-0008-1", "name": "Barbell Back Squat",
                "sets": [ { "weight": 230, "reps": 5, "done": true, "warmup": false },
                          { "weight": 230, "reps": 5, "done": true, "warmup": false } ] } ] },
          "true_readiness": 0.65
        }
      ]
    }
    """#

    private func fixtureAthlete() throws -> FleetAthlete {
        try FleetContract.decodeAthlete(Data(Self.fixture.utf8), source: "fixture")
    }

    func testFixtureDecodes() throws {
        let a = try fixtureAthlete()
        XCTAssertEqual(a.athleteId, "a-fixture")
        XCTAssertEqual(a.declaredSessionMinutes, 60)
        XCTAssertEqual(a.truth.attendanceByWeekday["tue"], 0.3)
        XCTAssertNil(a.truth.alwaysDroppedExercise)
        XCTAssertEqual(a.days.count, 8)
        XCTAssertNil(a.days[3].planned)
        XCTAssertTrue(a.days[3].travel)
        XCTAssertEqual(a.days[5].planned?.kind, "sport")
        XCTAssertEqual(a.days[5].planned?.exercises, [])
        XCTAssertNil(a.days[2].session?.exercises[2].plannedId, "an added exercise")
        XCTAssertEqual(a.days[2].session?.durationMinutes, 58.5)
    }

    func testOtherSchemaVersionIsRefused() throws {
        let v3 = Self.fixture.replacingOccurrences(of: "\"schema_version\": 1", with: "\"schema_version\": 3")
        XCTAssertThrowsError(try FleetContract.decodeAthlete(Data(v3.utf8), source: "v3")) { error in
            guard case FleetContract.ContractError.schemaVersion(let found, _) = error else {
                return XCTFail("expected a schema version error, got \(error)")
            }
            XCTAssertEqual(found, 3)
        }
    }

    func testFixtureConvertsToAppTypes() throws {
        let h = try FleetConverter.convert(try fixtureAthlete())
        XCTAssertEqual(h.sessions.count, 4)
        XCTAssertEqual(h.weeks.count, 2)
        XCTAssertTrue(h.weeks.allSatisfy { $0.days.count == 7 })
        XCTAssertEqual(FleetContract.dayString(h.weeks[0].days[0].date), "2026-03-30")
        XCTAssertEqual(h.weeks[1].days[1].kind, .rest, "days past the simulated window fill as rest")

        // DayOutcome.derive sees the plan through the gex- ids.
        XCTAssertEqual(h.outcomes[0].kind, .asPlanned)
        XCTAssertEqual(h.outcomes[1].kind, .modified)
        XCTAssertEqual(h.outcomes[1].swaps, [ExerciseSwapPair(planned: "Barbell Bench Press",
                                                              logged: "Dumbbell Bench Press")])
        XCTAssertEqual(h.outcomes[1].added, ["Dumbbell Curl"])
        XCTAssertEqual(h.outcomes[2].plannedDayKind, .sport)
        XCTAssertEqual(h.outcomes[1].durationMinutes, 58)

        XCTAssertEqual(h.missed.map { FleetContract.dayString($0.date) }, ["2026-04-03"])
        XCTAssertEqual(h.missed.first?.plannedKind, .lift)
        XCTAssertEqual(h.travelEvents.map { FleetContract.dayString($0.date) }, ["2026-04-02", "2026-04-03"])
        XCTAssertTrue(h.travelEvents.allSatisfy { $0.kind == .outOfTown })
        XCTAssertEqual(h.sessions[1].exercises[0].sets[0].weight, "70")
    }

    func testFixtureReplays() throws {
        let p = try FleetReplay.predictions(for: try fixtureAthlete())
        XCTAssertEqual(p.schemaVersion, 1)
        XCTAssertEqual(p.engineBuild, "145")
        XCTAssertEqual(p.likelihood.map(\.date),
                       ["2026-03-30", "2026-04-01", "2026-04-03", "2026-04-04", "2026-04-06"])
        XCTAssertEqual(p.likelihood[0].p, SessionLikelihoodEngine.priorHappened / (SessionLikelihoodEngine.priorHappened + SessionLikelihoodEngine.priorMissed), accuracy: 1e-9, "no history: the prior")
        XCTAssertEqual(p.likelihood[0].samples, 0)
        XCTAssertEqual(p.likelihood[4].samples, 4, "3 happened + 1 missed before 2026-04-06")

        XCTAssertEqual(p.twin.map(\.date), ["2026-04-06"], "only the squat has an earlier loaded day")
        let squat = try XCTUnwrap(p.twin.first)
        XCTAssertEqual(squat.exercise, "Barbell Back Squat")
        XCTAssertEqual(squat.baseline, StrengthStandards.epley1RM(weight: 225, reps: 5), accuracy: 1e-9)
        XCTAssertEqual(squat.actual, StrengthStandards.epley1RM(weight: 230, reps: 5), accuracy: 1e-9)

        XCTAssertTrue(p.suggestions.isEmpty)
        let week1 = p.counterfactual.filter { $0.weekStart == "2026-03-30" }
        XCTAssertEqual(Set(week1.filter { $0.alternative == "skip" }.map(\.liftDate)),
                       ["2026-03-30", "2026-04-01", "2026-04-03"])
        XCTAssertTrue(week1.allSatisfy { $0.sportDate == "2026-04-04" })
        XCTAssertTrue(p.counterfactual.allSatisfy { $0.weekStart == "2026-03-30" },
                      "week 2 has no sport day")

        // The file round-trips through the contract decoder.
        let back = try FleetContract.decodePredictions(try FleetContract.encode(p))
        XCTAssertEqual(back.likelihood.map(\.date), p.likelihood.map(\.date))
        XCTAssertEqual(back.counterfactual.count, p.counterfactual.count)
        XCTAssertEqual(back.twin.map(\.exercise), p.twin.map(\.exercise))
    }

    // MARK: - Generated athlete with planted habits

    /// 8 weeks from Monday 2026-03-30. Mon lift, Tue lift (done on even weeks
    /// only), Wed rest, Thu lift, Fri rest, Sat sport, Sun unplanned. Face Pull
    /// is planned Mon and Thu and never done; every session runs 80 minutes
    /// against a declared 60. Week 4 has travel Tue to Thu with no sessions.
    /// Week 2's Thursday is abandoned after one exercise. Loads climb 5 lb a week.
    private func plantedAthlete(weeks: Int = 8) throws -> FleetAthlete {
        let start = try FleetContract.day("2026-03-30")
        typealias Lift = (id: String, name: String, sets: Int, reps: Int, base: Double)
        let monday: [Lift] = [("sq", "Barbell Back Squat", 3, 5, 185), ("rdl", "Romanian Deadlift", 3, 8, 155),
                              ("fp", "Face Pull", 3, 15, 40)]
        let tuesday: [Lift] = [("ohp", "Overhead Press", 3, 5, 95), ("pu", "Pull-Up", 3, 8, 0)]
        let thursday: [Lift] = [("bp", "Barbell Bench Press", 3, 5, 155), ("row", "Barbell Row", 3, 8, 135),
                                ("fp", "Face Pull", 3, 15, 40)]

        var days: [FleetDay] = []
        for w in 0..<weeks {
            for d in 0..<7 {
                let date = cal.date(byAdding: .day, value: 7 * w + d, to: start)!
                let key = FleetContract.dayString(date)
                let travel = w == 4 && (1...3).contains(d)
                var planned: FleetPlanned?
                var lifts: [Lift] = []
                switch d {
                case 0: lifts = monday; planned = FleetPlanned(kind: "lift", title: "Lower A", minutes: 60, exercises: [])
                case 1: lifts = tuesday; planned = FleetPlanned(kind: "lift", title: "Upper B", minutes: 60, exercises: [])
                case 2, 4: planned = FleetPlanned(kind: "rest", title: "Rest", minutes: nil, exercises: [])
                case 3: lifts = thursday; planned = FleetPlanned(kind: "lift", title: "Upper A", minutes: 60, exercises: [])
                case 5: planned = FleetPlanned(kind: "sport", title: "Climb", minutes: 120, exercises: [])
                default: planned = nil
                }
                planned?.exercises = lifts.map {
                    FleetPlannedExercise(id: "p-\(key)-\($0.id)", name: $0.name, sets: $0.sets, reps: $0.reps)
                }

                var attended = planned.map { $0.kind == "lift" || $0.kind == "sport" } ?? false
                if d == 1 && w % 2 == 1 { attended = false }
                if travel { attended = false }
                if w == 6 && d == 3 { attended = false }

                var session: FleetSession?
                if attended {
                    let abandoned = w == 2 && d == 3
                    var logged: [FleetLoggedExercise] = []
                    for lift in lifts where lift.name != "Face Pull" {
                        let weight = lift.base > 0 ? lift.base + 5 * Double(w) : 0
                        var sets: [FleetSet] = []
                        if weight > 0 { sets.append(FleetSet(weight: (weight / 2).rounded(), reps: 5, done: true, warmup: true)) }
                        for _ in 0..<lift.sets { sets.append(FleetSet(weight: weight, reps: lift.reps, done: true, warmup: false)) }
                        var name = lift.name
                        if w == 5 && lift.id == "bp" { name = "Dumbbell Bench Press" }
                        logged.append(FleetLoggedExercise(plannedId: "p-\(key)-\(lift.id)", name: name, sets: sets))
                        if abandoned { break }
                    }
                    if w == 3 && d == 0 {
                        logged.append(FleetLoggedExercise(plannedId: nil, name: "Hanging Leg Raise",
                                                          sets: [FleetSet(weight: 0, reps: 10, done: true, warmup: false)]))
                    }
                    session = FleetSession(start: d == 5 ? "\(key)T10:00:00Z" : "\(key)T17:30:00Z",
                                           durationMinutes: d == 5 ? 120 : (abandoned ? 25 : 80),
                                           abandoned: abandoned, exercises: logged)
                }
                days.append(FleetDay(date: key, planned: planned, travel: travel, session: session,
                                     trueReadiness: 0.6))
            }
        }
        let athlete = FleetAthlete(
            schemaVersion: 1, athleteId: "a-planted", persona: "dropper", declaredSessionMinutes: 60,
            truth: FleetTruth(attendanceByWeekday: ["mon": 1, "tue": 0.5, "wed": 0, "thu": 0.9,
                                                    "fri": 0, "sat": 1, "sun": 0],
                              travelAttendance: 0, overrunMinutes: 20,
                              alwaysDroppedExercise: "Face Pull", habits: ["dropper", "overrunner"]),
            days: days)
        // Through JSON and back, so the generated athlete is exactly what a
        // file in the contract shape would decode to.
        return try FleetContract.decodeAthlete(try FleetContract.encode(athlete), source: "planted")
    }

    func testPlantedAthlete_shapeAndInvariants() throws {
        let athlete = try plantedAthlete()
        let p = try FleetReplay.predictions(for: athlete)

        // Likelihood: exactly one row per planned lift or sport day, in 0...1.
        let plannedDays = athlete.days
            .filter { $0.planned?.kind == "lift" || $0.planned?.kind == "sport" }
            .map(\.date)
        XCTAssertEqual(p.likelihood.map(\.date), plannedDays)
        for row in p.likelihood {
            XCTAssertTrue((0...1).contains(row.p), "\(row)")
            XCTAssertGreaterThanOrEqual(row.samples, 0)
        }
        XCTAssertEqual(p.likelihood.map(\.samples), p.likelihood.map(\.samples).sorted(),
                       "evidence only grows inside the 90-day window")
        // The skipped Tuesdays end below the Mondays.
        let lastTue = try XCTUnwrap(p.likelihood.last(where: { weekday($0.date) == 3 }))
        let lastMon = try XCTUnwrap(p.likelihood.last(where: { weekday($0.date) == 2 }))
        XCTAssertLessThan(lastTue.p, lastMon.p)

        // Suggestions: week starts only; both planted habits are seen.
        let mondays = Set(athlete.days.map(\.date).filter { weekday($0) == 2 })
        XCTAssertTrue(p.suggestions.allSatisfy { mondays.contains($0.weekStart) })
        XCTAssertTrue(p.suggestions.contains { $0.id == "droppedExercise:face pull" && $0.rule == "droppedExercise" },
                      "\(p.suggestions)")
        XCTAssertTrue(p.suggestions.contains { $0.rule == "sessionLength" }, "\(p.suggestions)")
        XCTAssertFalse(p.suggestions.contains { $0.weekStart == "2026-03-30" }, "nothing before any history")

        // Twin: rows only on session days, for exercises logged that day.
        let logged: [String: Set<String>] = Dictionary(uniqueKeysWithValues:
            athlete.days.compactMap { d -> (String, Set<String>)? in
                guard let s = d.session else { return nil }
                return (d.date, Set(s.exercises.map(\.name)))
            })
        XCTAssertFalse(p.twin.isEmpty)
        for row in p.twin {
            XCTAssertTrue(logged[row.date]?.contains(row.exercise) ?? false, "\(row)")
            XCTAssertGreaterThanOrEqual(row.predicted, 0)
            XCTAssertLessThan(row.baseline, row.actual, "planted loads climb every week")
        }
        XCTAssertFalse(p.twin.contains { $0.exercise == "Face Pull" || $0.exercise == "Pull-Up" },
                       "never logged / bodyweight: no loaded top set")

        // Counterfactual: planned lift days of the week, before its sport day.
        let known: Set<String> = ["skip", "move", "shorter", "saved_routine"]
        XCTAssertFalse(p.counterfactual.isEmpty)
        for row in p.counterfactual {
            XCTAssertTrue(known.contains(row.alternative), "\(row)")
            XCTAssertTrue(mondays.contains(row.weekStart))
            XCTAssertLessThanOrEqual(row.weekStart, row.liftDate)
            XCTAssertLessThan(row.liftDate, row.sportDate)
            XCTAssertTrue((0...1).contains(row.baseline))
            XCTAssertEqual(row.moveTo != nil, row.alternative == "move")
        }
    }

    func testReplayIsDeterministic() throws {
        let athlete = try plantedAthlete()
        let a = try FleetContract.encode(try FleetReplay.predictions(for: athlete))
        let b = try FleetContract.encode(try FleetReplay.predictions(for: athlete))
        XCTAssertEqual(a, b)
    }

    /// Remove every session on or after `cut`. Anything predicted for `cut`
    /// or earlier (and the twin before `cut`) must not change: if it did, it
    /// read the day it predicts, or later.
    func testNoPredictionUsesSameDayOrLaterData() throws {
        let athlete = try plantedAthlete()
        let full = try FleetReplay.predictions(for: athlete)
        // A Monday, a Tuesday, a Thursday and a Saturday.
        for cut in ["2026-04-20", "2026-04-28", "2026-05-07", "2026-05-16"] {
            var masked = athlete
            for i in masked.days.indices where masked.days[i].date >= cut {
                masked.days[i].session = nil
            }
            let m = try FleetReplay.predictions(for: masked)
            XCTAssertEqual(m.likelihood.filter { $0.date <= cut }, full.likelihood.filter { $0.date <= cut }, cut)
            XCTAssertEqual(m.suggestions.filter { $0.weekStart <= cut }, full.suggestions.filter { $0.weekStart <= cut }, cut)
            XCTAssertEqual(m.counterfactual.filter { $0.weekStart <= cut },
                           full.counterfactual.filter { $0.weekStart <= cut }, cut)
            XCTAssertEqual(m.twin.filter { $0.date < cut }, full.twin.filter { $0.date < cut }, cut)
        }
    }

    /// The replay's memoized twin is the app's `TwinInputs.predict`.
    func testFrozenTwinMatchesTheApp() throws {
        let h = try FleetConverter.convert(try plantedAthlete(weeks: 4))
        for (i, session) in h.sessions.enumerated() where !session.exercises.isEmpty {
            let history = TwinInputs.sets(from: h.sessions.filter { $0.startTime < session.startTime })
            let app = TwinInputs.predict(session: session, plannedExercises: h.outcomes[i].plannedExercises,
                                         history: history)
            let replay = FleetReplay.freezeTwin(session: session, plannedExercises: h.outcomes[i].plannedExercises,
                                                history: history, patternFor: TwinInputs.pattern(for:))
            XCTAssertEqual(replay.exercises, app.exercises)
            XCTAssertEqual(replay.readiness, app.readiness, accuracy: 1e-12)
        }
    }

    // MARK: - The real run

    func testReplayRunDirectory() throws {
        guard let dir = ProcessInfo.processInfo.environment["FLEET_RUN_DIR"], !dir.isEmpty else {
            throw XCTSkip("FLEET_RUN_DIR is not set; pass TEST_RUNNER_FLEET_RUN_DIR=<run dir> to xcodebuild.")
        }
        let fm = FileManager.default
        let run = URL(fileURLWithPath: dir, isDirectory: true)
        let manifestURL = run.appendingPathComponent("manifest.json")
        if fm.fileExists(atPath: manifestURL.path) {
            _ = try FleetContract.decodeManifest(try Data(contentsOf: manifestURL))
        }
        let files = try fm.contentsOfDirectory(at: run.appendingPathComponent("athletes", isDirectory: true),
                                               includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no athletes/*.json under \(dir)")

        let out = run.appendingPathComponent("predictions", isDirectory: true)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        for file in files {
            let athlete = try FleetContract.decodeAthlete(try Data(contentsOf: file), source: file.lastPathComponent)
            let predictions = try FleetReplay.predictions(for: athlete)
            try FleetContract.encode(predictions)
                .write(to: out.appendingPathComponent("\(athlete.athleteId).json"), options: .atomic)
        }
        print("fleet replay: wrote \(files.count) predictions to \(out.path)")
    }

    // MARK: - Helpers

    /// Gregorian weekday (1 = Sunday) of a `YYYY-MM-DD` string.
    private func weekday(_ s: String) -> Int {
        guard let d = try? FleetContract.day(s) else { return 0 }
        return cal.component(.weekday, from: d)
    }
}
