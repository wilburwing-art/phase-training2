// MuscleChipGeneratorView.swift — DEBUG-only screen that pre-renders the
// 22 muscle-chip PNGs (11 buckets × 2 sides) into the app's Documents dir
// so they can be lifted into Assets.xcassets/MuscleChips/.
//
// At 28pt the live BodyAnatomyView (a MuscleMap ForEach of shape paths)
// produces an illegible blur and burns CPU per row. Pre-rendering each
// (bucket, side) once at 1x/2x/3x lets MuscleChipBadge load a flat
// .template image and tint with Color.accent — much cheaper and visually
// distinguishable bucket-to-bucket.
//
// Flow:
//   1. Open via Profile → "Regenerate muscle chips" (DEBUG only).
//   2. Tap Regenerate. Each (bucket, side) is rendered into a 252×252pt
//      frame at scale 1, 2, 3 via ImageRenderer (iOS 17+).
//   3. Files land in Documents/MuscleChips/<bucket>-<side>@<scale>x.png.
//   4. Run `scripts/install_muscle_chips.sh` to copy them into the
//      Assets.xcassets catalog with the right Contents.json metadata.

#if DEBUG

import SwiftUI
import UIKit

struct MuscleChipGeneratorView: View {
    @Environment(\.dismiss) private var dismiss

    /// When true, kick off rendering as soon as the view appears. Used by the
    /// `--regenerate-muscle-chips` launch flag so a single simctl launch +
    /// pause completes the entire generation cycle without manual taps.
    var autoRunOnAppear: Bool = false

    @State private var lastRunDir: URL? = nil
    @State private var lastRunCount: Int = 0
    @State private var lastError: String? = nil
    @State private var isRunning: Bool = false
    @State private var didAutoRun: Bool = false

    /// Logical render size for each chip. 252pt is 9× the 28pt display size,
    /// which gives @3x rasterization plenty of detail to downsample from.
    private let renderSize: CGFloat = 252

    /// All (bucket, side) pairs we need to ship. 11 × 2 = 22 chips.
    private var pairs: [(MuscleBucket, BodyAnatomyView.AnatomySide)] {
        MuscleBucket.allCases.flatMap { bucket in
            [(bucket, BodyAnatomyView.AnatomySide.front),
             (bucket, BodyAnatomyView.AnatomySide.back)]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Renders 22 chip PNGs (11 buckets × front/back) at 1×/2×/3× into Documents/MuscleChips. Then run scripts/install_muscle_chips.sh to copy them into Assets.xcassets.")
                        .styled(.body)
                        .foregroundStyle(Color.ink2)

                    chipPreviewGrid

                    Button(action: regenerate) {
                        HStack {
                            if isRunning {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.bg)
                            }
                            Text(isRunning ? "Regenerating…" : "Regenerate")
                                .styled(.body)
                                .foregroundStyle(Color.bg)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isRunning)

                    if let lastRunDir, lastRunCount > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Last run: \(lastRunCount) files")
                                .styled(.body)
                                .foregroundStyle(Color.ink)
                            Text(lastRunDir.path)
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let lastError {
                        Text(lastError)
                            .styled(.body)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Muscle chips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .onAppear {
                if autoRunOnAppear && !didAutoRun {
                    didAutoRun = true
                    // Give the view a tick to settle so the MuscleMap subviews
                    // populate before ImageRenderer captures.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        regenerate()
                    }
                }
            }
        }
    }

    // MARK: - Preview grid

    /// Renders all 22 chips at the actual on-screen 28pt size, so you can
    /// eyeball legibility before pulling files out of the simulator.
    private var chipPreviewGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live preview (28pt — what the row will show)")
                .styled(.body)
                .foregroundStyle(Color.ink2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 12) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: 4) {
                        chipPreview(bucket: pair.0, side: pair.1)
                        Text("\(pair.0.rawValue.prefix(4))·\(pair.1 == .front ? "F" : "B")")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chipPreview(bucket: MuscleBucket, side: BodyAnatomyView.AnatomySide) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.elevated)
            chipArtwork(bucket: bucket, side: side, tint: Color.accent)
                .padding(2)
        }
        .frame(width: 28, height: 28)
    }

    /// The artwork that gets snapshotted. Wrapped in a ZStack so the
    /// ImageRenderer can capture a clear-background 252×252 canvas with
    /// just the silhouette drawn in solid color.
    @ViewBuilder
    private func chipArtwork(bucket: MuscleBucket, side: BodyAnatomyView.AnatomySide, tint: Color) -> some View {
        BodyAnatomyView(
            highlights: [bucket.primarySlug: .primary],
            side: side,
            tint: tint
        )
    }

    // MARK: - Render + write

    private func regenerate() {
        isRunning = true
        lastError = nil
        Task { @MainActor in
            do {
                let (dir, count) = try renderAll()
                lastRunDir = dir
                lastRunCount = count
                isRunning = false
            } catch {
                lastError = "Failed: \(error.localizedDescription)"
                isRunning = false
            }
        }
    }

    @MainActor
    private func renderAll() throws -> (URL, Int) {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let outDir = docs.appendingPathComponent("MuscleChips", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var written = 0
        let scales: [CGFloat] = [1.0, 2.0, 3.0]

        for (bucket, side) in pairs {
            let view = chipArtwork(bucket: bucket, side: side, tint: .black)
                .frame(width: renderSize, height: renderSize)
                .background(Color.clear)

            for scale in scales {
                let renderer = ImageRenderer(content: view)
                renderer.scale = scale
                renderer.proposedSize = ProposedViewSize(width: renderSize, height: renderSize)
                guard let uiImage = renderer.uiImage else {
                    throw NSError(domain: "MuscleChipGenerator", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "ImageRenderer returned nil for \(bucket.rawValue)-\(side == .front ? "front" : "back")@\(Int(scale))x"])
                }
                guard let png = uiImage.pngData() else {
                    throw NSError(domain: "MuscleChipGenerator", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "PNG encode failed for \(bucket.rawValue)-\(side == .front ? "front" : "back")@\(Int(scale))x"])
                }
                let name = "\(bucket.rawValue)-\(side == .front ? "front" : "back")@\(Int(scale))x.png"
                let url = outDir.appendingPathComponent(name)
                try png.write(to: url, options: .atomic)
                written += 1
            }
        }

        // Also drop a small README so it's clear how the files map to assets.
        let readme = """
        Generated by MuscleChipGeneratorView.

        Files: <bucket>-<side>@<scale>x.png
        Buckets: \(MuscleBucket.allCases.map { $0.rawValue }.joined(separator: ", "))
        Sides: front, back
        Scales: 1x, 2x, 3x

        Pull these into the host repo with:
          scripts/install_muscle_chips.sh
        """
        try readme.write(
            to: outDir.appendingPathComponent("README.txt"),
            atomically: true, encoding: .utf8
        )

        return (outDir, written)
    }
}

#Preview {
    MuscleChipGeneratorView()
        .preferredColorScheme(.dark)
}

#endif
