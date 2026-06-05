// WeeklyCheckInFlow.swift — Phase 12 retention loop coordinator.
//
// 4 steps: Intent → Constraints → Feedback → Preview.
// Captures a Draft, mutates TrainingMemory on accept, runs Planner with
// previousFeedback to regenerate the plan for the upcoming week, presents
// the regenerated plan, commits to PlanStore on Accept.
//
// Reuses the onboarding chrome (OnboardingScaffold + buttons) so the visual
// language matches.

import SwiftUI

// MARK: - Draft

struct WeeklyCheckInDraft {
    // Intent
    var intentText: String = ""
    var intentTags: Set<String> = []

    // Constraints (drop into WeekOverrides on accept; rolling forward 7 days)
    var unavailableDays: Set<Weekday> = []

    // Events for the upcoming week (races, sport sessions, hard climbs). The
    // planner uses these to anchor specific days + apply pre-event taper and
    // post-event recovery. Hydrated from planStore.overrides.events on first
    // appear so the user sees / can edit any pre-existing events.
    var events: [WeekEvent] = []

    // Feedback (becomes a WeeklyCheckIn record in memory.weeklyCheckIns;
    // FeedbackEntries from the CompleteScreen during the week stay where they are)
    var lastWeekRating: String? = nil        // "too_easy" | "right" | "too_hard"
    var worked: String = ""
    var didntWork: String = ""

    /// Flips to true after the first .onAppear so we don't re-overwrite
    /// user edits when the flow body re-renders.
    var hydrated: Bool = false

    /// Tags shown on the Intent step.
    static let intentChips: [(String, String)] = [
        ("more_volume",  "More volume"),
        ("less_volume",  "Less volume"),
        ("deload",       "Deload"),
        ("more_sport",   "More sport"),
        ("more_mobility","More mobility"),
        ("travel",       "Travel week"),
    ]
}

// MARK: - Steps

enum WeeklyCheckInStep: Int, CaseIterable {
    case intent = 0
    case constraints
    case events
    case feedback
    case preview

    /// Treated like onboarding's planPreview step — hide the counter.
    var humanIndex: Int { self == .preview ? 0 : rawValue + 1 }
    static var total: Int { WeeklyCheckInStep.allCases.count - 1 }

    func next() -> WeeklyCheckInStep? { WeeklyCheckInStep(rawValue: rawValue + 1) }
    func prev() -> WeeklyCheckInStep? { WeeklyCheckInStep(rawValue: rawValue - 1) }
}

// MARK: - Coordinator

struct WeeklyCheckInFlow: View {
    @EnvironmentObject private var memoryStore: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var sportLogStore: SportLogStore

    let onDismiss: () -> Void

