// RestTimer.swift — Rest-period overlay component for LogScreen.
//
// Presentation-only: parent owns the countdown via TimelineView and passes
// `remaining` (seconds) plus +15 / skip / set-duration callbacks. Mirrors the
// inline rest card in `handoff/proto/log.jsx:188-206` and
// `handoff/hd-training-log.jsx:59-80`.
//
// Visuals (from handoff/README.md:290-296):
//   - 12pt corner radius, accentWash background, 0.5pt accentBorder border
//   - Pulse dot (7pt, accent) with opacity 1 → 0.35 → 1 over 1.6s ease-in-out
//   - "REST" micro label (accent)
//   - Mono L remaining-time readout (M:SS, accent) — tap to pick a new duration
//   - "+15" and "Skip" pill chips
//
// Feature: tap the time readout to surface a confirmationDialog with
// duration presets + "Custom…". (Previously a SwiftUI Menu — switched
// because SwiftUI Menu's items are unreliable in iOS 26 XCUITest:
// .accessibilityIdentifier doesn't propagate to menu items and the
// item element type varies across hierarchy contexts. confirmationDialog
// renders as UIAlertController which has stable, well-known XCUI
// accessibility.) `expired` flips the band to a brief alert state when
// the parent fires the timeout (sound + haptic happen in LogScreen).

import SwiftUI

struct RestTimer: View {
    let remaining: Int
    /// When true, the parent has hit zero and is briefly flashing the card.
    /// LogScreen drives this from a state flag it clears ~1.2s after expiry.
    var expired: Bool = false
    let onAdd15: () -> Void
    let onSkip: () -> Void
    /// Set an arbitrary new duration (seconds). Parent typically resets the
    /// countdown start time so the new value runs from "now" instead of
    /// retroactively shortening/extending the existing window.
    var onSetDuration: ((Int) -> Void)? = nil

    @State private var pulse = false
    @State private var showPresetDialog = false
    @State private var showCustomSheet = false
    @State private var customText: String = ""

    /// Duration presets surfaced in the tap-on-time menu. Mirrors the most
    /// common lifter rest windows; "Custom…" hands off to a numeric prompt.
    private static let presets: [(label: String, seconds: Int)] = [
        ("30s", 30),
        ("60s", 60),
        ("90s", 90),
        ("2m", 120),
        ("3m", 180),
        ("5m", 300),
    ]

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(expired ? Color.ok : Color.accent)
                .frame(width: 7, height: 7)
                .opacity(pulse ? 0.35 : 1.0)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }

            Text(expired ? "DONE" : "REST")
                .styled(.micro)
                .foregroundStyle(expired ? Color.ok : Color.accent)
                .textCase(.uppercase)

            timeReadout

            Spacer(minLength: 4)

            chip("+15", action: onAdd15)
                .accessibilityIdentifier("log-rest-add15")
            chip("Skip", action: onSkip)
                .accessibilityIdentifier("log-rest-skip")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(expired ? Color.ok.opacity(0.18) : Color.accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(expired ? Color.ok : Color.accentBorder, lineWidth: expired ? 1.0 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: expired)
        .alert("Custom rest", isPresented: $showCustomSheet) {
            TextField("Seconds", text: $customText)
                .keyboardType(.numberPad)
            Button("Set") {
                if let v = Int(customText), v > 0 { onSetDuration?(v) }
                customText = ""
            }
            Button("Cancel", role: .cancel) { customText = "" }
        } message: {
            Text("Enter rest duration in seconds.")
        }
    }

    /// Mono time text. When `onSetDuration` is wired, tap surfaces a
    /// confirmationDialog with preset + Custom options. Otherwise render
    /// plain text. The dialog (UIAlertController under the hood) has
    /// reliable iOS 26 XCUITest accessibility; SwiftUI Menu didn't.
    @ViewBuilder
    private var timeReadout: some View {
        if let onSetDuration {
            Button {
                showPresetDialog = true
            } label: {
                Text(Self.formatTime(remaining))
                    .styled(.monoL)
                    .foregroundStyle(expired ? Color.ok : Color.accent)
                    .monospacedDigit()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("log-rest-time")
            .confirmationDialog(
                "Set rest duration",
                isPresented: $showPresetDialog,
                titleVisibility: .visible
            ) {
                ForEach(Self.presets, id: \.seconds) { preset in
                    Button(preset.label) { onSetDuration(preset.seconds) }
                        .accessibilityIdentifier("log-rest-preset-\(preset.seconds)")
                }
                Button("Custom…") {
                    customText = String(remaining)
                    showCustomSheet = true
                }
                .accessibilityIdentifier("log-rest-preset-custom")
                Button("Cancel", role: .cancel) { }
            }
        } else {
            Text(Self.formatTime(remaining))
                .styled(.monoL)
                .foregroundStyle(expired ? Color.ok : Color.accent)
                .monospacedDigit()
        }
    }

    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .styled(.monoXS)
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        // .borderless rather than .plain: iOS 26 XCUITest synthesized taps
        // do not fire .plain Button actions when the label is smaller than
        // ~44pt (these chips are ~38pt wide). Foregrounds are set explicitly
        // on the Text, so .borderless's accent tint doesn't change visuals.
        .buttonStyle(.borderless)
    }

    static func formatTime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 16) {
            RestTimer(remaining: 75, onAdd15: {}, onSkip: {}, onSetDuration: { _ in })
            RestTimer(remaining: 9, onAdd15: {}, onSkip: {}, onSetDuration: { _ in })
            RestTimer(remaining: 0, expired: true, onAdd15: {}, onSkip: {}, onSetDuration: { _ in })
        }
        .padding()
    }
}
