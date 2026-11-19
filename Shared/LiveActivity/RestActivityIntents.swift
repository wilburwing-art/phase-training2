// RestActivityIntents.swift: the Skip and +15 buttons on the rest-timer Live
// Activity.
//
// Compiled into the app and the widget extension: the widget needs the types
// to build `Button(intent:)`, and the system runs a `LiveActivityIntent`'s
// `perform` in the app's process. The app sets `RestActivityButtonHandler.handle`
// at launch; it stays nil in the widget extension, which never runs `perform`.

#if os(iOS) && canImport(ActivityKit)
import AppIntents

/// What a Live Activity button asks the app to do.
enum RestActivityButton: Equatable {
    case skip
    case add(seconds: Int)
}

@MainActor
enum RestActivityButtonHandler {
    static var handle: ((RestActivityButton) -> Void)?
}

struct SkipRestActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"
    // Siri and Shortcuts use `SkipRestIntent`; this one exists for the button.
    static var isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RestActivityButtonHandler.handle?(.skip)
        return .result()
    }
}

struct AddRestActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add rest"
    static var isDiscoverable = false

    @Parameter(title: "Seconds")
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        RestActivityButtonHandler.handle?(.add(seconds: seconds))
        return .result()
    }
}
#endif
