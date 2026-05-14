import SwiftUI

@main
struct PhaseTrainingApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var memory  = MemoryStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(session)
                .environmentObject(memory)
                .preferredColorScheme(.dark)
                .fullScreenCover(isPresented: .constant(!memory.isOnboarded)) {
                    OnboardingFlow()
                        .environmentObject(memory)
                        .preferredColorScheme(.dark)
                }
        }
    }
}
