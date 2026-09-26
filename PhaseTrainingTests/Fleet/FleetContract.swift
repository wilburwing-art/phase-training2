// FleetContract.swift — the synthetic-athlete fleet's JSON shapes, mirrored
// from eval-rig's fleet/CONTRACT.md (schema version 1).
//
// eval-rig simulates athletes and writes `athletes/<id>.json`; the replay in
// this folder reads them, drives the app's pure engines, and writes
// `predictions/<id>.json` for eval-rig to score. JSON on disk is the only
// link between the repos, so these structs follow the contract field for
// field (snake_case keys through CodingKeys) and refuse any other schema
// version. Test target only: nothing here ships.
//
// Everything is UTC: `date` fields are `YYYY-MM-DD`, timestamps ISO 8601 with Z.

import Foundation

enum FleetContract {

    static let schemaVersion = 1
    static let engineBuild = "145"

    enum ContractError: Error, CustomStringConvertible {
        case schemaVersion(found: Int, source: String)
        case badDate(String)
        case badTimestamp(String)
        case unknownPlannedKind(String)

        var description: String {
            switch self {
            case .schemaVersion(let found, let source):
                return "\(source): schema_version \(found), this replay reads \(FleetContract.schemaVersion)"
            case .badDate(let s): return "not a YYYY-MM-DD date: \(s)"
            case .badTimestamp(let s): return "not an ISO 8601 timestamp: \(s)"
            case .unknownPlannedKind(let s): return "planned.kind must be lift, sport or rest, got \(s)"
            }
        }
    }

    /// Gregorian, UTC, en_US_POSIX, weeks start Monday. Every date the replay
    /// touches goes through this calendar.
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 2
        return c
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = FleetContract.calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `YYYY-MM-DD` -> start of that UTC day.
    static func day(_ s: String) throws -> Date {
        guard let d = dayFormatter.date(from: s) else { throw ContractError.badDate(s) }
        return calendar.startOfDay(for: d)
    }

    static func dayString(_ d: Date) -> String { dayFormatter.string(from: d) }

    static func timestamp(_ s: String) throws -> Date {
        if let d = isoPlain.date(from: s) ?? isoFractional.date(from: s) { return d }
        throw ContractError.badTimestamp(s)
    }

    static func timestampString(_ d: Date) -> String { isoPlain.string(from: d) }

    // MARK: - Decoding with the version check

    private struct VersionHeader: Decodable {
        let schemaVersion: Int
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version" }
    }

    /// Reads `schema_version` first, so a file from another major version is
    /// refused with a clear error instead of a shape mismatch.
    static func checkVersion(_ data: Data, source: String) throws {
        let header = try JSONDecoder().decode(VersionHeader.self, from: data)
        guard header.schemaVersion == schemaVersion else {
            throw ContractError.schemaVersion(found: header.schemaVersion, source: source)
        }
    }

    static func decodeAthlete(_ data: Data, source: String = "athlete") throws -> FleetAthlete {
        try checkVersion(data, source: source)
        return try JSONDecoder().decode(FleetAthlete.self, from: data)
    }

    static func decodeManifest(_ data: Data, source: String = "manifest.json") throws -> FleetManifest {
        try checkVersion(data, source: source)
        return try JSONDecoder().decode(FleetManifest.self, from: data)
    }

    static func decodePredictions(_ data: Data, source: String = "predictions") throws -> FleetPredictions {
        try checkVersion(data, source: source)
        return try JSONDecoder().decode(FleetPredictions.self, from: data)
    }

    /// Stable bytes: sorted keys, pretty printed.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(value)
    }
}

// MARK: - manifest.json

struct FleetManifest: Codable, Equatable {
    var schemaVersion: Int
    var runId: String
    var seed: Int
    var weeks: Int
    var startDate: String
    var athletes: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runId = "run_id"
        case seed, weeks
        case startDate = "start_date"
        case athletes
    }
}

// MARK: - athletes/<id>.json

struct FleetAthlete: Codable, Equatable {
    var schemaVersion: Int
    var athleteId: String
    var persona: String
    var declaredSessionMinutes: Int
    /// Planted truth. The replay never reads it; it is decoded only so the
    /// contract test pins its shape.
    var truth: FleetTruth
    var days: [FleetDay]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case athleteId = "athlete_id"
        case persona
        case declaredSessionMinutes = "declared_session_minutes"
        case truth, days
    }
}

struct FleetTruth: Codable, Equatable {
    var attendanceByWeekday: [String: Double]
    var travelAttendance: Double
    var overrunMinutes: Double
    var alwaysDroppedExercise: String?
    var habits: [String]

