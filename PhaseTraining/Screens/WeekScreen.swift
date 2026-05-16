// WeekScreen.swift — Phase 11 Week tab. The planning surface.
//
// Renders PlanStore.plan + per-day affordances:
//   - Tap a row → WeekDayEditSheet for fine-grained edits
//   - Long-press + drag a row onto another → swap the two days
//
// Both routes mutate PlanStore.overrides + auto-regenerate.

import SwiftUI
import UniformTypeIdentifiers

struct WeekScreen: View {
    @EnvironmentObject private var planStore: PlanStore
    /// Tap-to-edit (overrides path; cofounder's phase 11).
    @State private var editingDate: Date? = nil
    /// Long-press menu → PlanDiff preview (PLAN spec path; for the Phase 13 coach).
    @State private var pendingDiff: PlanDiff?

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
        .sheet(item: Binding(
            get: { pendingDiff.map(IdentifiedDiff.init) },
            set: { pendingDiff = $0?.diff }
        )) { wrapper in
            PlanDiffSheet(
                diff: wrapper.diff,
                onApply: {
                    planStore.apply(wrapper.diff)
                    pendingDiff = nil
                },
                onCancel: { pendingDiff = nil }
            )
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

    private func propose(_ edits: [PlanEdit]) {
        if let diff = planStore.propose(edits), !diff.isNoop {
            pendingDiff = diff
        }
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
                        DraggableDayRow(
                            day: day,
                            isToday: isToday(day.date),
                            onTap: { editingDate = day.date }
                        )
                        .contextMenu { menuItems(for: day, plan: plan) }
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
            Text("Tap to customize · long-press and drag to swap days.")
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

    // MARK: - Context menu (Phase 11)

    @ViewBuilder
    private func menuItems(for day: DayPlan, plan: WeekPlan) -> some View {
        Menu("Move to…") {
            ForEach(plan.days.filter { $0.id != day.id }) { target in
                Button(weekdayLabel(target.date)) {
                    propose([.move(dayId: day.id, toDate: target.date)])
                }
            }
        }
        Menu("Change to…") {
            ForEach([DayKind.lift, .sport, .mobility, .rest], id: \.self) { newKind in
                if newKind != day.kind {
                    Button(newKind.label.capitalized) {
                        propose([.swapKind(
                            dayId: day.id,
                            to: newKind,
                            title: defaultTitle(for: newKind),
                            routineId: nil
                        )])
                    }
                }
            }
        }
        Menu("Shorten to…") {
            ForEach([30, 45, 60], id: \.self) { mins in
                Button("\(mins) min") {
                    propose([.shorten(dayId: day.id, toMinutes: mins)])
                }
            }
        }
        Button(day.protected ? "Unprotect" : "Protect day") {
            if day.protected {
                propose([.swapKind(dayId: day.id, to: .rest, title: "Rest", routineId: nil)])
            } else {
                propose([.protectDay(dayId: day.id, eventTitle: day.title)])
            }
        }
        if day.kind != .rest {
            Button("Remove session", role: .destructive) {
                propose([.removeSession(dayId: day.id)])
            }
        }
    }

    private func weekdayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private func defaultTitle(for kind: DayKind) -> String {
        switch kind {
        case .lift:     return "Lift"
        case .sport:    return "Sport"
        case .mobility: return "Mobility"
        case .rest:     return "Rest"
        case .event:    return "Event"
        }
    }
}

private struct IdentifiedDiff: Identifiable {
    let diff: PlanDiff
    var id: Int { diff.hashValue }
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

// MARK: - Draggable row wrapper
//
// Per-day view that owns its own `isTargeted` state for the drop highlight,
// and forwards taps + drops up to the planStore. Drag payload is a MovableDay
// (date string) — using Transferable's CodableRepresentation so the drag works
// across the SwiftUI process without manual NSItemProvider plumbing.

private struct DraggableDayRow: View {
    let day: DayPlan
    let isToday: Bool
    let onTap: () -> Void

    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var memory: MemoryStore
    @State private var isTargeted = false

    var body: some View {
        Button(action: onTap) {
            DayRow(day: day, isToday: isToday, isTargeted: isTargeted)
        }
        .buttonStyle(.plain)
        .draggable(MovableDay(date: day.date)) {
            // Lightweight drag preview — same row but de-saturated.
            DayRow(day: day, isToday: false, isTargeted: false)
                .frame(maxWidth: 340)
                .opacity(0.92)
        }
        .dropDestination(for: MovableDay.self) { items, _ in
            guard let source = items.first else { return false }
            // Self-drop is a no-op; PlanStore.swap already guards but we exit
            // early to avoid the haptic.
            if Calendar.current.isDate(source.date, inSameDayAs: day.date) {
                return false
            }
            planStore.swap(sourceDate: source.date,
                           targetDate: day.date,
                           memory: memory.memory)
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

// MARK: - Transferable drag payload

/// Date wrapper used as the drag payload between day rows.
struct MovableDay: Codable, Transferable {
    /// ISO yyyy-MM-dd. Decoded back to a Date on drop via DateFormatter.
    let dateISO: String

    init(date: Date) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        self.dateISO = f.string(from: date)
    }

    var date: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: dateISO) ?? Date()
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .text)
    }
}

// MARK: - DayRow

private struct DayRow: View {
    let day: DayPlan
    let isToday: Bool
    /// True while a drag hovers over this row — render an accent ring so the
    /// user knows where the drop will land.
    var isTargeted: Bool = false

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
        .background(isTargeted ? Color.accentWash : (isToday ? Color.accentWash : Color.surface))
        .overlay(alignment: .leading) {
            if isToday {
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: isTargeted ? 1.5 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private var borderColor: Color {
        if isTargeted { return Color.accent }
        return isToday ? Color.accentBorder : Color.line
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
