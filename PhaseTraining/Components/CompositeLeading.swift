// CompositeLeading.swift — 56pt photo + 28pt chip badge composite slot.
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ExerciseThumbnail(exerciseID: exerciseID, urlString: photoURL, size: 56, cornerRadius: 10)
            MuscleChipBadge(group: group, side: side)
                .offset(x: 6, y: 6)
        }
        .frame(width: 64, height: 64, alignment: .topLeading)
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
