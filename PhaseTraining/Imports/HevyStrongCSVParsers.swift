// HevyStrongCSVParsers.swift — Hevy and Strong workout exports.
//
// Both write one row per set and both are read by header name, so a column
// added or reordered upstream doesn't break them. Neither format ships a spec;
// the shapes below come from the importers other apps maintain for them:
//
//   Hevy  "title","start_time","end_time","description","exercise_title",
//         "superset_id","exercise_notes","set_index","set_type","weight_kg",
//         "reps","distance_km","duration_seconds","rpe"
//         (aree6/LiftShift). Imperial exports carry weight_lbs instead
//         (astashov/liftosaur). set_type "warmup" marks a warm-up. start_time
//         is local and named-month: "8 Feb 2024, 12:16" or
//         "Oct 17, 2026, 8:30 AM".
//   Strong Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,
//         Distance,Seconds,Notes,Workout Notes,RPE
//         Newer exports use ";" and add "Weight Unit" (TraceApps/lifttrace);
//         some name the column "Weight (kg)" (IgnisDa/ryot). Date is local
//         "yyyy-MM-dd HH:mm:ss".
//
// Output matches FitbodCSVParser: kilograms, warm-ups counted and dropped,
// rows without reps reported as errors.

import Foundation

/// Accumulates parsed sets with per-(workout, exercise) set numbers and a
/// memoized name resolver, the bookkeeping every CSV parser shares.
private struct ImportedSetBuilder {
    let source: ImportSource
    let resolve: (String) -> Int?
    var sets: [ImportedSet] = []
    var errors: [(line: Int, raw: String, reason: String)] = []
    var totalRows = 0
    var warmupsSkipped = 0
    private var counters: [String: Int] = [:]
    private var resolved: [String: Int?] = [:]

    init(source: ImportSource, resolve: @escaping (String) -> Int?) {
        self.source = source
        self.resolve = resolve
    }

    mutating func add(name: String, at: Date, kg: Double?, reps: Int, rpe: Double?) {
        if resolved[name] == nil { resolved[name] = .some(resolve(name)) }
        let key = "\(Int64(at.timeIntervalSince1970))|\(name)"
        let n = (counters[key] ?? 0) + 1
        counters[key] = n
        sets.append(ImportedSet(id: ImportedSet.makeId(source: source, performedAt: at, exerciseNameRaw: name, setNum: n),
                                source: source, exerciseId: resolved[name] ?? nil, exerciseNameRaw: name,
                                performedAt: at, setNum: n,
                                weight: (kg ?? 0) > 0 ? kg : nil, reps: reps, rir: nil, rpe: rpe))
    }

    func result() -> FitbodCSVParser.ParseResult {
        let matched = resolved.values.compactMap { $0 }.count
        return FitbodCSVParser.ParseResult(sets: sets, workouts: [], errors: errors,
                                           nameMatchRate: resolved.isEmpty ? 0 : Double(matched) / Double(resolved.count),
                                           totalRows: totalRows, warmupsSkipped: warmupsSkipped)
    }
}

