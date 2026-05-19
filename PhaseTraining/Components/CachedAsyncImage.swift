// CachedAsyncImage.swift — in-memory + URLCache-backed async image loader.
//
// SwiftUI's stock AsyncImage refetches on every view re-creation and doesn't
// keep decoded images in memory across navigation. With ~555 exercise images
// served from raw.githubusercontent.com, that means every Library → detail
// → back round trip re-hits the network. This wrapper:
//
//   - Hits an NSCache<NSString, UIImage> first (fast in-memory hits)
//   - Falls back to URLSession.shared.data(from:) which honors URLCache.shared
//   - Caches successful decodes back into the in-memory cache
//
// URLCache.shared is upsized at app launch in PhaseTrainingApp.init() so
// disk-cached bytes survive across app launches.

import SwiftUI
import UIKit

enum ImageCache {
    static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 64 * 1024 * 1024  // 64 MB
        return cache
    }()
}

struct CachedAsyncImage<Loaded: View, Placeholder: View, Failure: View>: View {
    let url: URL?
    @ViewBuilder let loaded: (Image) -> Loaded
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: () -> Failure

    @State private var image: UIImage? = nil
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                loaded(Image(uiImage: image))
            } else if didFail {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { didFail = true; return }
        let key = url.absoluteString as NSString
        if let cached = ImageCache.memory.object(forKey: key) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = UIImage(data: data) else {
                didFail = true
                return
            }
            ImageCache.memory.setObject(decoded, forKey: key, cost: data.count)
            image = decoded
        } catch {
            didFail = true
        }
    }
}