    enum CodingKeys: String, CodingKey {
        case attendanceByWeekday = "attendance_by_weekday"
        case travelAttendance = "travel_attendance"
        case overrunMinutes = "overrun_minutes"
        case alwaysDroppedExercise = "always_dropped_exercise"
        case habits
    }
}

struct FleetDay: Codable, Equatable {
    var date: String
    /// Nil on unplanned days.
    var planned: FleetPlanned?
    var travel: Bool
    /// Nil when the athlete did not train that day.
    var session: FleetSession?
    /// Simulator ground truth for 2a's direction. Never read by the replay.
    var trueReadiness: Double?

    enum CodingKeys: String, CodingKey {
        case date, planned, travel, session
        case trueReadiness = "true_readiness"
    }
}

struct FleetPlanned: Codable, Equatable {
    /// `lift`, `sport` or `rest`.
    var kind: String
    var title: String?
    var minutes: Int?
    /// Empty on sport and rest days.
    var exercises: [FleetPlannedExercise]

    enum CodingKeys: String, CodingKey { case kind, title, minutes, exercises }
}

extension FleetPlanned {
    // In an extension so the memberwise init stays available. Sport and rest
    // days may omit `exercises` or send null.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
        exercises = try c.decodeIfPresent([FleetPlannedExercise].self, forKey: .exercises) ?? []
    }
}

struct FleetPlannedExercise: Codable, Equatable {
    var id: String
    var name: String
    var sets: Int
    var reps: Int
}

struct FleetSession: Codable, Equatable {
    /// ISO 8601, UTC.
    var start: String
    /// Double so a simulator that emits fractional minutes still decodes.
    var durationMinutes: Double
    var abandoned: Bool
    var exercises: [FleetLoggedExercise]

    enum CodingKeys: String, CodingKey {
        case start
        case durationMinutes = "duration_minutes"
        case abandoned, exercises
    }
}

struct FleetLoggedExercise: Codable, Equatable {
    /// Nil = added (not in the plan).
    var plannedId: String?
    var name: String
    var sets: [FleetSet]

    enum CodingKeys: String, CodingKey {
        case plannedId = "planned_id"
        case name, sets
    }
}

struct FleetSet: Codable, Equatable {
    /// Pounds.
    var weight: Double
    var reps: Int
    var done: Bool
    var warmup: Bool
}

// MARK: - predictions/<id>.json

struct FleetPredictions: Codable, Equatable {
    var schemaVersion: Int
    var athleteId: String
    var engineBuild: String
    var likelihood: [FleetLikelihoodRow]
    var suggestions: [FleetSuggestionRow]
    var twin: [FleetTwinRow]
    var counterfactual: [FleetCounterfactualRow]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case athleteId = "athlete_id"
        case engineBuild = "engine_build"
        case likelihood, suggestions, twin, counterfactual
    }
}

struct FleetLikelihoodRow: Codable, Equatable {
    var date: String
    var p: Double
    var samples: Int
}

struct FleetSuggestionRow: Codable, Equatable {
    var weekStart: String
    var id: String
    var rule: String

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case id, rule
    }
}

struct FleetTwinRow: Codable, Equatable {
    var date: String
    var exercise: String
    var predicted: Double
    var baseline: Double
    var actual: Double
}

struct FleetCounterfactualRow: Codable, Equatable {
    var weekStart: String
    var liftDate: String
    /// `skip`, `move`, `shorter` or `saved_routine`.
    var alternative: String
    var sportDate: String
    var baseline: Double
    /// Null when the alternative leaves no readiness events at all.
    var score: Double?
    /// Extra detail beyond the contract, present only for its alternative:
    /// the target day of a move, the minutes of a shorter session, the saved
    /// routine's id.
    var moveTo: String?
    var minutes: Int?
    var routineId: String?

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case liftDate = "lift_date"
        case alternative
        case sportDate = "sport_date"
        case baseline, score
        case moveTo = "move_to"
        case minutes
        case routineId = "routine_id"
    }
}

extension FleetCounterfactualRow {
    // Written by hand so `score` is an explicit null rather than a missing
    // key; the extras stay omitted when they do not apply.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weekStart, forKey: .weekStart)
        try c.encode(liftDate, forKey: .liftDate)
        try c.encode(alternative, forKey: .alternative)
        try c.encode(sportDate, forKey: .sportDate)
        try c.encode(baseline, forKey: .baseline)
        if let score {
            try c.encode(score, forKey: .score)
        } else {
            try c.encodeNil(forKey: .score)
        }
        try c.encodeIfPresent(moveTo, forKey: .moveTo)
        try c.encodeIfPresent(minutes, forKey: .minutes)
        try c.encodeIfPresent(routineId, forKey: .routineId)
    }
}