private func headerIndex(_ header: [String]) -> [String: Int] {
    Dictionary(header.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
}

private func number(_ s: String?) -> Double? {
    guard let s, !s.isEmpty else { return nil }
    return Double(s.replacingOccurrences(of: ",", with: "."))
}

// MARK: - Hevy

enum HevyCSVParser {

    static func looksLikeHeader(_ fields: [String]) -> Bool {
        let h = Set(fields.map { $0.lowercased() })
        return h.contains("exercise_title") && h.contains("set_index")
    }

    static func parse(_ csv: String, nameResolver: @escaping (String) -> Int?) -> FitbodCSVParser.ParseResult {
        var b = ImportedSetBuilder(source: .hevyCSV, resolve: nameResolver)
        let rows = CSVRows.parse(csv, delimiter: ",")
        guard let header = rows.first, looksLikeHeader(header.fields) else {
            b.errors.append((1, rows.first?.fields.joined(separator: ",") ?? "", "not a Hevy header"))
            return b.result()
        }
        let col = headerIndex(header.fields)
        let lbs = col["weight_lbs"] != nil
        func cell(_ r: [String], _ name: String) -> String? { col[name].flatMap { $0 < r.count ? r[$0] : nil } }

        for (line, r) in rows.dropFirst() {
            b.totalRows += 1
            let raw = r.joined(separator: ",")
            guard let name = cell(r, "exercise_title"), !name.isEmpty else { b.errors.append((line, raw, "empty exercise_title")); continue }
            guard let start = cell(r, "start_time"), let at = parseDate(start) else {
                b.errors.append((line, raw, "unparseable start_time \"\(cell(r, "start_time") ?? "")\"")); continue
            }
            if cell(r, "set_type")?.lowercased() == "warmup" { b.warmupsSkipped += 1; continue }
            guard let reps = number(cell(r, "reps")).map({ Int($0) }), reps > 0 else {
                b.errors.append((line, raw, "no reps")); continue
            }
            let w = number(cell(r, lbs ? "weight_lbs" : "weight_kg"))
            b.add(name: name, at: at, kg: w.map { lbs ? $0 * ImportUnitCorrection.kgPerLb : $0 },
                  reps: reps, rpe: number(cell(r, "rpe")))
        }
        return b.result()
    }

    /// Hevy writes local, named-month times; an ISO time is accepted too.
    static func parseDate(_ s: String) -> Date? {
        for format in ["d MMM yyyy, HH:mm", "MMM d, yyyy, h:mm a", "d MMM yyyy, h:mm a", "MMM d, yyyy, HH:mm",
                       "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - Strong

enum StrongCSVParser {

    /// Where the weight unit came from, so the import summary can say.
    enum UnitSource: Equatable {
        case column, header, assumed
    }

    static func looksLikeHeader(_ fields: [String]) -> Bool {
        let h = Set(fields.map { $0.lowercased() })
        return h.contains("exercise name") && h.contains("set order")
    }

    static func delimiter(forHeaderLine line: String) -> Character {
        line.contains(";") ? ";" : ","
    }

    static func parse(_ csv: String, fallbackImperial: Bool,
                      nameResolver: @escaping (String) -> Int?) -> (result: FitbodCSVParser.ParseResult, imperial: Bool, unitSource: UnitSource) {
        var b = ImportedSetBuilder(source: .strongCSV, resolve: nameResolver)
        let firstLine = csv.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let rows = CSVRows.parse(csv, delimiter: delimiter(forHeaderLine: firstLine))
        guard let header = rows.first, looksLikeHeader(header.fields) else {
            b.errors.append((1, firstLine, "not a Strong header"))
            return (b.result(), fallbackImperial, .assumed)
        }
        let col = headerIndex(header.fields)
        func cell(_ r: [String], _ name: String) -> String? { col[name].flatMap { $0 < r.count ? r[$0] : nil } }

        // Unit: a per-row column wins, then a suffix on the weight header,
        // then the user's own setting.
        let weightKey = header.fields.map { $0.lowercased() }.first { $0.hasPrefix("weight") && $0 != "weight unit" } ?? "weight"
        let headerUnit: Bool? = weightKey.contains("(kg)") ? false : (weightKey.contains("(lb") ? true : nil)
        let hasUnitColumn = col["weight unit"] != nil
        let unitSource: UnitSource = hasUnitColumn ? .column : (headerUnit != nil ? .header : .assumed)
        let fileImperial = headerUnit ?? fallbackImperial

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for (line, r) in rows.dropFirst() {
            b.totalRows += 1
            let raw = r.joined(separator: ",")
            guard let name = cell(r, "exercise name"), !name.isEmpty else { b.errors.append((line, raw, "empty Exercise Name")); continue }
            guard let at = cell(r, "date").flatMap(f.date(from:)) else {
                b.errors.append((line, raw, "unparseable date \"\(cell(r, "date") ?? "")\"")); continue
            }
            if cell(r, "set order")?.uppercased() == "W" { b.warmupsSkipped += 1; continue }
            guard let reps = number(cell(r, "reps")).map({ Int($0) }), reps > 0 else {
                b.errors.append((line, raw, "no reps")); continue
            }
            let rowImperial: Bool
            if hasUnitColumn, let u = cell(r, "weight unit")?.lowercased(), !u.isEmpty {
                rowImperial = u.hasPrefix("lb")
            } else {
                rowImperial = fileImperial
            }
            let w = number(cell(r, weightKey))
            b.add(name: name, at: at, kg: w.map { rowImperial ? $0 * ImportUnitCorrection.kgPerLb : $0 },
                  reps: reps, rpe: number(cell(r, "rpe")))
        }
        return (b.result(), fileImperial, unitSource)
    }
}
