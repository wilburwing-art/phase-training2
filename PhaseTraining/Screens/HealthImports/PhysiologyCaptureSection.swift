// PhysiologyCaptureSection.swift — recovery data section of Health &
// Imports (1c capture slice, build 145).
//
// The "Capture recovery data" tap is the only place the HRV / resting heart
// rate / sleep permission sheet can appear. It is its own grant, separate
// from workouts and body metrics, and skipping it changes nothing else in
// the app. Once on, PhaseTrainingApp refreshes silently on foreground.

import SwiftUI

struct PhysiologyCaptureSection: View {
    @State private var enabled = PhysiologyStore().isEnabled
    @State private var summary = PhysiologyCaptureSummary.make(PhysiologyStore().loadNights())
    @State private var working = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECOVERY DATA")
                .font(.caption.bold())
                .foregroundColor(.ink2)
            Text(enabled ? statusLine
                 : "Optionally keep nightly heart rate variability, resting heart rate and sleep from Health on this phone, so future builds can learn how recovery relates to your training.")
                .font(.caption)
                .foregroundColor(.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                Button("Stop and delete recovery data", role: .destructive, action: stopTapped)
                    .font(.caption)
                    .accessibilityIdentifier("health-physiology-stop")
            } else {
                Button(action: connectTapped) {
                    HStack {
                        if working {
                            ProgressView().tint(.ink)
                        } else {
                            Image(systemName: "bed.double")
                        }
                        Text(working ? "Reading…" : "Capture recovery data")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .foregroundColor(.ink)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.lineSoft, lineWidth: 1)
                    )
                }
                .disabled(working)
                .accessibilityIdentifier("health-physiology-connect")
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Stays on this phone. Not sent to the AI Coach. Separate permission from workouts.")
                .font(.caption)
                .foregroundColor(.ink3)
        }
    }

    private var statusLine: String {
        guard summary.nights > 0 else {
            return "On. No nights yet. If you expected some, check Settings → Health → Data Access & Devices → Phase Training."
        }
        return "On. \(summary.nights) night\(summary.nights == 1 ? "" : "s") kept: \(summary.daysWithHRV) with HRV, \(summary.daysWithRestingHR) with resting heart rate, \(summary.daysWithSleep) with sleep."
    }

    private func connectTapped() {
        working = true
        note = nil
        Task { @MainActor in
            defer { working = false }
            switch await PhysiologyCapture.connect() {
            case .connected:
                enabled = true
            case .unavailable:
                note = "Health isn't available on this device."
            case .failed(let message):
                note = message
            }
            summary = PhysiologyCaptureSummary.make(PhysiologyStore().loadNights())
        }
    }

    private func stopTapped() {
        PhysiologyStore().stopAndDelete()
        enabled = false
        summary = PhysiologyCaptureSummary.make([])
        note = "Stopped and deleted. To also remove the permission, use Settings → Health → Data Access & Devices."
    }
}
