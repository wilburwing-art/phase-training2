// CheckInPreviewScreen.swift — step 4: show regenerated WeekPlan, accept or back.

import SwiftUI

struct CheckInPreviewScreen: View {
    let plan: WeekPlan?
    let onAccept: () -> Void
    let onBack: () -> Void

    var body: some View {
        CheckInScaffold(
            step: .preview,
            title: "Your new week.",
            subtitle: subtitleText,
            nextLabel: "Accept plan",
            nextEnabled: plan != nil,
            onNext: onAccept,
            onBack: onBack,
            onClose: nil
        ) {
            if let plan {
                VStack(alignment: .leading, spacing: 12) {
                    summaryRow(plan: plan)
                    Divider().background(Color.lineSoft)
                    VStack(spacing: 8) {
                        ForEach(plan.days) { day in
                            DayPreviewRow(day: day, isToday: Calendar.current.isDateInToday(day.date))
                        }
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

// MARK: - Day row (mirrors OnboardingPlanPreviewScreen's private DayPreviewRow)

private struct DayPreviewRow: View {
    let day: DayPlan
    let isToday: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(weekdayShort)
                .font(.custom("JetBrainsMono-SemiBold", size: 14))
                .foregroundStyle(isToday ? Color.accent : Color.ink2)
                .frame(width: 32, alignment: .leading)
            kindBadge
            Text(day.title)
                .styled(.body)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
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

    private var weekdayShort: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: day.date).uppercased()
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
