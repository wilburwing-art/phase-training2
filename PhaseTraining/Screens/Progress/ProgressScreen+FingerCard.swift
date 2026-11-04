// ProgressScreen+FingerCard.swift — max-hang finger strength over time.
//
// Shown to a lifter who climbs, or who has logged a test: the latest result
// as a share of body weight, a sparkline across tests, and the way to log one.

import SwiftUI

extension ProgressScreen {

    var fingerStrengthCard: some View {
        let tests = memoryStore.memory.maxHangTests.sorted { $0.date < $1.date }
        return Group {
            if memoryStore.memory.climbs || !tests.isEmpty {
                card(title: "FINGER STRENGTH") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let latest = tests.last {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(latest.percentLabel)
                                    .font(.scaled("JetBrainsMono-SemiBold", size: 18))
                                    .foregroundStyle(Color.ink)
                                    .accessibilityIdentifier("progress-finger-latest")
                                Spacer()
                                Text("\(tests.count) test\(tests.count == 1 ? "" : "s")")
                                    .font(.monoXS)
                                    .foregroundStyle(Color.ink3)
                            }
                            if tests.count >= 2 {
                                let pts = tests.map { $0.ratio * 100 }
                                BodyWeightSpark(points: pts, minValue: pts.min() ?? 0, maxValue: pts.max() ?? 1)
                                    .frame(height: 44)
                            }
                            Text("Max hang, 20mm edge, 10 seconds.")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                        } else {
                            Text("Test a 10-second max hang on a 20mm edge to track finger strength.")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                        }
                        Button {
                            presentingMaxHangSheet = true
                        } label: {
                            Text("Log a test")
                                .styled(.micro)
                                .foregroundStyle(Color.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progress-finger-log")
                    }
                }
                .sheet(isPresented: $presentingMaxHangSheet) {
                    MaxHangTestSheet().environmentObject(memoryStore)
                }
            }
        }
    }
}
