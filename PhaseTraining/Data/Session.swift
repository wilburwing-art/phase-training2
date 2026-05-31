// Session.swift — Session-shaped models for active + saved workouts.
// Ports `handoff/proto/data.jsx` session-object shape to Swift Codable structs.
//
// Numeric fields on LoggedSet are intentionally `String` to match the prototype's
// TextField binding semantics (raw text in, blank-allowed).

import Foundation

struct LoggedSet: Codable, Equatable {
    var num: Int
    var weight: String
    var reps: String
    var rpe: String
    var done: Bool
    /// Marks a warm-up set. Warmup sets are tracked + displayed in the log
    /// but EXCLUDED from PR detection, volume aggregation, and Epley 1RM
    /// math (see UserDatabase.bestWeightsByExerciseAndReps, MuscleVolume,
    /// StrengthStandards, GeneratorContext.buildStagnantExercises). Optional
    /// on decode so pre-build-100 sessions round-trip cleanly without a
    /// JSON migration; defaults to false.
    var isWarmup: Bool = false
    /// Reps-in-reserve (build 103). Distinct from RPE: RIR records how many
    /// reps the user had left in the tank ("3 RIR" = could have done 3
    /// more). The science-based era cohort speaks in RIR terms, and the
    /// data flows directly into hypertrophy autoregulation. Stored as raw
    /// String to match the rest of the row (TextField-friendly, "blank =
    /// unspecified" sentinel). Optional on decode so pre-build-103 sessions
    /// round-trip cleanly without migrating the JSON.
    var rir: String = ""

    enum CodingKeys: String, CodingKey {
        case num, weight, reps, rpe, done, isWarmup, rir
    }

    init(num: Int, weight: String, reps: String, rpe: String, done: Bool, isWarmup: Bool = false, rir: String = "") {
        self.num = num
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.done = done
        self.isWarmup = isWarmup
        self.rir = rir
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.num = try c.decode(Int.self, forKey: .num)
        self.weight = try c.decode(String.self, forKey: .weight)
        self.reps = try c.decode(String.self, forKey: .reps)
        self.rpe = try c.decode(String.self, forKey: .rpe)
        self.done = try c.decode(Bool.self, forKey: .done)
        self.isWarmup = (try? c.decode(Bool.self, forKey: .isWarmup)) ?? false
        self.rir = (try? c.decode(String.self, forKey: .rir)) ?? ""
    }
}

extension LoggedSet {
    /// Best-effort numeric load from the free-text `weight` field. The logger
    /// accepts raw text, so values arrive as "135", " 135 ", "+25", "60kg",
    /// "1,250", or "BW". `Double(weight)` rejects everything but a bare number,
    /// which silently drops padded/suffixed/comma'd sets from volume, PRs, and
    /// trend math. This tolerates a leading "+", surrounding whitespace,
    /// thousands separators, and a trailing unit; returns nil only when there's
    /// no number ("", "BW", "bodyweight") — callers using `?? 0` treat those as
    /// zero external load, which is correct for bodyweight movements.
    var weightValue: Double? { Self.leadingNumber(weight) }

    /// Best-effort rep count from the free-text `reps` field. Same tolerance as
    /// `weightValue`; a logged range like "8-10" yields the first number.
    /// `Int(exactly:)` (not trapping `Int(Double)`) so a pathologically long
    /// entry — stuck key, paste, bad CSV — yields nil instead of crashing the
    /// getter and every read path that calls it.
    var repsValue: Int? { Self.leadingNumber(reps).flatMap { Int(exactly: $0.rounded()) } }

    private static func leadingNumber(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("+") { s.removeFirst() }
        // Comma handling: with BOTH separators present, "," is a thousands
        // grouping ("1,250.5" -> "1250.5"). A lone "," is the decimal separator
        // on European keypads ("60,5" -> "60.5"), NOT a thousands mark —
        // stripping it would 10x the value.
        if s.contains(",") {
            s = s.contains(".")
                ? s.replacingOccurrences(of: ",", with: "")
                : s.replacingOccurrences(of: ",", with: ".")
        }
        let numeric = s.prefix { $0.isNumber || $0 == "." }
        return Double(numeric)
    }
}

struct LoggedExercise: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var type: String?
    var unit: String
    var targetSets: Int
    var targetReps: Int
    var rest: Int
    var sets: [LoggedSet]
    var prevSets: [LoggedSet]
    /// Coaching hints — propagated from ExerciseTemplate. Both optional so
    /// pre-build-70 saved sessions decode cleanly without a migration.
    var rpe: String?
    var tempo: String?
    /// Superset grouping — propagated from routine_exercises.superset_group
    /// (or CustomRoutineExercise.supersetGroup). Exercises sharing a value
    /// render adjacently with a colored band + "A1"/"A2" labels in the
    /// LogScreen + DayWorkoutPreviewSheet, and round-robin during rest
    /// navigation. Optional so pre-superset saved sessions decode cleanly.
    var supersetGroup: Int?
}

extension LoggedExercise {
    /// Sentinel `unit` value marking a reps-only / bodyweight exercise
    /// (bird dog, dead bug, plank-to-row, ...). The LogScreen reads this to
    /// collapse the weight input to a "BW" label so the user logs reps + done
    /// without tapping a 0 into every set. Weight stays addable for the rare
    /// weighted case (weight vest, holding a plate).
    static let bodyweightUnit = "bw"

    /// Map an `EquipmentCategory` to the weight-logging unit carried on the
    /// session row. `.repsOnly` collapses to bodyweight; everything else logs
    /// in lbs. Centralised so the generated / custom / bundled template
    /// builders stay in sync.
    static func unit(for category: EquipmentCategory?) -> String {
        category == .repsOnly ? bodyweightUnit : "lbs"
    }

    /// True when this row should hide the weight input by default.
    var isBodyweight: Bool { unit == Self.bodyweightUnit }

    /// Unit to show beside an actual numeric weight. The bodyweight sentinel
    /// is a logging-mode marker, not a real unit, so any load the user *did*
    /// log (weight vest, plate) reads in lbs rather than "bw".
    var displayUnit: String { isBodyweight ? "lbs" : unit }
}

struct ActiveSession: Codable, Equatable {
    var templateId: String
    var name: String
    var category: String
    var startTime: Date
    var exercises: [LoggedExercise]
    var feel: String?
    var note: String?
}

struct SavedSession: Codable, Identifiable, Equatable {
    var templateId: String
    var name: String
    var category: String
    var startTime: Date
    var exercises: [LoggedExercise]
    var feel: String?
    var note: String?
    var endTime: Date
    var duration: Int // seconds

    var id: TimeInterval { startTime.timeIntervalSince1970 }
}

struct SessionStats: Equatable {
    var totalSets: Int
    var doneSets: Int
    var avgRpe: String // matches prototype's "—" sentinel when no RPEs logged
}

/// A personal-record event: highest weight ever lifted at a given rep count
/// for a given exercise (matched by name). Emitted by `SessionStore.prs(in:)`
/// after each saved session for CompleteScreen to celebrate.
struct PersonalRecord: Equatable, Hashable {
    let exerciseName: String
    let reps: Int
    let weight: Double
    let previousBest: Double?
    let date: Date
}
