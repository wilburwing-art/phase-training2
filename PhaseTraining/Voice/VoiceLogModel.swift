import Combine
import Foundation

/// The set a voice change landed on.
struct SetTarget: Equatable {
    let exIdx: Int
    let setIdx: Int
}

/// What the log screen shows after a spoken command.
struct HeardCard: Equatable {
    enum Kind: Equatable { case applied, info, unparsed }
    let kind: Kind
    /// The transcript, shown in quotes ("" when nothing was heard).
    let heard: String
    let message: String
    /// Applied set changes only.
    let target: SetTarget?
    let undoable: Bool
    let shownAt: Date
}

/// Push-to-talk on the log screen: runs `SpeechInput`, parses the transcript
/// with `VoiceCommand`, applies it through `ActiveWorkoutController`, and keeps
/// one level of undo for the last voice set change.
@MainActor
final class VoiceLogModel: ObservableObject {
    static let cardSeconds: TimeInterval = 5
    static let cannedTranscriptPrefix = "--ui-test-voice-transcript="

    @Published private(set) var card: HeardCard?
    @Published private(set) var inputState: SpeechInput.State = .idle

    private struct UndoEntry {
        let exerciseID: String
        let setNum: Int
        let before: LoggedSet
        let after: LoggedSet
        /// True when the change started the rest now anchored to this set.
        let startedRest: Bool
    }

    private let workout: ActiveWorkoutController
    private var input: SpeechInput?
    private let readback: @MainActor (LoggedExercise, Int) -> Void
    /// The cue speaker; `SpeechInput` stops it before the mic opens.
    private let cueOutput: @MainActor () -> SpeechOutputting
    private let makeInput: @MainActor (SpeechOutputting) async -> SpeechInput
    private let now: () -> Date
    private var undoEntry: UndoEntry?
    private var stateSink: AnyCancellable?

    init(workout: ActiveWorkoutController,
         input: SpeechInput?,
         readback: @escaping @MainActor (LoggedExercise, Int) -> Void = { VoiceCuePlayer.shared.readback(exercise: $0, setIdx: $1) },
         cueOutput: @escaping @MainActor () -> SpeechOutputting = { VoiceCuePlayer.shared.speechOutput },
         makeInput: @escaping @MainActor (SpeechOutputting) async -> SpeechInput = { await SpeechInput.makeDefault(output: $0) },
         now: @escaping () -> Date = Date.init) {
        self.workout = workout
        self.readback = readback
        self.cueOutput = cueOutput
        self.makeInput = makeInput
        self.now = now
        if let input { attach(input) }
    }

    private func attach(_ input: SpeechInput) {
        self.input = input
        inputState = input.state
        stateSink = input.$state.sink { [weak self] in self?.inputState = $0 }
    }

    // MARK: - Mic

    func prepare() async {
        guard input == nil else { return }
        if let text = Self.cannedTranscript() {
            attach(SpeechInput(transcriber: CannedTranscriber(transcript: text), permissions: GrantedPermissions()))
        } else {
            attach(await makeInput(cueOutput()))
        }
    }

    func pressDown() async {
        if input == nil { await prepare() }
        guard let input else { return }
        await input.pressDown(exerciseNames: workout.session.exercises.map(\.name))
        if case .unavailable(let reason) = input.state {
            show(.info, heard: "", message: reason.message)
        }
    }

    func release() async {
        guard let input, case .listening = input.state else { return }
        handle(await input.release())
    }

    func cancel() {
        input?.cancel()
    }

    // MARK: - Card

    func cardIsLive(at date: Date) -> Bool {
        guard let card else { return false }
        return date.timeIntervalSince(card.shownAt) < Self.cardSeconds
    }

    func dismissCard(shownAt: Date) {
        if card?.shownAt == shownAt { card = nil }
    }

    private func show(_ kind: HeardCard.Kind, heard: String, message: String,
                      target: SetTarget? = nil, undoable: Bool = false) {
        card = HeardCard(kind: kind, heard: heard, message: message,
                         target: target, undoable: undoable, shownAt: now())
    }

    // MARK: - Commands

    func handle(_ transcript: String?) {
        let heard = transcript ?? ""
        let next = workout.nextUp()
        let isBodyweight = next.map { workout.session.exercises[$0.exIdx].isBodyweight } ?? false
        guard let transcript,
              let command = VoiceCommand.parse(transcript, context: VoiceContext(isBodyweight: isBodyweight)) else {
            show(.unparsed, heard: heard, message: "Didn't catch that")
            return
        }

        switch command {
        case .skipRest:
            if restRunning {
                workout.skipRest()
                show(.info, heard: heard, message: "Rest skipped")
            } else {
                show(.info, heard: heard, message: "No rest running")
            }
        case .addRest(let seconds):
            if restRunning {
                workout.addRest(seconds: seconds)
                show(.info, heard: heard, message: "\(seconds < 0 ? "-" : "+")\(abs(seconds)) s rest")
            } else {
                show(.info, heard: heard, message: "No rest running")
            }
        case .undo:
            performUndo(heard: heard)
        case .whatsNext:
            if let next {
                show(.info, heard: heard, message: SpokenCue.upNext(next: next, in: workout.session))
            } else {
                show(.info, heard: heard, message: Self.allLogged)
            }
        case .setsLeft:
            let left = workout.session.exercises.reduce(0) { $0 + $1.sets.filter { !$0.done }.count }
            show(.info, heard: heard,
                 message: left == 0 ? Self.allLogged : "\(left) \(left == 1 ? "set" : "sets") left")
        case .logSet(let weight, let reps, let rpe, let unit):
            guard let next else { show(.info, heard: heard, message: Self.allLogged); return }
            let exercise = workout.session.exercises[next.exIdx]
            if let unit, !exercise.isBodyweight, let mismatch = Self.unitMismatch(spoken: unit, exercise: exercise) {
                show(.unparsed, heard: heard, message: mismatch)
                return
            }
            applySet(next, heard: heard,
                     weight: weight.map(SpokenCue.format), reps: String(reps), rpe: rpe.map(SpokenCue.format))
        case .sameAgain:
            guard let next else { show(.info, heard: heard, message: Self.allLogged); return }
            guard let previous = workout.session.exercises[next.exIdx].sets.last(where: { $0.done }) else {
                show(.info, heard: heard, message: "Nothing to repeat yet")
                return
            }
            applySet(next, heard: heard, weight: previous.weight, reps: previous.reps, rpe: nil)
        case .completeSet:
            guard let next else { show(.info, heard: heard, message: Self.allLogged); return }
            applySet(next, heard: heard, weight: nil, reps: nil, rpe: nil)
        }
    }

