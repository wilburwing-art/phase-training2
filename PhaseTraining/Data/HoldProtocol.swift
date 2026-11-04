// HoldProtocol.swift — reads a timed prescription ("8s hold", "6 hangs (7s on /
// 3s off)", "30-60 sec") into what the hold timer runs.
//
// The generator writes holds as "<n>s hold" (`SetScheme.repsString`) and
// coach.db carries about 45 timed rep strings in a handful of shapes. A range
// takes its LOW end so the first attempt is achievable. Anything that is not
// clearly timed returns nil, and Log then shows no timer.

import Foundation

struct HoldProtocol: Equatable {
    /// Seconds under load per hang or hold.
    let onSeconds: Int
    /// Rest between hangs within one set (repeaters); nil for a single hold.
    var offSeconds: Int? = nil
    /// Hangs per set when the protocol names a count ("6 hangs", "8 x 5 sec").
    var reps: Int? = nil
    /// "per side", "per arm", "per leg": the hold runs once for each side.
    var perSide: Bool = false

    /// How many timed hangs one set runs: the named count, else one per side.
    var hangsPerSet: Int { max(1, reps ?? 1) * (perSide ? 2 : 1) }

    static func parse(_ raw: String?) -> HoldProtocol? {
        guard let raw else { return nil }
        let s = raw.lowercased().replacingOccurrences(of: "–", with: "-")
        let perSide = ["per side", "per arm", "per leg", "each side", "per hand"].contains { s.contains($0) }
        let unit = #"(?:s|sec|secs|second|seconds)\b"#

        // Repeaters: "6 hangs (7s on / 3s off)", "30s on / 30s off".
        if let m = match(#"(\d+)\s*"# + unit + #"\s*on\s*/\s*(\d+)\s*"# + unit + #"\s*off"#, s),
           let on = m[0], let off = m[1] {
            let count = match(#"^(\d+)\s*(?:hangs?|reps?|x)\b"#, s)?.first ?? nil
            return HoldProtocol(onSeconds: on, offSeconds: off, reps: count, perSide: perSide)
        }
        // Counted holds: "8-10 x 5 sec", "6-8 x 10 sec", "8-6-4 x 10 sec holds".
        if let m = match(#"^(\d+)(?:\s*-\s*\d+)*\s*x\s*(\d+)\s*"# + unit, s), let n = m[0], let on = m[1] {
            return HoldProtocol(onSeconds: on, reps: n, perSide: perSide)
        }
        // A single hold: "8s hold", "45 sec hold", "30-60 sec", "7-10 sec".
        if let m = match(#"^(\d+)(?:\s*-\s*\d+)?\s*"# + unit, s), let on = m[0] {
            return HoldProtocol(onSeconds: on, perSide: perSide)
        }
        return nil
    }

    /// Integer capture groups of the first match, nil when no match.
    private static func match(_ pattern: String, _ s: String) -> [Int?]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).flatMap { Int(s[$0]) }
        }
    }
}
