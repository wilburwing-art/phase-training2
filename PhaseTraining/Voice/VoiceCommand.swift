import Foundation

enum VoiceUnit: Equatable { case lb, kg }

struct VoiceContext: Equatable {
    /// Current exercise logs reps only (LoggedExercise.isBodyweight).
    var isBodyweight: Bool = false
}

/// One spoken command during a workout. `parse` maps a recognizer transcript
/// to a command, or nil when the transcript is unclear, out of range, or asks
/// for anything that deletes or ends. A wrong log is worse than a re-ask, so
/// every ambiguous shape returns nil.
enum VoiceCommand: Equatable {
    /// weight nil = keep the set's current or last weight ("same weight for 5",
    /// bodyweight reps). unit nil = not spoken; the caller uses the exercise unit.
    case logSet(weight: Double?, reps: Int, rpe: Double?, unit: VoiceUnit?)
    case sameAgain, completeSet, skipRest
    case addRest(seconds: Int)
    case whatsNext, setsLeft, undo

    static func parse(_ transcript: String, context: VoiceContext) -> VoiceCommand? {
        let tokens = Grammar.normalize(transcript)
        guard !tokens.isEmpty else { return nil }
        if tokens.contains(where: Grammar.refused.contains) { return nil }

        let words = tokens.filter { !Grammar.fillers.contains($0) }
        guard !words.isEmpty else { return nil }

        if let fixed = Grammar.fixedPhrases[words.joined(separator: " ")] { return fixed }
        if let rest = Grammar.addRest(words) { return rest.map { .addRest(seconds: $0) } }
        return Grammar.logSet(words, context: context)
    }
}

private enum Grammar {

    // MARK: - Vocabulary

    static let refused: Set<String> = [
        "delete", "remove", "erase", "clear", "end", "ending", "finish", "finished",
        "cancel", "discard", "quit", "stop", "reset", "restart", "abandon",
    ]

    static let fillers: Set<String> = [
        "uh", "um", "er", "ok", "okay", "hey", "please", "so", "like", "alright", "yeah", "then",
    ]

    static let fixedPhrases: [String: VoiceCommand] = {
        var map: [String: VoiceCommand] = [:]
        let table: [(VoiceCommand, [String])] = [
            (.sameAgain, ["same again", "same", "again", "same as last", "same as last time",
                          "same as before", "repeat", "repeat that", "same thing", "one more"]),
            (.completeSet, ["done", "set done", "got it", "complete", "completed", "set complete", "check"]),
            (.skipRest, ["skip", "skip rest", "skip the rest", "skip timer", "skip the timer",
                         "im ready", "ready"]),
            (.whatsNext, ["whats next", "what is next", "next", "whats up next", "what now",
                          "next set", "next exercise"]),
            (.setsLeft, ["how many left", "how many sets left", "sets left", "how many more",
                         "how many to go", "how many sets to go", "how many remaining"]),
            (.undo, ["undo", "undo that", "scratch that", "take that back", "go back", "oops"]),
        ]
        for (command, phrases) in table {
            for phrase in phrases { map[phrase] = command }
        }
        return map
    }()

    static let separators: Set<String> = ["for", "fore", "by", "x", "times", "×"]

    static let units: [String: VoiceUnit] = [
        "lb": .lb, "lbs": .lb, "pound": .lb, "pounds": .lb,
        "kg": .kg, "kgs": .kg, "kilo": .kg, "kilos": .kg, "kilogram": .kg, "kilograms": .kg,
    ]

    static let secondWords: Set<String> = ["second", "seconds", "sec", "secs"]
    static let minuteWords: Set<String> = ["minute", "minutes", "min", "mins"]

