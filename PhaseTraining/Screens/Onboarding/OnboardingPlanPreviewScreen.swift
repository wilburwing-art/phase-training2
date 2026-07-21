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
    @State private var detailDay: DayPlan?

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
                    Text("Tap a lift or sport day to see the session.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                    VStack(spacing: 8) {
                        ForEach(plan.days) { day in
                            DayPreviewRow(
                                day: day,
                                isToday: Calendar.current.isDateInToday(day.date),
                                onTap: hasDetail(day) ? { detailDay = day } : nil
                            )
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
        .sheet(item: $detailDay) { day in
            OnboardingDayDetailSheet(day: day)
        }
        .onAppear { generateOnce() }
    }

    /// A day is worth opening if it's a lift with a built workout or a sport day.
    private func hasDetail(_ day: DayPlan) -> Bool {
        switch day.kind {
        case .lift:  return !(day.generatedWorkout?.exercises.isEmpty ?? true)
        case .sport: return true
        case .rest, .event: return false
        }
    }

    private func generateOnce() {
        guard generated == nil else { return }
        let routines = CoachDatabase.shared.listRoutines()
        generated = Planner.generate(memory: memory, routines: routines)
    }

    private var subtitleText: String {
        if let sport = memory.primarySport {
            return "Built around \(sport.name.lowercased()), \(memory.seasonForPlanner.label.lowercased())."
        }
        // Onboarding requires a supported sport (M2b), so this is just a guard.
        return "Built around your training week."
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

private struct DayPreviewRow: View {
    let day: DayPlan
    let isToday: Bool
    /// Non-nil when the row has detail worth opening (a lift with exercises or a
    /// sport day). Adds a chevron + makes the row a button.
    var onTap: (() -> Void)? = nil

    var body: some View {
        let row = HStack(alignment: .center, spacing: 12) {
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
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink3)
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

        if let onTap {
            Button(action: onTap) { row }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan-preview-day-\(day.kind.rawValue)-\(weekdayShort)")
        } else {
            row
        }
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

// MARK: - Read-only day detail (tapped from the plan preview)

/// What a preview day actually contains — the exercises of a lift, or the sport
/// session. Read-only: the user is still deciding whether to accept the plan, so
/// there's no Start/edit here. Reuses the DayPlan.generatedWorkout the preview
/// already generated (no re-roll).
private struct OnboardingDayDetailSheet: View {
    let day: DayPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        switch day.kind {
                        case .lift:
                            if let w = day.generatedWorkout, !w.exercises.isEmpty {
                                exerciseList(w)
                            } else {
                                note("This day's workout builds when you start it.")
                            }
                        case .sport:
                            sportDetail
                        case .rest:
                            note("Rest day — recovery. No session to preview.")
                        case .event:
                            note(day.title)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.accent)
                        .accessibilityIdentifier("day-detail-close")
                }
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(weekdayLong.uppercased()) · \(day.kind.label.uppercased())")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text(day.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            if day.kind == .lift, let w = day.generatedWorkout {
                Text("\(w.exercises.count) movements · ~\(w.estimatedMinutes) min")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                if !w.provenance.isEmpty, w.provenance.hasPrefix("Authored") {
                    Text(w.provenance)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private func exerciseList(_ w: GeneratedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXERCISES")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            ForEach(Array(w.exercises.enumerated()), id: \.element.id) { idx, ex in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(idx + 1)")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .frame(width: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                        Text(setRepLine(ex))
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                        if let notes = ex.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.monoXS)
                                .foregroundStyle(Color.accent)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var sportDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = day.notes, !note.isEmpty {
                Text("SESSION")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                Text(note)
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                note("\(day.sport?.name ?? "Sport") session — do your thing, then log it when you're done.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.custom("Inter-Regular", size: 14))
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func setRepLine(_ ex: GeneratedExercise) -> String {
        var parts = ["\(ex.sets) × \(ex.reps)"]
        if ex.restSeconds > 0 { parts.append("rest \(ex.restSeconds)s") }
        if let rpe = ex.rpe, !rpe.isEmpty { parts.append(rpe) }
        if let tempo = ex.tempo, !tempo.isEmpty { parts.append("tempo \(tempo)") }
        return parts.joined(separator: " · ")
    }

    private var weekdayLong: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: day.date)
    }
}

#Preview {
    @Previewable @State var memory: TrainingMemory = {
        var m = TrainingMemory()
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        m.sports = [climbing]
        m.primarySport = climbing
        m.seasonsBySport = [climbing: .inSeason]
        m.experience = .intermediate
        m.liftDaysPerWeek = 1
        return m
    }()
    return OnboardingPlanPreviewScreen(memory: memory, onAccept: {}, onBack: {})
}
