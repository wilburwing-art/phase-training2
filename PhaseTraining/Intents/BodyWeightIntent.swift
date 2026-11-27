import AppIntents
import Foundation

/// "Log body weight" from Siri or Shortcuts (11c 7.1). Records today's weight
/// in the user's display unit without opening the app.
struct LogBodyWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log body weight"
    static var description = IntentDescription("Records today's body weight.")
    static var openAppWhenRun = false

    @Parameter(title: "Weight", requestValueDialog: IntentDialog("What do you weigh?"))
    var weight: Double

    init() {}

    init(weight: Double) {
        self.weight = weight
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = BodyWeightIntentActions.log(weight: weight, in: BodyWeightIntentActions.store)
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

/// What the body-weight intent does to memory, and the line Siri says back.
@MainActor
enum BodyWeightIntentActions {
    /// The app's live `MemoryStore`. Set in `PhaseTrainingApp.init`, before any
    /// view. A direct UserDefaults write would be lost to the app's next save
    /// of its in-memory copy, so the intent writes through this instance.
    static var store: MemoryStore?

    static let noStoreLine = "Open Phase once, then try again."
    static let notOnboardedLine = "Finish setup in Phase first."
    static let invalidWeightLine = "Weight must be more than zero."

    /// Takes `weight` in lb for an imperial user, kg otherwise. A second log on
    /// the same day replaces the first (`recordBodyWeight`).
    static func log(weight: Double, in store: MemoryStore?, now: Date = Date()) -> String {
        guard let store else { return noStoreLine }
        guard store.isOnboarded else { return notOnboardedLine }
        guard weight.isFinite, weight > 0 else { return invalidWeightLine }
        let imperial = store.memory.usesImperial
        let kg = imperial ? BodyMetrics.lbToKg(weight) : weight
        store.update { $0.recordBodyWeight(kg, on: now) }
        return "Logged " + BodyMetrics.formatWeight(kg: kg, imperial: imperial)
    }
}
