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
    @EnvironmentObject private var memory: MemoryStore
    @EnvironmentObject private var tabSelection: TabSelectionStore
    @State private var editingDate: Date? = nil
    /// PR 6 (weekly-coach roadmap) — opens the WeekTone picker sheet.
    @State private var pickingWeekTone = false
    /// Date of the day row currently being dragged. Shared across rows so
    /// each row can tell a self-drop hover (no-op) apart from a valid swap
    /// target and render the disabled cue instead of the accent drop ring.
    @State private var draggingDate: Date? = nil

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
        .sheet(isPresented: $pickingWeekTone) {
            WeekTonePickerSheet(
                current: planStore.overrides.weekTone,
                onPick: { tone in
                    planStore.updateOverrides(memory: memory.memory) { o in
                        // tone == .typical encodes as "no adjustment"; clear
                        // to nil so the chip reads "set tone" again rather
                        // than "Typical" (less noise on the default).
                        o.weekTone = (tone == .typical) ? nil : tone
                    }
                    pickingWeekTone = false
                }
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

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        if memory.isOnboarded {
            // Onboarded but plan missing (e.g., legacy install before plan generation
            // was wired into onboarding) — let them regenerate from existing memory.
            VStack(spacing: 16) {
                Spacer()
                Text("WEEK")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                Text("No plan yet.")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 32))
                    .tracking(-0.025 * 32)
                    .foregroundStyle(Color.ink)
                Text("Generate a plan from your profile to get started.")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    planStore.generate(from: memory.memory)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Generate plan")
                            .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                    }
                    .foregroundStyle(Color.accentInk)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                Spacer()
            }
        } else {
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
    }

    // MARK: - Content

    /// Static Mon→Sun layout — no ScrollView, no LazyVStack. Seven rows are
    /// always visible at fixed positions so muscle memory is "row 3 = Wed".
    /// Rows are sized by GeometryReader so all seven always fit the available
    /// viewport between header and the system tab bar — iPhone SE through
    /// 16 Pro Max.
    private func content(plan: WeekPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(plan: plan)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // PR 7 — surface rules-engine issues inline. Banner renders
            // 0–2 rows by default with a "+N more" affordance; collapses
            // when there are no visible issues so the strip stays clean
            // on healthy weeks.
            let issues = planStore.currentValidationIssues(memory: memory.memory)
            if !issues.isEmpty {
                PlanValidationBanner(
                    issues: issues,
                    onAcknowledge: { issue in
                        planStore.recordPlanOverride(issue)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("plan-validation-banner")
            }

            GeometryReader { geo in
                let spacing: CGFloat = 6
                let rowH = max(48, (geo.size.height - spacing * 6) / 7)
                VStack(spacing: spacing) {
                    ForEach(Array(plan.days.enumerated()), id: \.element.id) { idx, day in
                        DraggableDayRow(
                            day: day,
                            isToday: isToday(day.date),
                            onTap: { editingDate = day.date },
                            draggingDate: $draggingDate
                        )
                        .frame(height: rowH)
                        .accessibilityIdentifier("week-day-row-\(idx)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func header(plan: WeekPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("THIS WEEK")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                Spacer(minLength: 4)
                SeasonPhaseBadge(style: .compact, surface: "week")
            }
            Text(plan.rangeLabel)
                .font(.custom("SpaceGrotesk-SemiBold", size: 26))
                .tracking(-0.025 * 26)
                .foregroundStyle(Color.ink)
            HStack(spacing: 8) {
                Text(planSummary(plan))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                Spacer(minLength: 4)
                // PR 6 — WeekTone chip. Tap → picker. When unset, reads
                // "Set tone"; when set, reads the chosen tone label.
                WeekToneChip(
                    tone: planStore.overrides.weekTone,
                    action: { pickingWeekTone = true }
                )
                .accessibilityIdentifier("week-tone-chip")
            }
            // Week-level actions. Both are chips rather than full-width pills
            // because the seven day rows below are sized by GeometryReader to
            // fill the viewport, so anything taller here steals row height.
            HStack(spacing: 6) {
                // PR 6 — "typical week" fast path: copy last week's shape onto
                // this week in one tap. Only when a prior week exists to copy.
                if planStore.hasPriorWeekShape {
                    chip(icon: "arrow.uturn.backward", title: "Same as last week",
                         identifier: "week-same-as-last") {
                        planStore.adoptLastWeekShape(memory: memory.memory)
                    }
                }
                // Build 122 — moved off Today, where it was one of five tiles
                // between the header and the workout. Week is the planning
                // surface, and this is now the only in-app door to the check-in
                // (the other setter is a `plan-week` notification deep link),
                // so it is permanent here rather than gated on the week ending.
                chip(icon: "calendar.badge.plus", title: "Plan next week",
                     identifier: "week-plan-next") {
                    tabSelection.showWeeklyCheckIn = true
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    /// Shared chrome for the header's week-level actions.
    private func chip(icon: String, title: String, identifier: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .styled(.monoXS)
            }
            .foregroundStyle(Color.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func planSummary(_ plan: WeekPlan) -> String {
        var counts: [DayKind: Int] = [:]
        for d in plan.days { counts[d.kind, default: 0] += 1 }
        let order: [DayKind] = [.lift, .sport, .rest, .event]
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

// MARK: - Cached formatters

/// DateFormatter is expensive to allocate; these run per row render and per
/// drag payload, so cache one instance per distinct format.
private enum WeekDateFormatters {
    /// ISO yyyy-MM-dd — sheet identity + drag payload encoding.
    static let isoDay: DateFormatter = DayKeyFormatter.iso

    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
}

// MARK: - Identifiable wrapper for `.sheet(item:)`

private struct EditingDate: Identifiable {
    let date: Date
    var id: String {
        WeekDateFormatters.isoDay.string(from: date)
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
    /// Date of the row being dragged, owned by WeekScreen — see note there.
    @Binding var draggingDate: Date?

    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var memory: MemoryStore
    @State private var isTargeted = false

    /// True while the drag hovering this row started from this same day.
    /// Dropping here is a no-op, so the row renders the disabled cue.
    private var isSelfTarget: Bool {
        guard isTargeted, let dragging = draggingDate else { return false }
        return Calendar.current.isDate(dragging, inSameDayAs: day.date)
    }

    /// Magnitude of the declared SUPPORT day this row represents, if any —
    /// derived from memory.supportPattern (source of truth), so only the
    /// climbing days the user actually declared get the badge. nil for regular
    /// sport days, lifts, and rests.
    private var supportMagnitude: SupportMagnitude? {
        guard day.kind == .sport,
              let pattern = memory.memory.supportPattern,
              day.sport?.slug == pattern.sportSlug else { return nil }
        return pattern.magnitude(on: Weekday.from(date: day.date, calendar: .current))
    }

    var body: some View {
        Button(action: onTap) {
            DayRow(day: day, isToday: isToday, isTargeted: isTargeted, isSelfTarget: isSelfTarget,
                   supportMagnitude: supportMagnitude)
        }
        .buttonStyle(.plain)
        .draggable(MovableDay(date: day.date)) {
            // Lightweight drag preview — same row but de-saturated. onAppear
            // doubles as the drag-start hook (SwiftUI exposes no other one)
            // to record which day is in flight.
            DayRow(day: day, isToday: false, isTargeted: false, supportMagnitude: supportMagnitude)
                .frame(maxWidth: 340)
                .opacity(0.92)
                .onAppear { draggingDate = day.date }
        }
        .dropDestination(for: MovableDay.self) { items, _ in
            draggingDate = nil
            // Abort if the payload date can't be parsed — a silent fallback to
            // "today" would move the wrong day and corrupt the plan.
            guard let source = items.first, let sourceDate = source.date else { return false }
            // Self-drop is a no-op; PlanStore.swap already guards but we exit
            // early to avoid the haptic.
            if Calendar.current.isDate(sourceDate, inSameDayAs: day.date) {
                return false
            }
            planStore.swap(sourceDate: sourceDate,
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
        self.dateISO = WeekDateFormatters.isoDay.string(from: date)
    }

    /// nil when the payload string can't be parsed — callers must abort the
    /// drop rather than silently fall back to "today" and move the wrong day.
    var date: Date? {
        WeekDateFormatters.isoDay.date(from: dateISO)
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
    /// True while the row is hovered by its own drag — dropping is a no-op,
    /// so render a dimmed dashed treatment instead of the accent drop ring.
    var isSelfTarget: Bool = false
    /// Non-nil when this is a declared support-sport day — renders the
    /// magnitude badge next to the SPORT kind badge.
    var supportMagnitude: SupportMagnitude? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Date strip
            VStack(spacing: 0) {
                Text(weekdayShort)
                    .styled(.micro)
                    .foregroundStyle(isToday ? Color.accent : Color.ink3)
                Text(dayNumber)
                    .font(.custom("JetBrainsMono-SemiBold", size: 18))
                    .foregroundStyle(isToday ? Color.ink : Color.ink2)
            }
            .frame(width: 36)

            KindBadge(kind: day.kind)

            if let mag = supportMagnitude {
                SupportBadge(magnitude: mag)
            }

            Text(day.title)
                .styled(.displayS)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if day.protected {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ink3)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(background)
        .overlay(alignment: .leading) {
            if isToday {
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 4)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, style: StrokeStyle(
                    lineWidth: (isToday || isTargeted) ? 1.5 : 0.5,
                    dash: isSelfTarget ? [4, 3] : []
                ))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isSelfTarget ? 0.55 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .animation(.easeOut(duration: 0.12), value: isSelfTarget)
    }

    private var background: Color {
        // Self-drop is a no-op — stay flat instead of lighting the accent
        // wash so the user can tell nothing will happen on this drop.
        if isSelfTarget { return Color.surface }
        if isTargeted || isToday { return Color.accentWash }
        return Color.surface
    }

    private var borderColor: Color {
        if isSelfTarget { return Color.ink3 }
        if isTargeted { return Color.accent }
        return isToday ? Color.accent : Color.line
    }

    private var weekdayShort: String {
        WeekDateFormatters.weekdayShort.string(from: day.date).uppercased()
    }

    private var dayNumber: String {
        WeekDateFormatters.dayNumber.string(from: day.date)
    }
}

/// Support-sport magnitude chip, shown next to the SPORT kind badge on a
/// declared support day. Outlined (not filled) so it reads as secondary
/// metadata vs the filled kind badges; color escalates with load so a big day
/// — the one the primary plan bends hardest to protect — stands out.
private struct SupportBadge: View {
    let magnitude: SupportMagnitude

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "figure.climbing")
                .font(.system(size: 9, weight: .semibold))
            Text(shortLabel)
                .styled(.micro)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(tint.opacity(0.55), lineWidth: 0.75)
        )
    }

    private var shortLabel: String {
        switch magnitude {
        case .light:  return "LIGHT"
        case .medium: return "MED"
        case .big:    return "BIG"
        }
    }

    private var tint: Color {
        switch magnitude {
        case .light:  return Color.ink2
        case .medium: return Color.accent
        case .big:    return Color.danger
        }
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
        case .lift:  return Color.accent
        case .sport: return Color.ok.opacity(0.85)
        case .rest:  return Color.elevated
        case .event: return Color.danger.opacity(0.9)
        }
    }

    private var textColor: Color {
        switch kind {
        case .lift, .sport, .event: return Color.accentInk
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

// MARK: - WeekToneChip + WeekTonePickerSheet
//
// PR 6 (weekly-coach roadmap) — the light-touch context chip below the
// strip header. When unset (no week-level adjustment), reads "Set tone"
// and points at the picker. When set to `.recovery` / `.build` / `.busy`,
// shows the chosen tone label so the user knows the week is biased.

private struct WeekToneChip: View {
    let tone: WeekTone?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tone == nil ? "slider.horizontal.3" : icon(for: tone!))
                    .font(.system(size: 11, weight: .medium))
                Text(tone?.label ?? "Set tone")
                    .styled(.monoXS)
            }
            .foregroundStyle(tone == nil ? Color.ink2 : Color.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tone == nil ? Color.surface : Color.accentWash)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tone == nil ? Color.line : Color.accentBorder,
                                  lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func icon(for tone: WeekTone) -> String {
        switch tone {
        case .typical:  return "circle"
        case .recovery: return "leaf"
        case .build:    return "arrow.up.right"
        case .busy:     return "hourglass"
        }
    }
}

private struct WeekTonePickerSheet: View {
    let current: WeekTone?
    let onPick: (WeekTone) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("WEEK TONE")
                        .styled(.micro)
                        .foregroundStyle(Color.accent)
                    Text("How's this week shaping up?")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 24))
                        .tracking(-0.025 * 24)
                        .foregroundStyle(Color.ink)

                    VStack(spacing: 10) {
                        ForEach(WeekTone.allCases, id: \.self) { tone in
                            ToneCard(
                                tone: tone,
                                isSelected: tone == current,
                                action: { onPick(tone) }
                            )
                            .accessibilityIdentifier("tone-card-\(tone.rawValue)")
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.bg)
    }
}

private struct ToneCard: View {
    let tone: WeekTone
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tone.label)
                        .styled(.body)
                        .foregroundStyle(isSelected ? Color.accentInk : Color.ink)
                    Text(subtitle)
                        .styled(.monoXS)
                        .foregroundStyle(isSelected ? Color.accentInk.opacity(0.85) : Color.ink2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentInk)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accent : Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Subtitle text — explains what each tone actually does. Keeps the
    /// chip non-mysterious; users shouldn't have to guess what "Build"
    /// means.
    private var subtitle: String {
        switch tone {
        case .typical:  return "Default — no adjustment to volume or duration"
        case .recovery: return "Lower volume (~30% fewer sets) for a deload week"
        case .build:    return "Higher volume (~15% more sets) for a hard push"
        case .busy:     return "Shorter sessions (~70% of usual length)"
        }
    }
}

#Preview("Empty") {
    let defaults = UserDefaults(suiteName: "WeekScreen.preview.empty")!
    return WeekScreen()
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(SessionStore(defaults: defaults))
}
