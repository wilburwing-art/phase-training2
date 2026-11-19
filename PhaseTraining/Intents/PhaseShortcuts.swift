import AppIntents

// 11c 7.1 adds its shortcuts here; an app may have only one AppShortcutsProvider.
struct PhaseShortcuts: AppShortcutsProvider {
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
    }
}
