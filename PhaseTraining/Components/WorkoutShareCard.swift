// WorkoutShareCard.swift — local share image + text for a finished workout.
//
// No account, no network, no name or body data: the card holds the session
// name, date, duration, sets, volume, PRs and the top exercises only.

import SwiftUI
import UIKit

struct WorkoutShareSummary: Equatable {
    struct PR: Equatable {
        let name: String
        let diff: Double
        let unit: String
    }

    struct DoneExercise: Equatable {
        let name: String
        let doneSets: Int
    }

    static let exerciseCap = 6

    let title: String
    let dateLine: String
    let durationLine: String
    let setsLine: String
    let volumeLine: String?
    let prLines: [String]
    let exerciseLines: [String]

    static func make(
        sessionName: String,
        date: Date,
        elapsedSeconds: Int,
        doneSets: Int,
        workingVolume: Double,
        usesImperial: Bool,
        prs: [PR],
        exercises: [DoneExercise]
    ) -> WorkoutShareSummary {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, MMM d"

        var volumeLine: String?
        if workingVolume > 0 {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "en_US")
            f.numberStyle = .decimal
            f.usesGroupingSeparator = true
            f.maximumFractionDigits = 0
            let number = f.string(from: NSNumber(value: workingVolume.rounded())) ?? "\(Int(workingVolume))"
            volumeLine = "\(number) \(usesImperial ? "lb" : "kg")"
        }

        let done = exercises.filter { $0.doneSets > 0 }
        var exerciseLines = done.prefix(exerciseCap).map { "\($0.name) · \(setsText($0.doneSets))" }
        if done.count > exerciseCap { exerciseLines.append("+\(done.count - exerciseCap) more") }

        return WorkoutShareSummary(
            title: sessionName,
            dateLine: dateFormatter.string(from: date),
            durationLine: CompleteScreen.formatElapsed(elapsedSeconds),
            setsLine: setsText(doneSets),
            volumeLine: volumeLine,
            prLines: prs.map { "\($0.name) +\(formatDiff($0.diff)) \($0.unit)" },
            exerciseLines: exerciseLines
        )
    }

    /// Duration, sets and volume on one line.
    var statsLine: String {
        ([durationLine, setsLine] + (volumeLine.map { [$0] } ?? [])).joined(separator: " · ")
    }

    var shareText: String {
        ([title, dateLine, statsLine] + prLines + exerciseLines + ["Logged in Phase"])
            .joined(separator: "\n")
    }

    private static func setsText(_ n: Int) -> String { n == 1 ? "1 set" : "\(n) sets" }

    private static func formatDiff(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.1f", d)
    }
}

/// Laid out at 360x450 points; rendered at scale 3 for 1080x1350 pixels.
struct WorkoutShareCardView: View {
    static let size = CGSize(width: 360, height: 450)

    let summary: WorkoutShareSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.dateLine.uppercased())
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    Text(summary.title)
                        .styled(.displayM)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                KettleView(pose: .flex)
                    .frame(width: 64, height: 64)
            }

            Text(summary.statsLine)
                .styled(.micro)
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 12)

            if !summary.prLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(summary.prLines.prefix(3).enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle")
                                .scaledSystemFont(11)
                            Text(line)
                                .styled(.micro)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(Color.accent)
                    }
                }
                .padding(.top, 14)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(summary.exerciseLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 0)

            Text("Logged in Phase")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.bg)
    }
}

enum WorkoutShareCard {
    @MainActor
    static func image(for summary: WorkoutShareSummary) -> UIImage? {
        let renderer = ImageRenderer(
            content: WorkoutShareCardView(summary: summary)
                .environment(\.colorScheme, .dark)
                // The card is a fixed 360x450 canvas; the user's text size
                // would overflow it at accessibility sizes.
                .environment(\.dynamicTypeSize, .large)
        )
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(WorkoutShareCardView.size)
        return renderer.uiImage
    }
}
