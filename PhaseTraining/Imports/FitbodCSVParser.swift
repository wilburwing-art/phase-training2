// FitbodCSVParser.swift — Phase 3 Fitbod history importer.
//
// Schema (observed from a 5,441-row real-user export spanning 2016-2026):
//
//   Date,Exercise,Reps,Weight(kg),Duration(s),Distance(m),Incline,
//   Resistance,isWarmup,Note,multiplier
//
//   - Date: "YYYY-MM-DD HH:MM:SS +0000" — ISO-like with EXPLICIT offset.
//     All sets within a single workout share the same Date timestamp
//     (Fitbod stamps the session start time on every row), so we cluster
//     by date to derive setNum within each (date, exercise) group.
//   - Reps: int (leading-space-padded ' 10' is common).
//   - Weight(kg): float (' 22.6796...' — Fitbod stores conversions
//     from lb at 6+ decimal places). 0.0 means bodyweight.
//   - Duration(s) > 0: cardio row; we emit an `ImportedWorkout` instead
//     of an `ImportedSet`.
//   - isWarmup: "true" / "false". We skip warmup rows from set-level
//     persistence — they're noise for priorBest/peak detection.
//   - multiplier: 1.0 normally, 2.0 for some bilateral logs (e.g.
//     "Dumbbell Row" in some Fitbod versions). We do NOT multiply set
//     counts — multiplier is a Fitbod display artifact, not a real "two
//     sets in one row" signal. The set-num clustering handles real
//     repetition.
//
// Field padding: many cells have a single leading space (' 10' instead
// of '10'). We trim on every field.
//
// Quote handling: the CSV format does NOT use quotes in the observed
// export. We split on naive commas. If a Note field contains a comma the
// row will be miscounted — surfaced as a parse error rather than silently
// corrupted.

import Foundation

enum FitbodCSVParser {

    /// Result of parsing a Fitbod history CSV.
    struct ParseResult {
        let sets: [ImportedSet]
        let workouts: [ImportedWorkout]
        /// (line number, raw line, reason) for rows that failed to parse.
        /// Non-fatal; the rest of the import succeeds.
        let errors: [(line: Int, raw: String, reason: String)]
        /// Resolved-vs-unresolved exercise-name match rate. Surfaced in
        /// the Settings → Imports screen so the user can see catalog
        /// coverage at a glance.
        let nameMatchRate: Double
        let totalRows: Int
    }

    /// Required header row. Exact match — any deviation surfaces a parse
    /// error rather than silently picking columns out of order.
    static let expectedHeader = "Date,Exercise,Reps,Weight(kg),Duration(s),Distance(m),Incline,Resistance,isWarmup,Note,multiplier"

    /// Parse a Fitbod CSV from raw text. The `nameResolver` closure
    /// receives each unique exercise name and returns its coach.db id
    /// (or nil). The closure is injected so tests can stub it without a
    /// live CoachDatabase.
    static func parse(_ csv: String, source: ImportSource = .fitbodCSV, nameResolver: (String) -> Int?) -> ParseResult {
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
        guard let headerLine = lines.first?.trimmingCharacters(in: .whitespaces) else {
            return ParseResult(sets: [], workouts: [], errors: [(0, "", "empty file")], nameMatchRate: 0, totalRows: 0)
        }
        guard headerLine == expectedHeader else {
            return ParseResult(sets: [], workouts: [], errors: [(0, headerLine, "header mismatch — expected \"\(expectedHeader)\"")], nameMatchRate: 0, totalRows: 0)
        }

        // Cluster by (date, exercise) to derive set numbers per group.
        // We walk the file in order so within a date the per-exercise
        // sequence is the user's logged order — set 1 first, set 2 next.
        var counters: [String: Int] = [:]  // key: "ts|name", val: next setNum
        var resolved: [String: Int?] = [:]  // memoize per unique raw name

        var sets: [ImportedSet] = []
        var workouts: [ImportedWorkout] = []
        var errors: [(Int, String, String)] = []
        var totalRows = 0

        // ISO-with-offset formatter shared across rows.
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss xxx"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)

        for (idx, rawLine) in lines.enumerated() {
            // skip header (idx 0) and any trailing blank line
            if idx == 0 { continue }
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            totalRows += 1

            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 11 else {
                errors.append((idx + 1, line, "expected 11 cells, got \(cells.count)"))
                continue
            }

            let dateRaw = cells[0]
            let exName = cells[1]
            let repsRaw = cells[2]
            let weightRaw = cells[3]
            let durationRaw = cells[4]
            let isWarmupRaw = cells[8].lowercased()
            // cells[5..7] (distance/incline/resistance) and cells[9..10]
            // (note/multiplier) are not consumed in v1.

            guard let performedAt = fmt.date(from: dateRaw) else {
                errors.append((idx + 1, line, "unparseable date \"\(dateRaw)\""))
                continue
            }
            if exName.isEmpty {
                errors.append((idx + 1, line, "empty Exercise"))
                continue
            }

            let weight = Double(weightRaw)
            let reps = Int(repsRaw)
            let duration = Double(durationRaw) ?? 0

            // Cardio detection: Duration > 0 AND (no weight OR no reps).
            // We emit ImportedWorkout for these so Phase 2's readiness
            // signal still picks them up via density/recency.
            if duration > 0 && (weight ?? 0) == 0 && (reps ?? 0) == 0 {
                let id = "\(source.rawValue):cardio:\(Int64(performedAt.timeIntervalSince1970)):\(exName)"
                workouts.append(ImportedWorkout(
                    id: id,
                    source: source,
                    kind: .cardio,
                    startTime: performedAt,
                    duration: duration,
                    energyKcal: nil
                ))
                continue
            }

            // Skip warmup rows for set-level persistence.
            if isWarmupRaw == "true" { continue }

            // Strength row. We accept rows with zero weight (bodyweight)
            // as long as they carry reps.
            guard let r = reps, r > 0 else {
                errors.append((idx + 1, line, "non-warmup row with reps=\"\(repsRaw)\""))
                continue
            }

            // Resolve exerciseId once per unique raw name.
            let exId: Int?
            if let cached = resolved[exName] {
                exId = cached
            } else {
                let resolvedId = nameResolver(exName)
                resolved[exName] = resolvedId
                exId = resolvedId
            }

            // setNum within (date, name) group.
            let key = "\(Int64(performedAt.timeIntervalSince1970))|\(exName)"
            let setNum = (counters[key] ?? 0) + 1
            counters[key] = setNum

            let id = ImportedSet.makeId(
                source: source,
                performedAt: performedAt,
                exerciseNameRaw: exName,
                setNum: setNum
            )

            // Weight 0.0 → nil to preserve "bodyweight" semantics.
            let storedWeight: Double? = (weight ?? 0) > 0 ? weight : nil

            sets.append(ImportedSet(
                id: id,
                source: source,
                exerciseId: exId,
                exerciseNameRaw: exName,
                performedAt: performedAt,
                setNum: setNum,
                weight: storedWeight,
                reps: r,
                rir: nil,  // Fitbod doesn't capture RIR
                rpe: nil   // nor RPE
            ))
        }

        let resolvedCount = resolved.values.compactMap { $0 }.count
        let matchRate = resolved.isEmpty ? 0 : Double(resolvedCount) / Double(resolved.count)

        return ParseResult(
            sets: sets,
            workouts: workouts,
            errors: errors,
            nameMatchRate: matchRate,
            totalRows: totalRows
        )
    }
}
