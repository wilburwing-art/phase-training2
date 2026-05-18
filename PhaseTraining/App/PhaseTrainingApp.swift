import SwiftUI

@main
struct PhaseTrainingApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CoachConsent.storageKey) private var coachConsentGranted: Bool = false

    @StateObject private var session = SessionStore()
    @StateObject private var memory  = MemoryStore()
    @StateObject private var plan    = PlanStore()
    @StateObject private var custom  = CustomRoutineStore()
    @StateObject private var recentPicks = RecentPicksStore()
    @StateObject private var tabSelection = TabSelectionStore()
    @StateObject private var conv = CoachConversationStore()

    /// UI tests pass `--ui-test-onboarded` to skip the first-launch onboarding cover
    /// without persisting state to UserDefaults.
    private let uiTestSkipsOnboarding = ProcessInfo.processInfo.arguments.contains("--ui-test-onboarded")

    /// UI tests pass `--ui-test-reset` to start from a clean slate (wipes
    /// session + memory + plan + overrides UserDefaults keys on launch).
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset") {
            for key in ["pt_active_session", "pt_sessions",
                        "pt_training_memory",
                        "pt_week_plan", "pt_week_overrides",
                        "pt_weekly_reminder_enabled",
                        "pt_custom_routines",
                        "pt_recent_exercise_picks"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        WeeklyReminderScheduler.registerDelegate()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(session)
                .environmentObject(memory)
                .environmentObject(plan)
                .environmentObject(custom)
                .environmentObject(recentPicks)
                .environmentObject(tabSelection)
                .environmentObject(conv)
                .preferredColorScheme(.dark)
                .fullScreenCover(isPresented: .constant(!memory.isOnboarded && !uiTestSkipsOnboarding)) {
                    OnboardingFlow()
                        .environmentObject(memory)
                        .environmentObject(plan)
                        .preferredColorScheme(.dark)
                }
                .sheet(isPresented: $tabSelection.showWeeklyCheckIn) {
                    WeeklyCheckInFlow(onDismiss: { tabSelection.showWeeklyCheckIn = false })
                        .environmentObject(memory)
                        .environmentObject(plan)
                        .presentationBackground(Color.bg)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        InsightGenerator.runIfDue(
                            memoryStore: memory,
                            planStore: plan,
                            sessionStore: session,
                            consentGranted: coachConsentGranted
                        )
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "phasetraining" else { return }
                    switch url.host {
                    case "today":     tabSelection.selected = .today
                    case "week":      tabSelection.selected = .week
                    case "progress":  tabSelection.selected = .progress
                    case "profile":   tabSelection.selected = .profile
                    case "plan-week":
                        // Notification deep link: jump to Today and pop the
                        // interactive planning flow on top.
                        tabSelection.selected = .today
                        tabSelection.showWeeklyCheckIn = true
                    default: break
                    }
                }
        }
    }
}
