import SwiftUI

@main
struct PhaseTrainingApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
