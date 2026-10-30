// ImportedHistorySessions.swift — imported sets shaped as read-only sessions.
//
// History, Progress and PR detection all read `SavedSession`. Imported sets
// (Fitbod CSV) arrive flat, one row per set, so this groups them into one
// session per `performedAt` (the same rule `ImportUnitCorrection` uses) and
// hands the screens the shape they already render.
//
// These never enter `SessionStore.savedSessions`: backup, the generator,
// recovery and `HistoryProfile` keep reading native sessions only, so nothing
// is counted twice and nothing is written back. Sets `HistoryProfile` flagged
// (impossible, outlier, duplicate) are left out, which keeps a typo like a
// 397 lb bench from becoming an all-time PR and drops a workout logged in
// both apps during the switch.

import Foundation

enum ImportedHistorySessions {

    static let templatePrefix = "import:"

    /// Newest first. Weights are in the user's unit, rounded to 0.1 so a
    /// pound number typed in Fitbod (stored as 83.9146 kg) reads "185" and
    /// compares equal to a native 185.
    static func build(imported: [ImportedSet], excluded: Set<String>, usesImperial: Bool) -> [SavedSession] {
        let catalog = CoachDatabase.shared
        var names: [Int: String] = [:]
        func name(_ set: ImportedSet) -> String {
            guard let id = set.exerciseId else { return set.exerciseNameRaw }
            if let n = names[id] { return n }
            let n = catalog.exercise(id: id)?.name ?? set.exerciseNameRaw
            names[id] = n
            return n
        }

        // A set with neither weight nor reps (a cardio row) has nothing to show.
        let kept = imported.filter { !excluded.contains($0.id) && ($0.reps ?? 0) > 0 }
        return Dictionary(grouping: kept, by: \.performedAt)
            .map { start, sets in
                // imported_sets keeps no within-workout order, so exercises
                // read alphabetically and sets by their number.
                let byName = Dictionary(grouping: sets, by: name)
                let exercises = byName.keys.sorted().enumerated().map { i, n -> LoggedExercise in
                    let rows = byName[n]!.sorted { $0.setNum < $1.setNum }
                    let loaded = rows.contains { ($0.weight ?? 0) > 0 }
                    let logged = rows.enumerated().map { j, s in
                        LoggedSet(num: j + 1,
                                  weight: s.weight.flatMap { $0 > 0 ? display(kg: $0, usesImperial: usesImperial) : nil } ?? "",
                                  reps: s.reps.map(String.init) ?? "",
                                  rpe: s.rpe.map { display($0) } ?? "",
                                  done: true)
                    }
                    return LoggedExercise(
                        id: "import-\(i)", name: n, type: nil,
                        unit: loaded ? (usesImperial ? "lbs" : "kg") : LoggedExercise.bodyweightUnit,
                        targetSets: logged.count, targetReps: rows.compactMap(\.reps).max() ?? 0,
                        rest: 0, sets: logged, prevSets: [])
                }
                let source = sets[0].source
                return SavedSession(templateId: templatePrefix + source.rawValue,
                                    name: "\(sourceName(source)) workout", category: "Imported",
                                    startTime: start, exercises: exercises,
                                    endTime: start, duration: 0)
            }
            .sorted { $0.startTime > $1.startTime }
    }

    static func sourceName(_ source: ImportSource) -> String {
        switch source {
        case .fitbodCSV: return "Fitbod"
        case .hevyCSV: return "Hevy"
        case .stravaCSV: return "Strava"
        case .strongCSV: return "Strong"
        case .healthKit: return "Apple Health"
        }
    }

    static func display(kg: Double, usesImperial: Bool) -> String {
        display(usesImperial ? kg / ImportUnitCorrection.kgPerLb : kg)
    }

    private static func display(_ value: Double) -> String {
        let r = (value * 10).rounded() / 10
        return r.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(r)) : String(r)
    }
}

extension SavedSession {
    /// The import source for a session built by `ImportedHistorySessions`,
    /// nil for sessions logged in the app.
    var importSource: ImportSource? {
        guard templateId.hasPrefix(ImportedHistorySessions.templatePrefix) else { return nil }
        return ImportSource(rawValue: String(templateId.dropFirst(ImportedHistorySessions.templatePrefix.count)))
    }
}