    static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "won": 1, "to": 2, "too": 2, "ate": 8,
    ]
    static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Number words that are always numbers. "four", "to"/"too", "a", "and",
    /// "point", "half" and "oh" depend on their neighbours.
    static let coreNumberWords: Set<String> = {
        var s = Set(ones.keys).union(teens.keys).union(tens.keys)
        s.insert("hundred")
        s.subtract(["four", "to", "too"])
        return s
    }()

    // MARK: - Rule 1: normalize

    static func normalize(_ raw: String) -> [String] {
        let chars = Array(raw.lowercased())
        var out = ""
        var last: Character = " "
        func emit(_ c: Character) { out.append(c); last = c }
        for (i, c) in chars.enumerated() {
            if c == "'" || c == "\u{2019}" || c == "\u{2018}" { continue }
            if isDigit(c) {
                if last.isLetter { emit(" ") }
                emit(c)
            } else if c == "×" {
                emit(" "); emit("×"); emit(" ")
            } else if c.isLetter {
                if isDigit(last) { emit(" ") }
                emit(c)
            } else if (c == "." || c == ","), isDigit(last), i + 1 < chars.count, isDigit(chars[i + 1]) {
                emit(c)
            } else {
                emit(" ")
            }
        }
        return out.split(whereSeparator: { $0 == " " }).map(String.init)
    }

    static func isDigit(_ c: Character) -> Bool { ("0"..."9").contains(c) }

    static func isDigitToken(_ t: String) -> Bool { t.first.map(isDigit) ?? false }

    /// Same rules as `LoggedSet.leadingNumber`: with both separators "," is a
    /// thousands mark, a lone "," is a decimal point.
    static func digitValue(_ token: String) -> Double? {
        var s = token.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("+") { s.removeFirst() }
        if s.contains(",") {
            s = s.contains(".")
                ? s.replacingOccurrences(of: ",", with: "")
                : s.replacingOccurrences(of: ",", with: ".")
        }
        let numeric = s.prefix { $0.isNumber || $0 == "." }
        return Double(numeric)
    }

    // MARK: - Rule 5: addRest

    /// nil = not an addRest shape. `.some(nil)` = an addRest shape with a bad
    /// value, which makes the whole command nil.
    static func addRest(_ w: [String]) -> Int?? {
        if w.first == "add" || w.first == "plus" {
            let rest = Array(w.dropFirst())
            if rest == ["a", "minute"] { return .some(60) }
            if rest == ["half", "a", "minute"] { return .some(30) }
            return .some(restSeconds(rest))
        }
        if w.count >= 3, w[0] == "give", w[1] == "me" {
            var rest = Array(w.dropFirst(2))
            if let u = rest.last, secondWords.contains(u) || minuteWords.contains(u) {
                guard rest.count >= 2, rest[rest.count - 2] == "more" else { return .some(nil) }
                rest.remove(at: rest.count - 2)
                return .some(restSeconds(rest))
            }
            guard rest.last == "more" else { return .some(nil) }
            return .some(restSeconds(Array(rest.dropLast())))
        }
        if w.count >= 3, w[w.count - 2] == "more",
           secondWords.contains(w[w.count - 1]) || minuteWords.contains(w[w.count - 1]) {
            var rest = w
            rest.remove(at: w.count - 2)
            return .some(restSeconds(rest))
        }
        return nil
    }

    /// `N [unit]`, seconds by default. Valid 1...600.
    static func restSeconds(_ tokens: [String]) -> Int? {
        var numberTokens = tokens
        var multiplier = 1.0
        if let u = numberTokens.last {
            if secondWords.contains(u) { numberTokens.removeLast() }
            else if minuteWords.contains(u) { numberTokens.removeLast(); multiplier = 60 }
        }
        guard !numberTokens.isEmpty,
              numberMask(numberTokens).allSatisfy({ $0 == .number }),
              let value = runValue(numberTokens) else { return nil }
        let seconds = value * multiplier
        guard seconds == seconds.rounded(), let s = Int(exactly: seconds), (1...600).contains(s) else { return nil }
        return s
    }

    // MARK: - Rule 6: numbers

    enum TokenRole: Equatable { case number, separator, other }

    static func numberMask(_ t: [String]) -> [TokenRole] {
        let n = t.count
        var role = [TokenRole](repeating: .other, count: n)
        let core = t.map { isDigitToken($0) || coreNumberWords.contains($0) }
        func coreAt(_ i: Int) -> Bool { i >= 0 && i < n && core[i] }
        func sepAt(_ i: Int) -> Bool { i >= 0 && i < n && separators.contains(t[i]) }

        for i in 0..<n {
            if core[i] { role[i] = .number; continue }
            switch t[i] {
            case "four":
                role[i] = coreAt(i - 1) && coreAt(i + 1) ? .separator : .number
            case "to", "too":
                // 2 only next to a number or separator, and never between two
                // numbers: "go to next" stays words, "185 to 5" stays a gap.
                let between = coreAt(i - 1) && coreAt(i + 1)
                let anchored = coreAt(i - 1) || coreAt(i + 1) || sepAt(i - 1) || sepAt(i + 1)
                role[i] = !between && anchored ? .number : .other
            case let s where separators.contains(s):
                role[i] = .separator
            default:
                break
            }
        }
        for i in 0..<n where t[i] == "a" && i + 1 < n && (t[i + 1] == "hundred" || t[i + 1] == "half") {
            role[i] = .number
        }
        for i in 0..<n where t[i] == "half" && i > 0 && t[i - 1] == "a" {
            role[i] = .number
        }
        var changed = true
        while changed {
            changed = false
            for i in 0..<n where role[i] == .other {
                let prevNum = i > 0 && role[i - 1] == .number
                let nextNum = i + 1 < n && role[i + 1] == .number
                let promote: Bool
                switch t[i] {
                case "and": promote = prevNum && nextNum
                case "point": promote = prevNum && (nextNum || (i + 1 < n && t[i + 1] == "oh"))
                case "oh": promote = prevNum
                default: promote = false
                }
                if promote { role[i] = .number; changed = true }
            }
        }
        return role
    }

    /// Value of one maximal run of number tokens. nil when the run is not a
    /// single well-formed number ("185 5", "185 five", "a half").
    static func runValue(_ run: [String]) -> Double? {
        var tokens = run
        var addHalf = false
        if tokens.count >= 4, Array(tokens.suffix(3)) == ["and", "a", "half"] {
            tokens.removeLast(3)
            addHalf = true
        }
        if tokens.contains(where: isDigitToken) {
            guard tokens.count == 1, let v = digitValue(tokens[0]) else { return nil }
            if addHalf { guard v == v.rounded() else { return nil } }
            return v + (addHalf ? 0.5 : 0)
        }
        var fraction = 0.0
        if let p = tokens.firstIndex(of: "point") {
            guard !addHalf, p > 0 else { return nil }
            let digits = tokens[(p + 1)...]
            guard !digits.isEmpty else { return nil }
            var scale = 0.1
            for d in digits {
                guard let v = d == "oh" ? 0 : ones[d] else { return nil }
                fraction += Double(v) * scale
                scale /= 10
            }
            tokens = Array(tokens[..<p])
        }
        guard let whole = integerValue(tokens) else { return nil }
        return Double(whole) + fraction + (addHalf ? 0.5 : 0)
    }

    static func integerValue(_ t: [String]) -> Int? {
        if let h = t.firstIndex(of: "hundred") {
            let head = t[..<h]
            let multiplier: Int
            if head == ["a"] { multiplier = 1 }
            else if head.count == 1, let d = ones[head[head.startIndex]], d >= 1 { multiplier = d }
            else { return nil }
            var tail = Array(t[(h + 1)...])
            if tail.first == "and" {
                tail.removeFirst()
                guard !tail.isEmpty else { return nil }
            }
            if tail.isEmpty { return multiplier * 100 }
            guard let below = belowHundred(tail), below >= 1 else { return nil }
            return multiplier * 100 + below
        }
        if let v = belowHundred(t) { return v }
        // Spoken load: a digit word then a tens or teen word is hundreds.
        guard t.count >= 2, let lead = ones[t[0]], lead >= 1 else { return nil }
        let rest = Array(t.dropFirst())
        if rest.count == 2, rest[0] == "oh", let d = ones[rest[1]], d >= 1 { return lead * 100 + d }
        if rest.count == 1, let teen = teens[rest[0]] { return lead * 100 + teen }
        if let ten = tens[rest[0]] {
            if rest.count == 1 { return lead * 100 + ten }
            if rest.count == 2, let d = ones[rest[1]], d >= 1 { return lead * 100 + ten + d }
        }
        return nil
    }

    static func belowHundred(_ t: [String]) -> Int? {
        switch t.count {
        case 1:
            return ones[t[0]] ?? teens[t[0]] ?? tens[t[0]]
        case 2:
            guard let ten = tens[t[0]], let d = ones[t[1]], d >= 1 else { return nil }
            return ten + d
        default:
            return nil
        }
    }

    // MARK: - Rule 7: logSet

    enum Item: Equatable {
        case number(Double), separator, unit(VoiceUnit), reps, rpe, weightWord, same
    }

    static func logSet(_ words: [String], context: VoiceContext) -> VoiceCommand? {
        guard var items = items(words) else { return nil }

        var rpe: Double?
        let rpeMarks = items.indices.filter { items[$0] == .rpe }
        if !rpeMarks.isEmpty {
            guard rpeMarks.count == 1, rpeMarks[0] == items.count - 2,
                  case .number(let value) = items[items.count - 1] else { return nil }
            guard (1...10).contains(value), (value * 2) == (value * 2).rounded() else { return nil }
            rpe = value
            items.removeLast(2)
        }

        var unit: VoiceUnit?
        var unitIndex: Int?
        for (i, item) in items.enumerated() {
            if case .unit(let u) = item {
                guard unit == nil else { return nil }
                unit = u
                unitIndex = i
            }
        }
        let unitAtEnd = unitIndex == items.count - 1
        let unitAfterWeight = unitIndex == 1
        if let i = unitIndex { items.remove(at: i) }

        var core = items
        if core.last == .reps { core.removeLast() }
        let hadReps = core.count != items.count

        func reps(_ v: Double) -> Int? {
            // Whole reps only: "185 for 8.5" re-asks instead of logging 9.
            guard v == v.rounded(), let r = Int(exactly: v), (1...100).contains(r) else { return nil }
            return r
        }

        switch core {
        case let c where c.count == 3 && c[1] == .separator:
            guard case .number(let w) = c[0], case .number(let r) = c[2] else {
                return weightWordForm(c, unit: unit, rpe: rpe, reps: reps)
            }
            guard unit == nil || unitAtEnd || unitAfterWeight,
                  w > 0, w <= 2000, let n = reps(r) else { return nil }
            return .logSet(weight: w, reps: n, rpe: rpe, unit: unit)
        case let c where c.count == 4 && c[0] == .same:
            return weightWordForm(Array(c.dropFirst()), unit: unit, rpe: rpe, reps: reps)
        case let c where c.count == 1:
            guard unit == nil, hadReps || context.isBodyweight,
                  case .number(let r) = c[0], let n = reps(r) else { return nil }
            return .logSet(weight: nil, reps: n, rpe: rpe, unit: nil)
        default:
            return nil
        }
    }

    /// `[same] weight SEP R` and the recognizer's "wait SEP R".
    static func weightWordForm(_ c: [Item], unit: VoiceUnit?, rpe: Double?,
                               reps: (Double) -> Int?) -> VoiceCommand? {
        guard unit == nil, c.count == 3, c[0] == .weightWord, c[1] == .separator,
              case .number(let r) = c[2], let n = reps(r) else { return nil }
        return .logSet(weight: nil, reps: n, rpe: rpe, unit: nil)
    }

    /// Token stream to grammar items. Number runs collapse to one value;
    /// unknown words drop. nil when a number run is malformed, or a word
    /// means time ("30 seconds", "more"), which must never log as reps.
    static func items(_ t: [String]) -> [Item]? {
        let roles = numberMask(t)
        var out: [Item] = []
        var i = 0
        while i < t.count {
            if roles[i] == .number {
                var j = i
                while j < t.count && roles[j] == .number { j += 1 }
                guard let v = runValue(Array(t[i..<j])) else { return nil }
                out.append(.number(v))
                i = j
                continue
            }
            if roles[i] == .separator { out.append(.separator); i += 1; continue }
            let w = t[i]
            if let u = units[w] {
                out.append(.unit(u))
            } else if w == "rep" || w == "reps" {
                out.append(.reps)
            } else if w == "rpe" || w == "rp" {
                out.append(.rpe)
            } else if w == "r", i + 2 < t.count, t[i + 1] == "p", t[i + 2] == "e" {
                out.append(.rpe)
                i += 3
                continue
            } else if w == "weight" || w == "wait" {
                out.append(.weightWord)
            } else if w == "same" {
                out.append(.same)
            } else if secondWords.contains(w) || minuteWords.contains(w) || w == "more" {
                return nil
            }
            i += 1
        }
        return out
    }
}
