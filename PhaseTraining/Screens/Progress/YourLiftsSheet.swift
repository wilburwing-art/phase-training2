// YourLiftsSheet.swift — every lift the history profile knows, one row each.
//
// Progress shows six top exercises; this is the full list behind "See all
// lifts". Each row's estimate comes from `ExerciseStrengthSummary`, the same
// string the Your strength card shows, and a row whose name
// resolves to a catalog exercise opens that card's detail sheet.

import SwiftUI

enum YourLifts {
    /// One profile per lift, newest `lastTrained` first. `HistoryProfile`
    /// keys each lift under its catalog id and every raw name it was logged
    /// as, so the same profile appears several times in `exercises`.
    static func rows(_ profile: HistoryProfile) -> [HistoryProfile.ExerciseProfile] {
        var seen: Set<String> = []
        return profile.exercises.values
            .filter { $0.estimate != nil }
            .sorted { ($0.lastTrained, $0.name) > ($1.lastTrained, $1.name) }
            .filter { seen.insert($0.name).inserted }
    }

    /// The trend in a word, for a list row. The Your strength card spells it out.
    static func trendWord(_ p: HistoryProfile.ExerciseProfile) -> String {
        switch p.trend {
        case .rising: return "Rising"
        case .falling: return "Falling"
        case .flat: return p.plateau ? "Plateau" : "Holding"
        case .unknown: return "No trend yet"
        }
    }
}

struct YourLiftsSheet: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var memoryStore: MemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var detail: Exercise?

    var body: some View {
        let rows = YourLifts.rows(store.historyProfile)
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.name) { p in
                            row(p)
                            Rectangle().fill(Color.lineSoft).frame(height: 0.5)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Your lifts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .sheet(item: $detail) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
    }

    @ViewBuilder
    private func row(_ p: HistoryProfile.ExerciseProfile) -> some View {
        let summary = ExerciseStrengthSummary(profile: p, defaultReps: nil,
                                              usesImperial: memoryStore.memory.usesImperial, now: Date())
        let exercise = ExerciseLookupCache.shared.exercise(forName: p.name)
        Button {
            detail = exercise
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name)
                        .font(.scaled("Inter-Regular", size: 14))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(YourLifts.trendWord(p))
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
                Spacer(minLength: 6)
                Text(summary.map { "est max \($0.estimate)" } ?? "")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink2)
                if exercise != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(exercise == nil)
        .accessibilityIdentifier("your-lifts-row-\(p.name)")
    }
}
