import SwiftUI

@main
struct PhaseTrainingApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var memory  = MemoryStore()
    @StateObject private var plan    = PlanStore()

    /// UI tests pass `--ui-test-onboarded` to skip the first-launch onboarding cover
    /// without persisting state to UserDefaults.
    private let uiTestSkipsOnboarding = ProcessInfo.processInfo.arguments.contains("--ui-test-onboarded")

    /// UI tests pass `--ui-test-reset` to start from a clean slate (wipes
    /// session + memory + plan + overrides UserDefaults keys on launch).
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset") {
            for key in ["pt_active_session", "pt_sessions",
                        "pt_training_memory",
                        "pt_week_plan", "pt_week_overrides"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(session)
                .environmentObject(memory)
                .environmentObject(plan)
                .preferredColorScheme(.dark)
                .fullScreenCover(isPresented: .constant(!memory.isOnboarded && !uiTestSkipsOnboarding)) {
                    OnboardingFlow()
                        .environmentObject(memory)
                        .environmentObject(plan)
                        .preferredColorScheme(.dark)
                }
        }
    }
}
