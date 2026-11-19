import UIKit

/// The lines spoken during a workout. Pure text, no state.
enum SpokenCue {
    static func restEnd(next: NextUp, in session: ActiveSession) -> String {
        let load = loadPhrase(weight: next.lastWeight, reps: next.targetReps)
        let tail = load.map { ", \($0)" } ?? ""
        if let rounds = supersetRounds(of: next, in: session) {
            let last = next.setNumber >= rounds
            let round = last ? "last round" : "round \(next.setNumber) of \(rounds)"
            return "Rest's up. Superset, \(round). \(next.exerciseName)\(tail)."
        }
        let position = next.setNumber == next.totalSets
            ? "last set"
            : "set \(next.setNumber) of \(next.totalSets)"
        return "Rest's up. \(next.exerciseName), \(position)\(tail)."
    }

    static func warning(next: NextUp, in session: ActiveSession) -> String {
        "10 seconds. \(next.exerciseName) next."
    }

    static func readback(exercise: LoggedExercise, setIdx: Int) -> String {
        guard exercise.sets.indices.contains(setIdx) else { return "\(exercise.name)." }
        let set = exercise.sets[setIdx]
        var line = "\(exercise.name), set \(setIdx + 1)"
        if let load = loadPhrase(weight: set.weight, reps: set.repsValue ?? 0) {
            line += ", \(load)"
        }
        return line + "."
    }

    private static func supersetRounds(of next: NextUp, in session: ActiveSession) -> Int? {
        guard session.exercises.indices.contains(next.exIdx),
              let id = session.exercises[next.exIdx].supersetGroup else { return nil }
        return session.exercises
            .filter { $0.supersetGroup == id }
            .map(\.sets.count)
            .max() ?? next.totalSets
    }

    /// "185 for 5", "5 reps", "185", or nil when there is nothing to say.
    private static func loadPhrase(weight: String?, reps: Int) -> String? {
        let value = weight.flatMap {
            LoggedSet(num: 1, weight: $0, reps: "", rpe: "", done: false).weightValue
        }.flatMap { $0 > 0 ? $0 : nil }
        switch (value, reps > 0) {
        case let (w?, true): return "\(format(w)) for \(reps)"
        case (nil, true): return "\(reps) reps"
        case let (w?, false): return format(w)
        case (nil, false): return nil
        }
    }

    private static func format(_ w: Double) -> String {
        if w == w.rounded() { return String(Int(w)) }
        var s = String(format: "%.1f", w)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}

/// Gate and speaker for the workout cues.
@MainActor
final class VoiceCuePlayer {
    static let shared = VoiceCuePlayer()

    private let makeOutput: () -> SpeechOutputting
    private var output: SpeechOutputting?
    private let defaults: UserDefaults
    private let voiceOverRunning: () -> Bool

    init(output: (() -> SpeechOutputting)? = nil,
         defaults: UserDefaults = .standard,
         voiceOverRunning: @escaping () -> Bool = { UIAccessibility.isVoiceOverRunning }) {
        self.makeOutput = output ?? { SpeechOutput() }
        self.defaults = defaults
        self.voiceOverRunning = voiceOverRunning
    }

    /// True when the rest-end line is spoken, so the banner chime stays quiet.
    nonisolated static func speaksRestEnd(settings: VoiceSettings, voiceOverRunning: Bool) -> Bool {
        settings.cuesOn && !voiceOverRunning
    }

    @discardableResult
    func restEnded(session: ActiveSession, next: NextUp?) -> Bool {
        guard let next else { return false }
        return speak(fullOnly: false) { SpokenCue.restEnd(next: next, in: session) }
    }

    @discardableResult
    func restWarning(session: ActiveSession, next: NextUp?) -> Bool {
        guard let next else { return false }
        return speak(fullOnly: true) { SpokenCue.warning(next: next, in: session) }
    }

    @discardableResult
    func readback(exercise: LoggedExercise, setIdx: Int) -> Bool {
        speak(fullOnly: true) { SpokenCue.readback(exercise: exercise, setIdx: setIdx) }
    }

    private func speak(fullOnly: Bool, line: () -> String) -> Bool {
        let settings = VoiceSettings.load(from: defaults)
        guard Self.speaksRestEnd(settings: settings, voiceOverRunning: voiceOverRunning()) else { return false }
        if fullOnly && settings.level != .full { return false }
        let out = output ?? makeOutput()
        output = out
        (out as? SpeechOutput)?.voiceIdentifier = settings.voiceId
        out.speak(line())
        return true
    }
}
