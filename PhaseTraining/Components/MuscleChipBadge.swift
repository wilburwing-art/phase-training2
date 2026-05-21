// MuscleChipBadge.swift — 28pt outer / 24pt inner anatomy badge.
//
// Used as the bottom-right cap of `CompositeLeading` (photo + chip badge
// composite leading slot on `.presentation` tiles). Reuses BodyAnatomyView
// at chip scale with the new `tint: Color?` override so the figure renders
// accent-on-elevated instead of the red/orange/yellow recovery palette.
//
// Spec: HANDOFF-tile-system.md §4a, snippet §7 in
// handoff/ExerciseTile+Composite.swift.

import SwiftUI

struct MuscleChipBadge: View {
    let group: MuscleBucket
    let side: BodyAnatomyView.AnatomySide

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.bg)
            .frame(width: 28, height: 28)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.elevated)
                    BodyAnatomyView(
                        highlights: [group.primarySlug: .primary],
                        side: side,
                        tint: Color.accent
                    )
                    .padding(2)
                }
                .padding(2)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("All buckets × front/back") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(MuscleBucket.allCases) { bucket in
                HStack(spacing: 12) {
                    Text(bucket.label)
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 100, alignment: .leading)
                    MuscleChipBadge(group: bucket, side: .front)
                    MuscleChipBadge(group: bucket, side: .back)
                    Text("natural: \(bucket.naturalSide == .front ? "front" : "back")")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
        .padding(20)
    }
    .background(Color.bg.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
