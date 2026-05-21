// TodayRecoveryCard.swift — glance-view recovery card on Today.
//
// Compact body silhouette + two stats, sized to live above the workout
// hero on Today. Tap → switches to Progress tab where the full per-muscle
// list lives. No tab of its own.

import SwiftUI

struct TodayRecoveryCard: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var tabSelection: TabSelectionStore

    var body: some View {
        let rows = MuscleFreshness.rows(from: store.savedSessions)
        let highlights = recoveryHighlights(from: rows)
        let freshCount = rows.filter { $0.freshness >= 1.0 }.count
        let needsRestCount = rows.filter { $0.freshness < 0.66 }.count

        Button {
            tabSelection.selected = .progress
        } label: {
            HStack(alignment: .center, spacing: 16) {
                BodyAnatomyView(highlights: highlights, side: .back)
                    .frame(width: 70, height: 130)

                VStack(alignment: .leading, spacing: 12) {
                    statRow(value: "\(freshCount)", label: "FRESH")
                    statRow(value: "\(needsRestCount)", label: "NEEDS REST")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Muscle recovery — \(freshCount) fresh, \(needsRestCount) need rest. Tap for details.")
    }

    private func statRow(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.custom("SpaceGrotesk-SemiBold", size: 22))
                .tracking(-0.025 * 22)
                .foregroundStyle(Color.ink)
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
    }

    private func recoveryHighlights(
        from rows: [MuscleFreshness.Row]
    ) -> [String: BodyAnatomyView.HighlightIntensity] {
        var out: [String: BodyAnatomyView.HighlightIntensity] = [:]
        for row in rows where row.intensity != .none {
            out[row.slug] = row.intensity
        }
        return out
    }
}

#Preview("Today recovery card") {
    TodayRecoveryCard()
        .environmentObject(SessionStore(defaults: UserDefaults(suiteName: "TodayRecoveryCard.preview")!))
        .environmentObject(TabSelectionStore())
        .padding()
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
