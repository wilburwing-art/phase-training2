// ExerciseThumbnail.swift — small square thumbnail for an Exercise.
//
// Used in Library list rows, SubstituteExerciseSheet rows, and the LogScreen
// exercise header. Wraps CachedAsyncImage with a consistent placeholder
// (icon) so a missing or unloaded image doesn't shift layout.
//
// Resolution order (offline-first):
//   1. Bundled `<exerciseID>.webp` shipped under Resources/ExerciseImages/
//      (flattened to app bundle root at build time — folder reference in
//      project.pbxproj). Loads via UIImage(named:) sync, no network.
//   2. `urlString` via CachedAsyncImage — NSCache + URLCache disk fallback.
//   3. SF Symbol placeholder.
//
// Rendered against a white background — free-exercise-db images are line
// illustrations on white, so dark surface behind would crop awkwardly.

import SwiftUI
import UIKit

struct ExerciseThumbnail: View {
    let exerciseID: Int?
    let urlString: String?
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 8

    /// Original URL-only init kept for existing call sites that don't have
    /// an exerciseID resolved (Library / SubstituteExerciseSheet / LogScreen).
    init(urlString: String?, size: CGFloat = 44, cornerRadius: CGFloat = 8) {
        self.exerciseID = nil
        self.urlString = urlString
        self.size = size
        self.cornerRadius = cornerRadius
    }

    /// Bundle-first init for composite leading slots. Falls through to the
    /// URL path if no bundled WebP exists for this id.
    init(exerciseID: Int?, urlString: String?, size: CGFloat = 44, cornerRadius: CGFloat = 8) {
        self.exerciseID = exerciseID
        self.urlString = urlString
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let bundled = bundledImage {
                Image(uiImage: bundled)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background(Color.white)
            } else {
                CachedAsyncImage(
                    url: urlString.flatMap(URL.init(string:)),
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
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.line, lineWidth: 0.5)
        )
    }

    /// Look up the bundled WebP for `exerciseID`. Returns nil for missing ids
    /// (the 21 long-tail exercises whose source URL didn't resolve at bundle
    /// time) so the URL/placeholder fallback can kick in.
    private var bundledImage: UIImage? {
        guard let exerciseID else { return nil }
        return BundledExerciseImage.shared.image(forID: exerciseID)
    }
}

/// Memoized lookup of bundled exercise WebPs. UIImage(named:) caches by name
/// internally but explicitly checking presence first lets us skip the misses
/// in O(1) for the long-tail exercises that don't have a bundled image.
final class BundledExerciseImage {
    static let shared = BundledExerciseImage()
    private let presentIDs: Set<Int>
    private var loaded: [Int: UIImage] = [:]
    private let lock = NSLock()

    private init() {
        // Enumerate once at init. `Resources/ExerciseImages/` is registered
        // as a folder reference in Project.yml (xcodegen `type: folder`), so
        // the subdirectory is preserved in the .app bundle. Also enumerate
        // the bundle root as a fallback for any build that uses the older
        // hand-edited pbxproj layout (which flattens contents).
        guard let resourcePath = Bundle.main.resourcePath else {
            self.presentIDs = []
            return
        }
        let fm = FileManager.default
        var ids: Set<Int> = []

        let subdir = (resourcePath as NSString).appendingPathComponent("ExerciseImages")
        if fm.fileExists(atPath: subdir) {
            let names = (try? fm.contentsOfDirectory(atPath: subdir)) ?? []
            for name in names where name.hasSuffix(".webp") {
                if let id = Int(name.dropLast(5)) { ids.insert(id) }
            }
        }
        if ids.isEmpty {
            let names = (try? fm.contentsOfDirectory(atPath: resourcePath)) ?? []
            for name in names where name.hasSuffix(".webp") {
                if let id = Int(name.dropLast(5)) { ids.insert(id) }
            }
        }
        self.presentIDs = ids
    }

    func image(forID id: Int) -> UIImage? {
        guard presentIDs.contains(id) else { return nil }
        lock.lock()
        if let hit = loaded[id] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        // Try the subdirectory (xcodegen folder reference) first, then the
        // bundle root (hand-edited pbxproj flat layout).
        var img: UIImage?
        if let url = Bundle.main.url(forResource: "\(id)", withExtension: "webp", subdirectory: "ExerciseImages"),
           let data = try? Data(contentsOf: url) {
            img = UIImage(data: data)
        }
        if img == nil,
           let url = Bundle.main.url(forResource: "\(id)", withExtension: "webp"),
           let data = try? Data(contentsOf: url) {
            img = UIImage(data: data)
        }
        if let img {
            lock.lock()
            loaded[id] = img
            lock.unlock()
        }
        return img
    }
}
