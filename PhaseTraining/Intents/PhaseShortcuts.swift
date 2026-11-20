import AppIntents

// 11c 7.1 adds its shortcuts here; an app may have only one AppShortcutsProvider.
struct PhaseShortcuts: AppShortcutsProvider {
    /// "Talk to coach" is listed only in builds compiled with `COACH_PHRASE`.
    /// Project.yml sets it for Debug; release.yml sets it on the archive only
    /// when `PHASETRAINING_BETA` is not 1, the same input that blanks the
    /// gateway token. `AppShortcutsBuilder` rejects a runtime `if`, so the
    /// gate is compile time (voice backlog Phase 0, decision A).
    #if COACH_PHRASE
    static let listsTalkToCoach = true
    #else
    static let listsTalkToCoach = false
    #endif

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSetIntent(),
            phrases: [
                "Log a set in \(.applicationName)",
                "Log set in \(.applicationName)",
            ],
            shortTitle: "Log a set",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: SkipRestIntent(),
            phrases: [
                "Skip rest in \(.applicationName)",
                "Skip my rest in \(.applicationName)",
            ],
            shortTitle: "Skip rest",
            systemImageName: "forward.end"
        )
        AppShortcut(
            intent: AddRestIntent(),
            phrases: [
                "Add rest in \(.applicationName)",
                "More rest in \(.applicationName)",
            ],
            shortTitle: "Add rest",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "What's my next set in \(.applicationName)",
            ],
            shortTitle: "What's next",
            systemImageName: "list.bullet"
        )
        #if COACH_PHRASE
        AppShortcut(
            intent: TalkToCoachIntent(),
            phrases: [
                "Talk to coach in \(.applicationName)",
                "Talk to my coach in \(.applicationName)",
            ],
            shortTitle: "Talk to coach",
            systemImageName: "waveform"
        )
        #endif
    }
}
