// OnboardingHealthScreen.swift — Apple Health read access, asked at onboarding.
//
// Until 2026-09-18 the only place the app requested Health access was the
// Sync button under Profile > Health & Imports, so a new install never saw
// Apple's sheet and readiness, activity detection and body metrics ran on
// nothing. This step asks once, up front, the way Fitbod does. Same shape as
// the coach consent step: neither row is pre-selected and Continue is gated
// on a pick. Connect raises Apple's sheet and, when it returns, pulls the
// last 28 days of workouts so Health & Imports already reads "N workouts
// imported". Not now advances with no sheet; that screen's Sync button is
// the way back in. Apple's own authorisation status is the record; no flag
// of ours is stored.

import SwiftUI

struct OnboardingHealthScreen: View {
    let onNext: () -> Void
    let onBack: () -> Void

    /// nil = no choice yet, which gates Continue.
    @State private var connect: Bool?
    @State private var connecting = false
    private let importer = HealthKitImporter()

    var body: some View {
        OnboardingScaffold(
            step: .health,
            title: "Read your workouts from Health?",
            subtitle: "Recent workouts tell the plan how active you've been, and skis, climbs and hikes it finds can be logged in a tap. Read-only: nothing is written to Health.",
            nextLabel: connecting ? "Connecting" : "Continue",
            nextEnabled: connect != nil && !connecting,
            onNext: continueTapped,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingPickRow(
                    title: "Connect Apple Health",
                    subtitle: "Apple will ask which data to share. Workouts is all this needs.",
                    selected: connect == true,
                    leading: "heart.text.square",
                    action: { connect = true },
                    a11yId: "onboarding-health-on"
                )
                OnboardingPickRow(
                    title: "Not now",
                    subtitle: "You can connect later in Profile → Health & Imports.",
                    selected: connect == false,
                    leading: "lock.fill",
                    action: { connect = false },
                    a11yId: "onboarding-health-off"
                )
            }
        }
    }

    private func continueTapped() {
        guard connect == true else { onNext(); return }
        connecting = true
        Task { @MainActor in
            // The sheet is Apple's; whether they allowed is not exposed, so
            // the fetch that follows is the only observation (an empty result
            // is "no workouts or denied", and Health & Imports says so).
            _ = try? await importer.requestAuthorization()
            let imported = (try? await importer.recentWorkouts(days: 28)) ?? []
            UserDatabase.shared.insertImportedWorkouts(imported)
            connecting = false
            onNext()
        }
    }
}

#Preview {
    OnboardingHealthScreen(onNext: {}, onBack: {})
        .preferredColorScheme(.dark)
}
