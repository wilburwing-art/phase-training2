// RecoveryPrePromptRow.swift — one-time offer on Progress to start recovery
// capture (HRV, resting heart rate, sleep). Either button marks it answered.
// Connect shares PhysiologyCapture.connect() with the Health & Imports section.

import SwiftUI

struct RecoveryPrePromptRow: View {
    @State private var visible = RecoveryCapturePrePrompt.shouldOffer(
        captureEnabled: PhysiologyStore().isEnabled)
    @State private var working = false
    @State private var note: String?

    var body: some View {
        if visible {
            VStack(alignment: .leading, spacing: 10) {
                Text("Capture recovery data")
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Text("Keep nightly heart rate variability, resting heart rate and sleep from Health. It stays on this phone and is a separate permission from workouts.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .font(.monoXS)
                        .foregroundStyle(Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button(action: turnOn) {
                        Text(working ? "Reading" : "Turn on")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentInk)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.accent))
                    }
                    .disabled(working)
                    .accessibilityIdentifier("progress-recovery-preprompt-on")
                    Button(action: dismiss) {
                        Text("Not now")
                            .foregroundStyle(Color.ink2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    .disabled(working)
                    .accessibilityIdentifier("progress-recovery-preprompt-off")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        }
    }

    private func dismiss() {
        RecoveryCapturePrePrompt.markAnswered()
        visible = false
    }

    private func turnOn() {
        working = true
        note = nil
        Task { @MainActor in
            defer { working = false }
            switch await PhysiologyCapture.connect() {
            case .connected:
                dismiss()
            case .unavailable:
                note = "Health isn't available on this device."
                RecoveryCapturePrePrompt.markAnswered()
            case .failed(let message):
                note = message
                RecoveryCapturePrePrompt.markAnswered()
            }
        }
    }
}
