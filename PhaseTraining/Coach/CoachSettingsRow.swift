// CoachSettingsRow.swift — Profile tab section for the AI Coach.
//
// Off by default. Toggling on triggers the consent modal (CoachConsent). In
// DEBUG builds, once consent is granted, a "Test ping" button does a round-
// trip to the gateway and prints the result — proves 13a end-to-end before
// any chat UI exists.

import SwiftUI

struct CoachSettingsRow: View {
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false
    @AppStorage(CoachEntitlement.proKey) private var proEntitled: Bool = false

    /// True between the toggle flick and the alert's Accept tap. Lets us
    /// revert if the user cancels.
    @State private var modalPresented: Bool = false
    @State private var paywallPresented: Bool = false
    @State private var pendingPing: Bool = false
    @State private var pingResultText: String? = nil
    @State private var pingErrorText: String? = nil

    private let client = CoachClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            Toggle(isOn: toggleBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Coach")
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            .tint(Color.accent)

            if Self.showsLapsedNotice(consent: consentGranted, pro: proEntitled) {
                proLapsedNotice
            }

            #if DEBUG
            if consentGranted {
                testPingBlock
            }
            #endif
        }
        .modifier(CoachConsentModal(presented: $modalPresented, consentGranted: $consentGranted))
        .sheet(isPresented: $paywallPresented) {
            PaywallView()
        }
    }

    /// The live Pro check (reactive via @AppStorage; always true while
    /// CoachEntitlement.proRequired is false — coach ships free).
    private var proSatisfied: Bool {
        proEntitled || !CoachEntitlement.proRequired
    }

    /// Pure form of the lapsed-notice condition (consent on, gate closed,
    /// no subscription) so tests can exercise it with requirePro pinned
    /// rather than flipping the shipped global.
    static func showsLapsedNotice(consent: Bool, pro: Bool,
                                  requirePro: Bool = CoachEntitlement.proRequired) -> Bool {
        consent && !(pro || !requirePro)
    }

    private var subtitle: String {
        if consentGranted {
            return "On — chat reaches Claude via our proxy"
        }
        return proSatisfied ? "Off — nothing leaves your phone"
                            : "Off — requires Pro"
    }

    /// Consent is on but the subscription isn't — coach surfaces are dark
    /// until the user (re)subscribes.
    private var proLapsedNotice: some View {
        Button { paywallPresented = true } label: {
            Text("Pro required. The coach is paused until you subscribe.")
                .font(.monoXS)
                .foregroundStyle(Color.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        Text("AI COACH")
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }

    // MARK: - Toggle binding

    /// Intercept changes: flipping to true routes through the Pro gate, then
    /// the consent modal. Flipping to false (revoking) is immediate.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { consentGranted },
            set: { newValue in
                if newValue {
                    if proSatisfied {
                        // Don't commit consent yet — show the modal.
                        modalPresented = true
                    } else {
                        paywallPresented = true
                    }
                } else {
                    consentGranted = false
                }
            }
        )
    }

    // MARK: - Test ping (DEBUG only)

    #if DEBUG
    private var testPingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: ping) {
                HStack(spacing: 6) {
                    if pendingPing {
                        ProgressView().tint(Color.accentInk).scaleEffect(0.7)
                    } else {
                        Image(systemName: "bolt.circle")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(pendingPing ? "Pinging…" : "Test ping")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 13))
                }
                .foregroundStyle(Color.accentInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(pendingPing)

            if let result = pingResultText {
                Text(result)
                    .font(.monoXS)
                    .foregroundStyle(Color.ok)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = pingErrorText {
                Text(error)
                    .font(.monoXS)
                    .foregroundStyle(Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ping() {
        pendingPing = true
        pingResultText = nil
        pingErrorText = nil
        Task {
            do {
                let result = try await client.send(
                    userMessage: "Say 'ok' in 3 words.",
                    system: "You are a debug ping. Reply briefly."
                )
                await MainActor.run {
                    pingResultText = "OK · \(result.model) · \(result.latencyMs)ms · in:\(result.inputTokens) out:\(result.outputTokens) · \"\(result.text.trimmingCharacters(in: .whitespacesAndNewlines))\""
                    pendingPing = false
                }
            } catch {
                await MainActor.run {
                    pingErrorText = "FAIL · \(error.localizedDescription)"
                    pendingPing = false
                }
            }
        }
    }
    #endif
}

#Preview {
    CoachSettingsRow()
        .padding()
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
