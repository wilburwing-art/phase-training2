// CheckInPreviewScreen.swift — step 4: show regenerated WeekPlan, accept or back.

import SwiftUI

struct CheckInPreviewScreen: View {
    let plan: WeekPlan?
    /// 3b: per-day chance each planned session happens, from the last 90
    /// days. Informational only; nothing moves because of it.
    var likelihoods: [SessionLikelihood] = []
    let onAccept: () -> Void
    let onBack: () -> Void
    /// Escape hatch. Steps 2-5 passed nil, so CheckInScaffold rendered a blank
    /// 32x32 spacer where the X should be — a user who opened the flow from the
    /// Sunday notification and wanted out had to tap Back three or four times.
    let onClose: () -> Void

    var body: some View {
        CheckInScaffold(
            step: .preview,
            title: "Your new week.",
            subtitle: subtitleText,
            nextLabel: "Accept plan",
            nextEnabled: plan != nil,
            onNext: onAccept,
            onBack: onBack,
            onClose: onClose
        ) {
            if let plan {
                VStack(alignment: .leading, spacing: 12) {
                    summaryRow(plan: plan)
                    Divider().background(Color.lineSoft)
                    VStack(spacing: 8) {
                        ForEach(plan.days) { day in
                            DayPreviewRow(day: day, isToday: Calendar.current.isDateInToday(day.date),
                                          likelihood: likelihood(for: day))
                        }
                    }
                    if plan.days.contains(where: { likelihood(for: $0) != nil }) {
                        Text("The percentages show how often sessions like these happened for you in the last 90 days. A heads-up only; nothing moves on its own.")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Tweak any day from the Week tab once accepted.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ProgressView()
                    .tint(Color.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
        }
    }

    /// Shown only once there is enough history to mean something; with a
    /// handful of days every row would read the prior.
    static let minSamplesToShow = 6

    private func likelihood(for day: DayPlan) -> SessionLikelihood? {
        likelihoods.first {
            Calendar.current.isDate($0.date, inSameDayAs: day.date) && $0.samples >= Self.minSamplesToShow
        }
    }

    private var subtitleText: String {
        plan == nil ? "Generating…" : "Regenerated from your check-in."
    }

    private func summaryRow(plan: WeekPlan) -> some View {
        var counts: [DayKind: Int] = [:]
        for d in plan.days { counts[d.kind, default: 0] += 1 }
        let order: [DayKind] = [.lift, .sport, .rest, .event]
        let parts = order.compactMap { kind -> String? in
            guard let n = counts[kind], n > 0 else { return nil }
            return "\(n) \(kind.label.lowercased())"
        }
        return Text(parts.joined(separator: " · "))
            .font(.monoXS)
            .foregroundStyle(Color.ink2)
    }
}

// MARK: - Day row
//
// Had a twin in onboarding's plan-preview screen until that step was cut. This
// is now the only week-preview row in the app; the onboarding reveal moved to
// the live Week tab.

private struct DayPreviewRow: View {
    let day: DayPlan
    let isToday: Bool
    var likelihood: SessionLikelihood? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(weekdayShort)
                .font(.scaled("JetBrainsMono-SemiBold", size: 14))
                .foregroundStyle(isToday ? Color.accent : Color.ink2)
                .frame(width: 32, alignment: .leading)
            kindBadge
            Text(day.title)
                .styled(.body)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let likelihood {
                Text(verbatim: "\(likelihood.percent)%")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .accessibilityLabel("About \(likelihood.percent) percent likely to happen")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isToday ? Color.accentWash : Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isToday ? Color.accentBorder : Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Cached — one row per plan day per render; allocating a DateFormatter
    /// each call is needless churn.
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private var weekdayShort: String {
        Self.weekdayFormatter.string(from: day.date).uppercased()
    }

    private var kindBadge: some View {
        Text(day.kind.label)
            .styled(.micro)
            .foregroundStyle(badgeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeBg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var badgeBg: Color {
        switch day.kind {
        case .lift:  return Color.accent
        case .sport: return Color.ok.opacity(0.85)
        case .rest:  return Color.elevated
        case .event: return Color.danger.opacity(0.9)
        }
    }

    private var badgeText: Color {
        switch day.kind {
        case .lift, .sport, .event: return Color.accentInk
        case .rest: return Color.ink3
        }
    }
}
