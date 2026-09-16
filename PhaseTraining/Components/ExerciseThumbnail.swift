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
//      A generated exercise ships four: `<id>.webp` + `<id>_end.webp` (themed
//      line art, this thumbnail flips between them) and `<id>_hero.webp` +
//      `<id>_hero_end.webp` (mannequin renders, the detail hero).
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

    /// Bundle-first. Falls through to the URL path if no bundled WebP exists
    /// for this id. There is no URL-only init on purpose: promoting an
    /// exercise clears its URL, so a call site that passed only the URL drew
    /// the placeholder for exactly the rows carrying generated art (the Log
    /// header did, until build 130). Resolve the id, through
    /// ExerciseLookupCache when only a name is in hand.
    init(exerciseID: Int?, urlString: String?, size: CGFloat = 44, cornerRadius: CGFloat = 8) {
        self.exerciseID = exerciseID
        self.urlString = urlString
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let bundled = bundledImage {
                if let end = bundledEndImage {
                    // Generated start/end pair: flip between the two frames
                    // so the row reads as the movement. TimelineView is torn
                    // down with the row when it scrolls off a LazyVStack, so
                    // nothing ticks for rows that are not on screen.
                    TimelineView(.periodic(from: .now, by: Self.flipInterval)) { context in
                        let showEnd = Int(context.date.timeIntervalSinceReferenceDate / Self.flipInterval) % 2 == 1
                        Image(uiImage: showEnd ? end : bundled)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
                            .id(showEnd)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: showEnd)
                    }
                } else {
                    Image(uiImage: bundled)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                }
            } else {
                CachedAsyncImage(
                    url: urlString.flatMap(URL.init(string:)),
                    loaded: { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
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
        .overlay {
            // The hairline frames a photo's edge against the card. Themed
            // line art has no edge: it is ink on the card's own surface,
            // and the frame read as a box drawn around the figure.
            if !isTransparentArt {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.line, lineWidth: 0.5)
            }
        }
    }

    private var isTransparentArt: Bool {
        guard let exerciseID else { return false }
        return BundledExerciseImage.shared.isTransparent(forID: exerciseID)
    }

    /// Look up the bundled WebP for `exerciseID`. Returns nil for missing ids
    /// (the 21 long-tail exercises whose source URL didn't resolve at bundle
    /// time) so the URL/placeholder fallback can kick in.
    private var bundledImage: UIImage? {
        guard let exerciseID else { return nil }
        return BundledExerciseImage.shared.image(forID: exerciseID)
    }

    /// Seconds each frame of a start/end pair is held. Slow enough to read
    /// as "start, end" rather than a flicker.
    static let flipInterval: TimeInterval = 1.2

    private var bundledEndImage: UIImage? {
        guard let exerciseID else { return nil }
        return BundledExerciseImage.shared.endImage(forID: exerciseID)
    }
}

/// Memoized lookup of bundled exercise WebPs. UIImage(named:) caches by name
/// internally but explicitly checking presence first lets us skip the misses
/// in O(1) for the long-tail exercises that don't have a bundled image.
final class BundledExerciseImage {
    static let shared = BundledExerciseImage()

    /// Filename suffixes a generated exercise can ship, after the numeric id.
    /// "" is the single image every exercise has (start frame for a pair);
    /// the others exist only for exercises promoted by scripts/imagegen.
    private static let suffixes = ["", "_end", "_hero", "_hero_end"]
    private var present: [String: Set<Int>] = [:]
    private var loaded: [String: [Int: UIImage]] = [:]
    private let lock = NSLock()

    private init() {
        // Enumerate once at init. `Resources/ExerciseImages/` is registered
        // as a folder reference in Project.yml (xcodegen `type: folder`), so
        // the subdirectory is preserved in the .app bundle. Also enumerate
        // the bundle root as a fallback for any build that uses the older
        // hand-edited pbxproj layout (which flattens contents).
        for suffix in Self.suffixes { present[suffix] = [] }
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let fm = FileManager.default

        func scan(_ names: [String]) {
            for name in names where name.hasSuffix(".webp") {
                let stem = String(name.dropLast(5))
                // Longest suffix first so "_hero_end" is not read as "_end".
                for suffix in Self.suffixes.sorted(by: { $0.count > $1.count })
                where stem.hasSuffix(suffix) {
                    if let id = Int(stem.dropLast(suffix.count)) {
                        present[suffix, default: []].insert(id)
                    }
                    break
                }
            }
        }
        let subdir = (resourcePath as NSString).appendingPathComponent("ExerciseImages")
        if fm.fileExists(atPath: subdir) {
            scan((try? fm.contentsOfDirectory(atPath: subdir)) ?? [])
        }
        if present[""]?.isEmpty ?? true {
            scan((try? fm.contentsOfDirectory(atPath: resourcePath)) ?? [])
        }
    }

    /// The single bundled image, or the START frame of a generated pair.
    func image(forID id: Int) -> UIImage? { cached(id, suffix: "") }

    /// END frame of a generated line-art pair; nil for single-image exercises.
    func endImage(forID id: Int) -> UIImage? { cached(id, suffix: "_end") }

    /// Mannequin start frame for the detail hero; nil unless generated.
    func heroImage(forID id: Int) -> UIImage? { cached(id, suffix: "_hero") }

    /// Mannequin end frame for the detail hero; nil unless generated.
    func heroEndImage(forID id: Int) -> UIImage? { cached(id, suffix: "_hero_end") }

    /// Whether the start image carries an alpha channel. Themed line art is
    /// RGBA ink over nothing; photos and the free-exercise-db drawings are
    /// opaque. Callers use it to decide what sits behind the image.
    func isTransparent(forID id: Int) -> Bool {
        guard let cg = image(forID: id)?.cgImage else { return false }
        switch cg.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst: return false
        default: return true
        }
    }

    private func cached(_ id: Int, suffix: String) -> UIImage? {
        guard present[suffix]?.contains(id) == true else { return nil }
        lock.lock()
        if let hit = loaded[suffix]?[id] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        // Try the subdirectory (xcodegen folder reference) first, then the
        // bundle root (hand-edited pbxproj flat layout).
        let resource = "\(id)\(suffix)"
        var img: UIImage?
        if let url = Bundle.main.url(forResource: resource, withExtension: "webp", subdirectory: "ExerciseImages"),
           let data = try? Data(contentsOf: url) {
            img = UIImage(data: data)
        }
        if img == nil,
           let url = Bundle.main.url(forResource: resource, withExtension: "webp"),
           let data = try? Data(contentsOf: url) {
            img = UIImage(data: data)
        }
        if let img {
            lock.lock()
            loaded[suffix, default: [:]][id] = img
            lock.unlock()
        }
        return img
    }
}
