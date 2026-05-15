import SwiftUI

@main
struct PhaseTrainingApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var memory  = MemoryStore()
    @StateObject private var plan    = PlanStore()

    /// UI tests pass `--ui-test-onboarded` to skip the first-launch onboarding cover
    /// without persisting state to UserDefaults.
    private let uiTestSkipsOnboarding = ProcessInfo.processInfo.arguments.contains("--ui-test-onboarded")

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