    func undo() {
        performUndo(heard: "")
    }

    private static let allLogged = WorkoutIntentActions.allLogged

    private var restRunning: Bool {
        workout.rest.remaining(at: now()) != nil
    }

    /// nil when the spoken unit matches the exercise's. No conversion is done.
    private static func unitMismatch(spoken: VoiceUnit, exercise: LoggedExercise) -> String? {
        let logsKg = exercise.unit == "kg"
        switch spoken {
        case .kg where !logsKg: return "Heard kg. \(exercise.name) logs in lb"
        case .lb where logsKg: return "Heard lb. \(exercise.name) logs in kg"
        default: return nil
        }
    }

    private func applySet(_ next: NextUp, heard: String, weight: String?, reps: String?, rpe: String?) {
        let exIdx = next.exIdx
        let setIdx = next.setIdx
        let before = workout.session.exercises[exIdx].sets[setIdx]
        let restBefore = workout.rest

        workout.logSet(exIdx: exIdx, setIdx: setIdx, weight: weight, reps: reps, rpe: rpe)

        let exercise = workout.session.exercises[exIdx]
        let after = exercise.sets[setIdx]
        let startedRest = workout.rest != restBefore
            && workout.rest.exIdx == exIdx && workout.rest.setIdx == setIdx
        undoEntry = UndoEntry(exerciseID: exercise.id, setNum: after.num,
                              before: before, after: after, startedRest: startedRest)

        show(.applied, heard: heard, message: Self.appliedMessage(exercise: exercise, setIdx: setIdx),
             target: SetTarget(exIdx: exIdx, setIdx: setIdx), undoable: true)
        readback(exercise, setIdx)
    }

    private static func appliedMessage(exercise: LoggedExercise, setIdx: Int) -> String {
        let set = exercise.sets[setIdx]
        let head = "\(exercise.name), set \(setIdx + 1)"
        let reps = set.reps.trimmingCharacters(in: .whitespaces)
        let weight = set.weight.trimmingCharacters(in: .whitespaces)
        if reps.isEmpty { return "\(head) done" }
        if exercise.isBodyweight || weight.isEmpty { return "\(head): \(reps) reps" }
        return "\(head): \(weight) × \(reps)"
    }

    // MARK: - Undo

    private func performUndo(heard: String) {
        guard let entry = undoEntry,
              let exIdx = workout.session.exercises.firstIndex(where: { $0.id == entry.exerciseID }),
              let setIdx = workout.session.exercises[exIdx].sets.firstIndex(where: { $0.num == entry.setNum }),
              workout.session.exercises[exIdx].sets[setIdx] == entry.after else {
            show(.info, heard: heard, message: "Nothing to undo")
            return
        }
        let name = workout.session.exercises[exIdx].name
        var updated = workout.session
        updated.exercises[exIdx].sets[setIdx] = entry.before
        workout.session = updated
        if entry.startedRest, workout.rest.exIdx == exIdx, workout.rest.setIdx == setIdx {
            workout.skipRest()
        }
        undoEntry = nil
        show(.info, heard: heard, message: "Undid \(name), set \(entry.setNum)")
    }

    // MARK: - UI-test launch flag

    private static func cannedTranscript() -> String? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix(cannedTranscriptPrefix) }
            .map { String($0.dropFirst(cannedTranscriptPrefix.count)) }
    }
}

/// Stands in for the recognizer under `--ui-test-voice-transcript=<text>`.
@MainActor
private final class CannedTranscriber: SpeechTranscribing {
    let supportsOnDevice = true
    private let transcript: String

    init(transcript: String) { self.transcript = transcript }

    func start(contextualStrings: [String], onPartial: @escaping (String) -> Void) throws {}
    func finish() async throws -> String? { transcript }
    func cancel() {}
}

@MainActor
private final class GrantedPermissions: SpeechPermissionProviding {
    let microphone: SpeechAuthorization = .granted
    let speech: SpeechAuthorization = .granted
    func requestMicrophone() async -> SpeechAuthorization { .granted }
    func requestSpeech() async -> SpeechAuthorization { .granted }
}
