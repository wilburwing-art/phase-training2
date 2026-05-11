// RestTimer.swift — Rest-period overlay component for LogScreen.
//
// Presentation-only: parent owns the countdown via TimelineView and passes
// `remaining` (seconds) plus +15 / skip callbacks. Mirrors the inline rest
// card in `handoff/proto/log.jsx:188-206` and `handoff/hd-training-log.jsx:59-80`.
//
// Visuals (from handoff/README.md:290-296):
//   - 12pt corner radius, accentWash background, 0.5pt accentBorder border
//   - Pulse dot (7pt, accent) with opacity 1 → 0.35 → 1 over 1.6s ease-in-out
//   - "REST" micro label (accent)
//   - Mono L remaining-time readout (M:SS, accent)
//   - "+15" and "Skip" pill chips

import SwiftUI

struct RestTimer: View {
    let remaining: Int
    let onAdd15: () -> Void
    let onSkip: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accent)
                .frame(width: 7, height: 7)
                .opacity(pulse ? 0.35 : 1.0)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }

            Text("REST")
                .styled(.micro)
                .foregroundStyle(Color.accent)
                .textCase(.uppercase)

            Text(Self.formatTime(remaining))
                .styled(.monoL)
                .foregroundStyle(Color.accent)
                .monospacedDigit()

            Spacer(minLength: 4)

            chip("+15", action: onAdd15)
            chip("Skip", action: onSkip)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .buttonStyle(.plain)
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
            RestTimer(remaining: 75, onAdd15: {}, onSkip: {})
            RestTimer(remaining: 9, onAdd15: {}, onSkip: {})
        }
        .padding()
    }
}
