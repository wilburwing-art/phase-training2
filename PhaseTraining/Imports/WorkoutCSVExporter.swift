// WorkoutCSVExporter.swift — the lifter's logged workouts as a Strong-format CSV.
//
// The app imports Fitbod, Hevy and Strong exports (build 165); this is the way
// back out. Strong's CSV is the format the most other apps import, and our own
// StrongCSVParser reads it, so a round trip is testable here. The header is the
// classic comma form other apps' importers read; which apps accept the file is
// verified only by trying one (it was read from importer source, not from a
// Strong file).
//
// Only sessions logged in the app: imported sessions came from those apps.

import Foundation

enum WorkoutCSVExporter {

    static let header = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE"

    /// Oldest session first, one row per done set. Weights are written in the
    /// lifter's unit (Strong carries no unit column), so a session logged in kg
    /// by a user now on lb is converted and one file holds one unit.
    static func csv(sessions: [SavedSession], usesImperial: Bool) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = .current
        date.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = [header]
        for session in sessions.sorted(by: { $0.startTime < $1.startTime }) {
            var firstOfSession = true
            for ex in session.exercises {
                var firstOfExercise = true
                var working = 0
                for set in ex.sets where set.done {
                    let order: String
                    switch set.setType {
                    case .warmup: order = "W"
                    case .drop: order = "D"
                    case .failure: order = "F"
                    case .normal: working += 1; order = "\(working)"
                    }
                    let fields = [
                        date.string(from: session.startTime),
                        session.name,
                        duration(session.duration),
                        ex.name,
                        order,
                        weight(set, unit: ex.unit, usesImperial: usesImperial),
                        set.repsValue.map(String.init) ?? "",
                        "",
                        "",
                        firstOfExercise ? (ex.note ?? "") : "",
                        firstOfSession ? (session.note ?? "") : "",
                        set.rpe.trimmingCharacters(in: .whitespaces),
                    ]
                    lines.append(fields.map(quote).joined(separator: ","))
                    firstOfExercise = false
                    firstOfSession = false
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the file the share sheet hands on, named for today.
    static func writeTempFile(_ csv: String, now: Date = Date()) throws -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase-training-workouts-\(f.string(from: now)).csv")
        try Data(csv.utf8).write(to: url, options: [.atomic])
        return url
    }

    private static func weight(_ set: LoggedSet, unit: String, usesImperial: Bool) -> String {
        guard let w = set.weightValue, w > 0 else { return "" }
        // "lbs" and the bodyweight sentinel both mean pounds (a vest or plate
        // on a bodyweight row reads in lbs, `LoggedExercise.displayUnit`).
        let isKg = unit.lowercased() == "kg"
        let value: Double
        switch (isKg, usesImperial) {
        case (true, true): value = w / ImportUnitCorrection.kgPerLb
        case (false, false): value = w * ImportUnitCorrection.kgPerLb
        default: value = w
        }
        let r = (value * 10).rounded() / 10
        return r.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(r)) : String(r)
    }

    private static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// RFC 4180: quote a field holding a comma, quote or line break, doubling quotes.
    private static func quote(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
