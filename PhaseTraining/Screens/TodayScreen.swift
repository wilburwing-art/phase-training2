// TodayScreen.swift — Phase 10 successor to StartScreen.
//
// Renders today's hero based on PlanStore.plan?.today(). DayKind drives the
// treatment:
//   - .lift / .mobility → workout-style hero (date, last-session card,
//     exercise preview from coach.db routine, "Start workout" CTA)
//   - .sport            → sport-day card; no exercise list, no CTA (log
//     externally for now; sport-flavored logging is a Phase 12 surface)
//   - .rest             → rest card; encourages mobility
//   - .event            → event card
//   - no plan / pre-onboard → falls back to upper-1 hardcoded template
//     (so cold launches before onboarding completes still work; same path
//     UI tests use)
//
// Active sessions always win — if `store.active` exists we render its
// template regardless of today's plan, so the user can resume a workout
// even on a day the planner now thinks should be rest.

import SwiftUI

struct TodayScreen: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var planStore: PlanStore
    @EnvironmentObject var memoryStore: MemoryStore
    @EnvironmentObject var tabSelection: TabSelectionStore

    let onStart: () -> Void
    let onHistory: () -> Void

    /// Drives the "Pick a different routine" sheet on lift/mobility days.
    @State private var pickingRoutine = false

    // MARK: - Derived state

    private var todayPlan: DayPlan? { planStore.plan?.today() }

    /// Effective DayKind for rendering. Active session forces a workout
    /// hero. Otherwise, follow today's plan; default to lift if no plan.
    private var effectiveKind: DayKind {
        if store.active != nil { return .lift }
        return todayPlan?.kind ?? .lift
    }

    /// Template for the workout hero. nil on sport/rest/event days when
    /// there's no active session.
    private var template: WorkoutTemplate? {
        if let active = store.active, !active.exercises.isEmpty {
            return WorkoutTemplate(
                id: active.templateId,
                name: active.name,
                category: active.category,
                exercises: active.exercises.map { ex in
                    ExerciseTemplate(
                        id: ex.id, name: ex.name, type: ex.type, unit: ex.unit,
                        targetSets: ex.targetSets, targetReps: ex.targetReps, rest: ex.rest
                    )
                }
            )
        }
        // Generated workout (the new default for lift / mobility days).
        // Uses GeneratedWorkout.stableTemplateId — same exercises → same id,
        // so SessionStore.getPreviousSession finds last week's same-shape
        // workout and pulls weight + reps forward into the autofill column.
        if let _ = todayPlan, let workout = todayPlan?.generatedWorkout {
            return workout.toWorkoutTemplate(id: workout.stableTemplateId)
        }
        // Day-override picked a specific routine (custom workout or library pick).
        if let routineId = todayPlan?.routineId {
            return loadTemplate(routineId: routineId)
        }
        // No plan yet → upper-1 fallback. Guarantees TodayScreen always has
        // a usable template before onboarding runs.
        if planStore.plan == nil {
            return WorkoutTemplate.upper1
        }
        return nil
    }

    private func loadTemplate(routineId: Int) -> WorkoutTemplate? {
        let routines = CoachDatabase.shared.listRoutines()
        guard let r = routines.first(where: { $0.id == routineId }) else { return nil }
        let exercises = CoachDatabase.shared.exercises(forRoutineId: routineId)
        return r.toWorkoutTemplate(with: exercises)
    }

    private var totalSets: Int {
        template?.exercises.reduce(0) { $0 + $1.targetSets } ?? 0
    }

    private var previous: SavedSession? {
        guard let template else { return nil }
        return store.getPreviousSession(templateId: template.id)
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: Date()).uppercased()
    }

    private var heroTitle: String {
        switch effectiveKind {
        case .lift, .mobility:
            return template?.name.replacingOccurrences(of: " Day ", with: "\nDay ")
                ?? (todayPlan?.title ?? "Train")
        case .sport:
            return todayPlan?.sport.map { "\($0.name)\nday" } ?? "Sport day"
        case .rest:
            return "Rest day"
        case .event:
            return "Event day"
        }
    }

    /// True when the current plan's last day is within 2 days (or already past).
    /// Drives the "Plan next week" pill.
    private var planEndingSoon: Bool {
        guard let last = planStore.plan?.days.last?.date else { return false }
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let lastDay = cal.startOfDay(for: last)
        let daysLeft = cal.dateComponents([.day], from: now, to: lastDay).day ?? 0
        return daysLeft <= 2
    }

    /// Phase 11: static insight copy. Phase 13 coach pipes dynamic text in.
    /// nil = no card rendered. Picks first matching rule.
    private var insightCopy: String? {
        guard let plan = planStore.plan else { return nil }
        if let day = plan.today() {
            if day.protected {
                return "Today is protected. I won't shuffle it without asking."
            }
            if let mins = day.durationMinutes {
                return "Today's session is shortened to \(mins) min."
            }
        }
        return nil
    }

    private var heroSubtitle: String {
        switch effectiveKind {
        case .lift, .mobility:
            return template?.category ?? ""
        case .sport:
            return todayPlan?.sport != nil ? "Log it after." : "Sport day."
        case .rest:
            return "Sleep, food, walk. The work is in recovery."
        case .event:
            return todayPlan?.title ?? "Today's event."
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if planStore.needsRegeneration(for: memoryStore.memory) {
                            driftBanner
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                        }
                        if planEndingSoon {
                            planNextWeekPill
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                        }
                        if let body = insightCopy {
                            InsightCard(body: body)
                                .padding(.horizontal, 20)
                                .padding(.top, planEndingSoon ? 10 : 14)
                        }
                        hero
                            .padding(.horizontal, 20)
                            .padding(.top, (insightCopy == nil && !planEndingSoon) ? 24 : 14)
                        if let reason = todayPlan?.generatedReason {
                            reasonRow(reason)
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                        }
                        if canRegenToday {
                            regenerateTodayRow
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                        }
                        if effectiveKind.isWorkout {
                            PreWorkoutCheckIn()
                                .padding(.horizontal, 20)
                                .padding(.top, 18)
                            lastSessionCard
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                            if let template {
                                exerciseList(template)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                            }
                            pickRoutineLink
                                .padding(.horizontal, 20)
                                .padding(.top, 18)
                        }
                        Spacer().frame(height: 160)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Bottom CTA stack
            VStack(spacing: 10) {
                primaryButton
                historyButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $pickingRoutine) {
            RoutineLibraryFlow(
                onWorkoutStarted: {
                    pickingRoutine = false
                    onStart()
                },
                onDismiss: { pickingRoutine = false }
            )
            .presentationBackground(Color.bg)
        }
    }

    // MARK: - Drift + regenerate affordances (Phase 15c)

    /// True when today is a generated lift/mobility day with no active session
    /// — i.e. the user can safely re-roll the workout without disrupting an
    /// in-progress log.
    private var canRegenToday: Bool {
        guard store.active == nil else { return false }
        guard let day = todayPlan else { return false }
        guard !day.protected else { return false }
        guard day.kind == .lift || day.kind == .mobility else { return false }
        return day.generatedWorkout != nil
    }

    /// Profile drift → "Refresh this week from your new profile" CTA.
    private var driftBanner: some View {
        Button {
            planStore.regenerateWeek(memory: memoryStore.memory)
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.accent)
                Text("Profile changed — tap to refresh this week.")
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentWash)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentBorder, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-refresh-week")
    }

    /// Always-available "give me a different workout today" affordance. Uses
    /// a fresh deterministic salt so each tap re-rolls.
    private var regenerateTodayRow: some View {
        Button {
            planStore.regenerateToday(memory: memoryStore.memory)
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text("Regenerate today's workout")
                    .styled(.micro)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.ink3)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-regenerate")
    }

    private var planNextWeekPill: some View {
        Button { tabSelection.showWeeklyCheckIn = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("PLAN NEXT WEEK")
                    .styled(.micro)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentWash)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-plan-next-week")
    }

    private var pickRoutineLink: some View {
        Button { pickingRoutine = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 11, weight: .medium))
                Text("PICK A DIFFERENT ROUTINE")
                    .styled(.micro)
            }
            .foregroundStyle(Color.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-pick-routine")
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(dateLabel)
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                if effectiveKind.isWorkout, let template {
                    Text("~\(template.exercises.count) EX · \(totalSets) SETS")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                } else {
                    Text(effectiveKind.label)
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Rectangle()
                .fill(Color.line)
                .frame(height: 0.5)
                .padding(.top, 8)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heroTitle)
                .styled(.displayL)
                .foregroundStyle(Color.ink)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
            Text(heroSubtitle)
                .styled(.body)
                .foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reasonRow(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(Color.accent)
                .padding(.top, 2)
            Text(reason)
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Last session card

    private var lastSessionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("LAST SESSION")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text(daysAgoShort)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Text(lastSessionDetail)
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
                .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var daysAgoShort: String {
        guard let prev = previous else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: prev.startTime, to: Date()).day ?? 0
        return "\(days)d ago"
    }

    private var lastSessionDetail: String {
        guard let prev = previous else { return "First time — weights will be empty" }
        let stats = computeStats(prev)
        return "\(formatDuration(prev.duration)) · \(stats.doneSets) sets · avg rpe \(stats.avgRpe)"
    }

    // MARK: - Exercise list

    private func exerciseList(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY'S EXERCISES")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .padding(.bottom, 8)

            ForEach(Array(template.exercises.enumerated()), id: \.element.id) { idx, ex in
                exerciseRow(index: idx, ex: ex)
                if idx < template.exercises.count - 1 {
                    Rectangle()
                        .fill(Color.lineSoft)
                        .frame(height: 0.5)
                }
            }
        }
    }

    private func exerciseRow(index: Int, ex: ExerciseTemplate) -> some View {
        let prevEx = previous?.exercises.first(where: { $0.id == ex.id })
        let prevW = prevEx?.sets.first?.weight ?? ""
        let middle = prevW.isEmpty ? "no prev" : "\(prevW) \(ex.unit)"
        return HStack(alignment: .center, spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ex.name)
                        .styled(.displayS)
                        .foregroundStyle(Color.ink)
                    if let t = ex.type {
                        Text("(\(t))")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                }
                Text("\(ex.targetSets) sets · \(middle) · \(ex.targetReps) reps")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var primaryButton: some View {
        switch effectiveKind {
        case .lift, .mobility:
            workoutStartButton
        case .sport, .rest, .event:
            // No primary action — the user sees today's status, no session to start.
            EmptyView()
        }
    }

    private var workoutStartButton: some View {
        Button(action: startWorkout) {
            HStack(spacing: 6) {
                Text(store.active == nil ? "Start workout" : "Resume workout")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(template == nil)
    }

    private var historyButton: some View {
        Button(action: onHistory) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
                Text("HISTORY")
                    .styled(.micro)
            }
            .foregroundStyle(Color.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func startWorkout() {
        if store.active == nil, let template {
            store.saveActive(store.createSession(from: template))
        }
        onStart()
    }

    // MARK: - Helpers

    private func computeStats(_ session: SavedSession) -> (doneSets: Int, avgRpe: String) {
        var doneSets = 0
        var totalRpe: Double = 0
        var rpeCount = 0
        for ex in session.exercises {
            for s in ex.sets where s.done {
                doneSets += 1
                if !s.rpe.isEmpty, let v = Double(s.rpe), !v.isNaN {
                    totalRpe += v
                    rpeCount += 1
                }
            }
        }
        let avgRpe = rpeCount > 0 ? String(format: "%.1f", totalRpe / Double(rpeCount)) : "—"
        return (doneSets, avgRpe)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Preview

#Preview("Lift day with plan") {
    let suite = "TodayScreen.preview.lift"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let plan = PlanStore(defaults: defaults)
    plan.setPlan(.sample())
    return TodayScreen(onStart: {}, onHistory: {})
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(plan)
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(TabSelectionStore())
}

#Preview("No plan (fallback)") {
    let suite = "TodayScreen.preview.fallback"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return TodayScreen(onStart: {}, onHistory: {})
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(TabSelectionStore())
}
