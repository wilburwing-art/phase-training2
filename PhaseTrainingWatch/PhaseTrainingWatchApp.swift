// PhaseTrainingWatchApp.swift — the watch companion (PLAN-watch.md).
//
// Step 0 of the plan: an empty target that builds in CI, so the project
// generation, embedding and signing questions get answered before any
// logging code exists. Everything the watch will do (mirror today's session,
// mark sets, run the rest timer, save the workout to Health, record labeled
// motion) lands in steps 1 to 3.

import SwiftUI

@main
struct PhaseTrainingWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Phase Training")
                .font(.headline)
            Text("Open today's session on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
