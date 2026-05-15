// OnboardingPlanPreviewScreen.swift — final onboarding step.
//
// Generates a WeekPlan from the draft TrainingMemory + the live coach.db
// catalog, renders the 7-day overview, and offers Accept (commits + dismisses
// onboarding) / Back (return to Constraints).
//
// Generation runs once on appear and caches in @State so back-and-forth
// navigation doesn't reshuffle the routine picks. The preview is intentionally
// the same view layer as the Week tab will render — it's what the user is
// about to live with.

import SwiftUI

struct OnboardingPlanPreviewScreen: View {
    let memory: TrainingMemory
    let onAccept: () -> Void
    let onBack: () -> Void

    @State private var generated: WeekPlan?

    var body: some View {
        OnboardingScaffold(
            step: .planPreview,
            title: "Your week.",
            subtitle: subtitleText,
            nextLabel: "Accept plan",
            nextEnabled: generated != nil,
            onNext: onAccept,
            onBack: onBack
        ) {
            if let plan = generated {
                VStack(alignment: .leading, spacing: 12) {
                    summaryRow(plan: plan)
                    Divider().background(Color.lineSoft)
                    VStack(spacing: 8) {
                        ForEach(plan.days) { day in
                            DayPreviewRow(day: day, isToday: Calendar.current.isDateInToday(day.date))
                        }
                    }
                    Text("You can change any of this from Profile or the Week tab once you're in.")
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
        .onAppear { generateOnce() }
    }

    private func generateOnce() {
        guard generated == nil else { return }
        let routines = CoachDatabase.shared.listRoutines()
        generated = Planner.generate(memory: memory, routines: routines)
    }

    private var subtitleText: String {
        if let sport = memory.primarySport {
            return "Built around \(sport.name.lowercased()), \(memory.season.label.lowercased())."
        }
        return "Built around \(memory.primaryFocus.label.lowercased())."
    }

    private func summaryRow(plan: WeekPlan) -> some View {
        var counts: [DayKind: Int] = [:]
        for d in plan.days { counts[d.kind, default: 0] += 1 }
        let order: [DayKind] = [.lift, .sport, .mobility, .rest, .event]
        let parts = order.compactMap { kind -> String? in
            guard let n = counts[kind], n > 0 else { return nil }
            return "\(n) \(kind.label.lowercased())"
        }
        return Text(parts.joined(separator: " · "))
            .font(.monoXS)
            .foregroundStyle(Color.ink2)
    }
}

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
        case .lift:     return Color.accent
        case .sport:    return Color.ok.opacity(0.85)
        case .mobility: return Color.ink2.opacity(0.7)
        case .rest:     return Color.elevated
        case .event:    return Color.danger.opacity(0.9)
        }
    }

    private var badgeText: Color {
        switch day.kind {
        case .lift, .sport, .mobility, .event: return Color.accentInk
        case .rest: return Color.ink3
        }
    }
}

#Preview {
    var memory = TrainingMemory()
    memory.primarySport = Sport.catalog.first { $0.slug == "climbing" }
    memory.season = .inSeason
    memory.availableDays = Weekday.allCases
    memory.experience = .intermediate
    return OnboardingPlanPreviewScreen(memory: memory, onAccept: {}, onBack: {})
}
