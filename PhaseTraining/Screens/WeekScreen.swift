// WeekScreen.swift — Phase 11 Week tab. The planning surface.
//
// Renders PlanStore.plan + tap-to-edit on each day. Tapping a row presents
// WeekDayEditSheet which mutates PlanStore.overrides + auto-regenerates.
// "Customize this week" copy nudges users to actually use the edit affordance.

import SwiftUI

struct WeekScreen: View {
    @EnvironmentObject private var planStore: PlanStore
    @State private var editingDate: Date? = nil

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            if let plan = planStore.plan {
                content(plan: plan)
            } else {
                emptyState
            }
        }
        .sheet(item: editingDateBinding) { wrapped in
            WeekDayEditSheet(date: wrapped.date, dayPlan: dayPlan(for: wrapped.date))
        }
    }

    /// Bridge editingDate (Date?) → Identifiable wrapper for `.sheet(item:)`.
    private var editingDateBinding: Binding<EditingDate?> {
        Binding(
            get: { editingDate.map(EditingDate.init) },
            set: { editingDate = $0?.date }
        )
    }

    private func dayPlan(for date: Date) -> DayPlan? {
        planStore.plan?.days.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("WEEK")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text("No plan yet.")
                .font(.custom("SpaceGrotesk-SemiBold", size: 32))
                .tracking(-0.025 * 32)
                .foregroundStyle(Color.ink)
            Text("Complete onboarding to generate your week.")
                .styled(.body)
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Content

    private func content(plan: WeekPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(plan: plan)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 18)

                VStack(spacing: 10) {
                    ForEach(plan.days) { day in
                        Button {
                            editingDate = day.date
                        } label: {
                            DayRow(day: day, isToday: isToday(day.date))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 32)
            }
        }
    }

    private func header(plan: WeekPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THIS WEEK")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text(plan.rangeLabel)
                .font(.custom("SpaceGrotesk-SemiBold", size: 30))
                .tracking(-0.025 * 30)
                .foregroundStyle(Color.ink)
            Text(planSummary(plan))
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
            Text("Tap any day to customize.")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .padding(.top, 2)
        }
    }

    private func planSummary(_ plan: WeekPlan) -> String {
        var counts: [DayKind: Int] = [:]
        for d in plan.days { counts[d.kind, default: 0] += 1 }
        let order: [DayKind] = [.lift, .sport, .mobility, .rest, .event]
        let parts = order.compactMap { kind -> String? in
            guard let n = counts[kind], n > 0 else { return nil }
            return "\(n) \(kind.label.lowercased())"
        }
        return parts.joined(separator: " · ")
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

// MARK: - Identifiable wrapper for `.sheet(item:)`

private struct EditingDate: Identifiable {
    let date: Date
    var id: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - DayRow

private struct DayRow: View {
    let day: DayPlan
    let isToday: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Date strip
            VStack(spacing: 2) {
                Text(weekdayShort)
                    .styled(.micro)
                    .foregroundStyle(isToday ? Color.accent : Color.ink3)
                Text(dayNumber)
                    .font(.custom("JetBrainsMono-SemiBold", size: 22))
                    .foregroundStyle(isToday ? Color.ink : Color.ink2)
            }
            .frame(width: 44)

            // Body
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    KindBadge(kind: day.kind)
                    if day.protected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.ink3)
                    }
                    if isToday {
                        Text("TODAY")
                            .styled(.micro)
                            .foregroundStyle(Color.accent)
                    }
                    Spacer()
                }
                Text(day.title)
                    .styled(.displayS)
                    .foregroundStyle(Color.ink)
                if let reason = day.generatedReason {
                    Text(reason)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(isToday ? Color.accentWash : Color.surface)
        .overlay(alignment: .leading) {
            if isToday {
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isToday ? Color.accentBorder : Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var weekdayShort: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: day.date).uppercased()
    }

    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: day.date)
    }
}

private struct KindBadge: View {
    let kind: DayKind

    var body: some View {
        Text(kind.label)
            .styled(.micro)
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var bgColor: Color {
        switch kind {
        case .lift:     return Color.accent
        case .sport:    return Color.ok.opacity(0.85)
        case .mobility: return Color.ink2.opacity(0.7)
        case .rest:     return Color.elevated
        case .event:    return Color.danger.opacity(0.9)
        }
    }

    private var textColor: Color {
        switch kind {
        case .lift, .sport, .mobility, .event: return Color.accentInk
        case .rest: return Color.ink3
        }
    }
}

// MARK: - Preview

#Preview("Populated") {
    let suite = "WeekScreen.preview.populated"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = PlanStore(defaults: defaults)
    store.setPlan(.sample())
    return WeekScreen()
        .environmentObject(store)
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(SessionStore(defaults: defaults))
}

#Preview("Empty") {
    let defaults = UserDefaults(suiteName: "WeekScreen.preview.empty")!
    return WeekScreen()
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(SessionStore(defaults: defaults))
}
