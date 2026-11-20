import AppIntents
import Combine
import Foundation

/// "Talk to coach" from Siri or Shortcuts (voice 3.4). Opens the app and the
/// voice check-in screen. Listed and discoverable only in `COACH_PHRASE`
/// builds (see `PhaseShortcuts.listsTalkToCoach`).
struct TalkToCoachIntent: AppIntent {
    static var title: LocalizedStringResource = "Talk to coach"
    static var description = IntentDescription("Opens a spoken check-in with the coach.")
    static var openAppWhenRun = true
    #if COACH_PHRASE
    static var isDiscoverable = true
    #else
    static var isDiscoverable = false
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = VoiceCheckInLaunch.shared.request()
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

/// Hands an intent's request to the tab shell, which owns the
/// `CoachConversationStore` that presents the screen. The flag stays up until
/// the shell takes it, so a cold launch from Siri still opens the screen.
@MainActor
final class VoiceCheckInLaunch: ObservableObject {
    static let shared = VoiceCheckInLaunch()

    @Published private(set) var pending = false

    static let openingLine = "Opening your coach check-in."
    static let offLine = "The coach is off. Turn it on in Profile."

    /// Raises the flag when the coach can answer, and returns what Siri says.
    func request(defaults: UserDefaults = .standard,
                 available: Bool = CoachEntitlement.coachAvailable) -> String {
        let offered = VoiceCheckInModel.isOffered(
            consent: defaults.bool(forKey: CoachConsent.storageKey),
            pro: CoachEntitlement.proSatisfied(defaults: defaults),
            available: available)
        guard offered else { return Self.offLine }
        pending = true
        return Self.openingLine
    }

    /// The shell calls this when it presents the screen.
    func consume() -> Bool {
        guard pending else { return false }
        pending = false
        return true
    }
}
