// ExerciseThumbnail.swift — small square thumbnail for an Exercise.
//
// Used in Library list rows, SubstituteExerciseSheet rows, and the LogScreen
// exercise header. Wraps CachedAsyncImage with a consistent placeholder
// (icon) so a missing or unloaded image doesn't shift layout.
//
// Rendered against a white background — free-exercise-db images are line
// illustrations on white, so dark surface behind would crop awkwardly.

import SwiftUI

struct ExerciseThumbnail: View {
    let urlString: String?
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 8

    var body: some View {
        let url = urlString.flatMap(URL.init(string:))
        CachedAsyncImage(
            url: url,
            loaded: { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background(Color.white)
            },
            placeholder: {
                ZStack {
                    Color.elevated
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: size * 0.4, weight: .regular))
                        .foregroundStyle(Color.ink3)
                }
                .frame(width: size, height: size)
            },
            failure: {
                ZStack {
                    Color.elevated
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Color.ink3)
                }
                .frame(width: size, height: size)
            }
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.line, lineWidth: 0.5)
        )
    }
}
