// HistoryCheckSheet.swift — what the history check left out, and why.
//
// `HistoryProfile` keeps flagged sets out of estimates without deleting
// them. This sheet is the only place that decision is visible, so a wrong
// call (a real heavy single read as a typo) can be seen.

import SwiftUI

struct HistoryCheckSheet: View {
    let audit: HistoryProfile.Audit
    var detraining: ProvenStrength.DetrainingRate = .standard
    @Environment(\.dismiss) private var dismiss

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Left out of weight suggestions. Nothing was deleted: these sets stay in your history.")
                            .styled(.body)
                            .foregroundStyle(Color.ink2)

                        if audit.flags.isEmpty {
                            Text("Nothing looked wrong.")
                                .styled(.body)
                                .foregroundStyle(Color.ink)
                        }
                        ForEach(groups, id: \.exercise) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.exercise)
                                    .styled(.displayS)
                                    .foregroundStyle(Color.ink)
                                ForEach(group.flags) { flag in
                                    Text(line(flag))
                                        .font(.monoXS)
                                        .foregroundStyle(Color.ink2)
                                        .accessibilityIdentifier("history-check-flag")
                                }
                            }
                        }

                        if !audit.layoffs.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("BREAKS OVER 8 WEEKS")
                                    .styled(.micro)
                                    .foregroundStyle(Color.ink3)
                                Text("Estimates start lighter after a break and catch up as you log.")
                                    .styled(.body)
                                    .foregroundStyle(Color.ink2)
                                if let rate = Self.rateLine(detraining) {
                                    Text(rate)
                                        .styled(.body)
                                        .foregroundStyle(Color.ink2)
                                        .accessibilityIdentifier("history-check-detraining")
                                }
                                ForEach(Array(audit.layoffs.enumerated()), id: \.offset) { _, gap in
                                    Text("\(Self.date.string(from: gap.from)) → \(Self.date.string(from: gap.to)) · \(gap.days) days")
                                        .font(.monoXS)
                                        .foregroundStyle(Color.ink2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle("History check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Nil unless the estimates use the lifter's own rate.
    static func rateLine(_ d: ProvenStrength.DetrainingRate) -> String? {
        guard d.isPersonal, let measured = d.measured else { return nil }
        func pct(_ x: Double) -> String { String(format: "%.1f%%", max(0, x) * 100) }
        let bound = measured < d.perWeek ? ", the gentlest we allow"
            : measured > d.perWeek ? ", the steepest we allow" : ""
        return "In \(d.breaks) past breaks you lost about \(pct(measured)) a week. Estimates use \(pct(d.perWeek))\(bound)."
    }

    private var groups: [(exercise: String, flags: [HistoryProfile.Flag])] {
        Dictionary(grouping: audit.flags, by: \.exercise)
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.exercise < $1.exercise }
    }

    private func line(_ f: HistoryProfile.Flag) -> String {
        let set = "\(Self.date.string(from: f.date)) · \(Self.lb(f.weightLb)) × \(f.reps)"
        switch f.reason {
        case .impossible:
            return "\(set) · not a possible set"
        case .outlier(let median):
            return "\(set) · rest of that workout around \(Self.lb(median))"
        case .duplicate(let of):
            return "\(set) · same sets as \(Self.date.string(from: of))"
        }
    }

    private static func lb(_ w: Double) -> String {
        // Round first: a kg round-trip turns 225 into 224.99999.
        let r = (w * 10).rounded() / 10
        return r.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(r)) lb" : String(format: "%.1f lb", r)
    }
}

/// The one-line entry point under the import section.
struct HistoryCheckRow: View {
    @EnvironmentObject private var sessions: SessionStore
    @State private var showing = false

    var body: some View {
        let profile = sessions.historyProfile
        let audit = profile.audit
        Button { showing = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History check")
                        .font(.subheadline)
                        .foregroundColor(.ink)
                    Text(summary(audit))
                        .font(.caption)
                        .foregroundColor(.ink2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.ink3)
            }
            .padding(12)
            .background(Color.surface)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history-check-row")
        .sheet(isPresented: $showing) { HistoryCheckSheet(audit: audit, detraining: profile.detraining) }
    }

    private func summary(_ audit: HistoryProfile.Audit) -> String {
        var parts: [String] = []
        let typos = audit.outlierSets + audit.impossibleSets
        if typos > 0 {
            parts.append(typos == 1 ? "left out 1 set that looks like a typo"
                                    : "left out \(typos) sets that look like typos")
        }
        if audit.duplicateBlocks > 0 {
            parts.append("\(audit.duplicateBlocks) duplicate \(audit.duplicateBlocks == 1 ? "workout" : "workouts")")
        }
        return parts.isEmpty ? "Nothing looked wrong" : parts.joined(separator: ", ").capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
