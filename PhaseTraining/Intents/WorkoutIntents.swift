import AppIntents

/// Siri and Shortcuts commands on the running workout. Each acts on
/// `ActiveWorkoutRegistry.shared.resolve()` without opening the app.

struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a set"
    static var description = IntentDescription("Logs the next set of the running workout.")
    static var openAppWhenRun = false

    @Parameter(title: "Reps", requestValueDialog: IntentDialog("How many reps?"))
    var reps: Int

    @Parameter(title: "Weight")
    var weight: Double?

    init() {}

    init(reps: Int, weight: Double? = nil) {
        self.reps = reps
        self.weight = weight
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = WorkoutIntentActions.logSet(weight: weight, reps: reps,
                                               in: ActiveWorkoutRegistry.shared.resolve())
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

struct SkipRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description = IntentDescription("Ends the running rest timer.")
    static var openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = WorkoutIntentActions.skipRest(in: ActiveWorkoutRegistry.shared.resolve())
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

struct AddRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Add rest"
    static var description = IntentDescription("Adds time to the running rest timer.")
    static var openAppWhenRun = false

    @Parameter(title: "Seconds", default: 15)
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = WorkoutIntentActions.addRest(seconds: seconds,
                                                in: ActiveWorkoutRegistry.shared.resolve())
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

struct WhatsNextIntent: AppIntent {
    static var title: LocalizedStringResource = "What's next"
    static var description = IntentDescription("Says the next set of the running workout.")
    static var openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = WorkoutIntentActions.whatsNext(in: ActiveWorkoutRegistry.shared.resolve())
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}
