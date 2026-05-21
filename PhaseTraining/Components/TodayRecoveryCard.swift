// TodayRecoveryCard.swift — glance pill for recovery on Today.
//
// Single-row pill above the workout hero — small body silhouette + inline
// counts + chevron. Tap → switches to Progress tab where the full per-muscle
// list lives. Deliberately understated: recovery is a pre-workout signal,
// not the primary action.

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
            HStack(spacing: 10) {
                BodyAnatomyView(highlights: highlights, side: .back)
                    .frame(width: 22, height: 40)
                Text("\(freshCount)")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink)
                Text("FRESH")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text("·")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text("\(needsRestCount)")
                    .font(.monoXS)
                    .foregroundStyle(needsRestCount > 0 ? Color.danger : Color.ink)
                Text("NEEDS REST")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Muscle recovery — \(freshCount) fresh, \(needsRestCount) need rest. Tap for details.")
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

#Preview("Today recovery pill") {
    TodayRecoveryCard()
        .environmentObject(SessionStore(defaults: UserDefaults(suiteName: "TodayRecoveryCard.preview")!))
        .environmentObject(TabSelectionStore())
        .padding()
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
