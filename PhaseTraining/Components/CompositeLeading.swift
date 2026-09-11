// CompositeLeading.swift — 84pt photo + 28pt chip badge composite slot.
//
// The leading slot for the `.presentation` density `ExerciseTile` (the
// Today-screen variant). Combines an `ExerciseThumbnail` (inherits the
// placeholder + cache behavior) with a `MuscleChipBadge` anchored at the
// bottom-right, overhanging by 6pt on each axis so the badge reads as a
// separate element pinned on top of the photo rather than inset into it.
//
// Spec: HANDOFF-tile-system.md §4a, snippet §6 in
// handoff/ExerciseTile+Composite.swift.

import SwiftUI

struct CompositeLeading: View {
    let exerciseID: Int?
    let photoURL: String?
    let group: MuscleBucket
    let side: BodyAnatomyView.AnatomySide

    init(exerciseID: Int? = nil,
         photoURL: String?,
         group: MuscleBucket,
         side: BodyAnatomyView.AnatomySide) {
        self.exerciseID = exerciseID
        self.photoURL = photoURL
        self.group = group
        self.side = side
    }

    /// Photo edge (56 until 2026-09-11, then 112, settled at 84) and the
    /// slot that holds it plus the badge's 6pt overhang. The badge stays
    /// 28pt: its artwork is a pre-rendered 28pt PNG and would blur if scaled.
    static let photoSize: CGFloat = ExerciseTile.thumbSize
    static let frameSize: CGFloat = photoSize + 8

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ExerciseThumbnail(exerciseID: exerciseID, urlString: photoURL, size: Self.photoSize, cornerRadius: 14)
            MuscleChipBadge(group: group, side: side)
                .offset(x: 6, y: 6)
        }
        .frame(width: Self.frameSize, height: Self.frameSize, alignment: .topLeading)
    }
}

// MARK: - Preview

#Preview("Composite leading — photo + chip") {
    VStack(alignment: .leading, spacing: 16) {
        CompositeLeading(photoURL: nil, group: .chest, side: .front)
        CompositeLeading(photoURL: nil, group: .back, side: .back)
        CompositeLeading(photoURL: nil, group: .quads, side: .front)
        CompositeLeading(photoURL: nil, group: .glutes, side: .back)
    }
    .padding(20)
    .background(Color.bg.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