    @State private var step: WeeklyCheckInStep = .intent
    @State private var draft = WeeklyCheckInDraft()
    @State private var previewPlan: WeekPlan?

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            content
                .id(step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .onAppear(perform: hydrateFromOverrides)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intent:
            CheckInIntentScreen(
                draft: $draft,
                onNext: advance,
                onClose: onDismiss
            )
        case .constraints:
            CheckInConstraintsScreen(
                draft: $draft,
                onNext: advance,
                onBack: back
            )
        case .events:
            CheckInEventsScreen(
                draft: $draft,
                weekStart: planStore.overrides.weekStart,
                onNext: advance,
                onBack: back
            )
        case .feedback:
            CheckInFeedbackScreen(
                draft: $draft,
                onNext: { regenerateAndAdvance() },
                onBack: back
            )
        case .preview:
            CheckInPreviewScreen(
                plan: previewPlan,
                onAccept: accept,
                onBack: back
            )
        }
    }

    /// Seed the draft with whatever the user has already entered on the Week
    /// tab so they see + can edit it rather than starting blank.
    private func hydrateFromOverrides() {
        guard !draft.hydrated else { return }
        draft.hydrated = true
        draft.unavailableDays = planStore.overrides.unavailableDays
        draft.events = planStore.overrides.events
    }

    private func advance() {
        guard let next = step.next() else { return }
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }

    private func back() {
        guard let prev = step.prev() else { return }
        withAnimation(.easeInOut(duration: 0.18)) { step = prev }
    }

    private func regenerateAndAdvance() {
        // PURE: build a candidate plan from the draft WITHOUT mutating memory or
        // overrides. All commits happen in accept() so that navigating Back from
        // the preview (or abandoning the flow) never double-stamps the check-in
        // or leaves a half-applied state. We generate against a LOCAL copy of
        // overrides merged with the draft's unavailable-days + events.
        var candidateOverrides = planStore.overrides
        candidateOverrides.unavailableDays = draft.unavailableDays
        candidateOverrides.events = draft.events
        let routines = CoachDatabase.shared.listRoutines()
        previewPlan = Planner.generate(
            memory: memoryStore.memory,
            overrides: candidateOverrides,
            routines: routines,
            previousFeedback: Array(memoryStore.memory.feedback.suffix(20)),
            recentSportLogs: sportLogStore.entries,
            // Without context the readiness lift-day floor defaults to neutral,
            // so the check-in regen silently ignored detrained-state capping
            // that every PlanStore regen path applies. Thread the real context.
            context: planStore.makeGeneratorContext(memory: memoryStore.memory)
        )
        advance()
    }

    private func accept() {
        guard let plan = previewPlan else { onDismiss(); return }
        // Commit everything together, exactly once, on accept. Stamp the
        // check-in into memory, push the draft's constraints/events into
        // overrides (idempotent wholesale replace), then set the plan.
        memoryStore.update { mem in
            mem.weeklyCheckIns.append(
                WeeklyCheckIn(
                    weekStart: Date().startOfTrainingWeek(),
                    intent: composedIntent,
                    lastWeekRating: draft.lastWeekRating,
                    notes: composedNotes
                )
            )
        }
        planStore.updateOverrides(memory: nil) { ov in
            ov.unavailableDays = draft.unavailableDays
            ov.events = draft.events
        }
        planStore.setPlan(plan)
        onDismiss()
    }

    private var composedIntent: String? {
        let tags = WeeklyCheckInDraft.intentChips
            .filter { draft.intentTags.contains($0.0) }
            .map { $0.1 }
        let parts = [tags.joined(separator: ", "), draft.intentText]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var composedNotes: String? {
        let parts = [
            draft.worked.isEmpty   ? nil : "worked: \(draft.worked)",
            draft.didntWork.isEmpty ? nil : "didn't: \(draft.didntWork)"
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Shared scaffold (mirrors OnboardingScaffold but with a Close affordance)

struct CheckInScaffold<Content: View>: View {
    let step: WeeklyCheckInStep
    let title: String
    let subtitle: String?
    let nextLabel: String
    let nextEnabled: Bool
    let onNext: () -> Void
    let onBack: (() -> Void)?
    let onClose: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        step: WeeklyCheckInStep,
        title: String,
        subtitle: String? = nil,
        nextLabel: String = "Continue",
        nextEnabled: Bool = true,
        onNext: @escaping () -> Void,
        onBack: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.step = step
        self.title = title
        self.subtitle = subtitle
        self.nextLabel = nextLabel
        self.nextEnabled = nextEnabled
        self.onNext = onNext
        self.onBack = onBack
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(title)
                                .styled(.displayL)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let subtitle {
                                Text(subtitle)
                                    .styled(.body)
                                    .foregroundStyle(Color.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        content()
                        Spacer().frame(height: 140)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            OnboardingPrimaryButton(label: nextLabel, enabled: nextEnabled, action: onNext,
                                    a11yId: "checkin-continue-\(step)")
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
                Spacer()
                if step.humanIndex > 0 {
                    Text("CHECK-IN \(step.humanIndex) OF \(WeeklyCheckInStep.total)")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.line)
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.accent)
                        .frame(width: geo.size.width * fillFraction, height: 2)
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 20)
        }
    }

    private var fillFraction: CGFloat {
        step == .preview
            ? 1.0
            : CGFloat(step.humanIndex) / CGFloat(WeeklyCheckInStep.total)
    }
}
