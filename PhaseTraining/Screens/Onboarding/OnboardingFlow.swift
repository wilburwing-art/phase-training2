// OnboardingFlow.swift — coordinator for the 8-step first-launch onboarding.
//
// Holds a draft TrainingMemory in @State; the user can move forward/backward
// freely. Only the final step commits via MemoryStore.completeOnboarding(),
// which flips the gate in PhaseTrainingApp's fullScreenCover.
//
// Also exports the shared chrome (OnboardingScaffold + OnboardingChip +
// OnboardingPickRow + OnboardingButton) used by every step screen so each
// step is just title + subtitle + a content block.

import SwiftUI

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case sports
    case sportSeasons       // per-sport season picker (replaces single .season)
    case focus              // multi-select
    case availability       // days + minutes + lift target
    case equipment          // tier-based
    case experience
    case about              // age + gender (optional)
    case constraints
    /// Apple Guideline 5.1.2(i) consent gate for the AI Coach. Defaults to ON
    /// with explicit accept-via-Continue. If skipped on a fresh install the
    /// coach bubble never appears, which is the bug this step closes.
    case coachConsent
    /// Final confirmation: shows the generated plan + Accept CTA. Not counted
    /// in the questionnaire numerator/denominator since it's not a question.
    case planPreview

    /// Numbered position shown to the user ("Step 2 of 9"). Welcome is step 1.
    /// planPreview returns 0 — the scaffold hides the counter for it.
    var humanIndex: Int {
        self == .planPreview ? 0 : rawValue + 1
    }
    /// Denominator for "Step X of Y". Excludes planPreview.
    static var total: Int { OnboardingStep.allCases.count - 1 }

    func next() -> OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    func prev() -> OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

// MARK: - Coordinator

struct OnboardingFlow: View {
    @EnvironmentObject private var store: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @State private var step: OnboardingStep = .welcome
    @State private var draft = TrainingMemory()

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            content
                .id(step) // forces transition each step
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .onAppear {
            // Resume mid-flow if the user is editing their profile? No — onboarding only
            // shows when onboardedAt is nil, so we always start fresh.
            draft = store.memory
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeScreen(onStart: { advance() })
        case .sports:
            OnboardingSportsScreen(draft: $draft, onNext: { advance() }, onBack: { back() })
        case .sportSeasons:
            OnboardingSportSeasonsScreen(draft: $draft, onNext: { advance() }, onBack: { back() })
        case .focus:
            OnboardingFocusScreen(draft: $draft, onNext: { advance() }, onBack: { back() })
        case .availability:
            OnboardingAvailabilityScreen(draft: $draft, onNext: { advance() }, onBack: { back() })
        case .equipment:
            OnboardingEquipmentScreen(draft: $draft, onNext: { advance() }, onBack: { back() })
        case .experience:
            OnboardingExperienceScreen(draft: $draft, onNext: { advance() }, onBack: { back() })
        case .about:
            OnboardingAboutScreen(draft: $draft, onNext: { advance() }, onBack: { back() })
        case .constraints:
            OnboardingConstraintsScreen(draft: $draft, onNext: { advance() }, onBack: { back() })
        case .coachConsent:
            OnboardingCoachConsentScreen(onNext: { advance() }, onBack: { back() })
        case .planPreview:
            OnboardingPlanPreviewScreen(memory: draft, onAccept: finish, onBack: { back() })
        }
    }

    private func advance() {
        guard let next = step.next() else { return }
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }

    private func back() {
        guard let prev = step.prev() else { return }
        withAnimation(.easeInOut(duration: 0.18)) { step = prev }
    }

    private func finish() {
        store.memory = draft
        store.completeOnboarding()
        // Generate + persist the plan against the just-committed memory so the
        // Today + Week tabs have something live the moment the cover dismisses.
        planStore.generate(from: store.memory)
    }
}

// MARK: - Shared scaffold
//
// Every step (after Welcome) reuses this layout: top progress bar + back chevron,
// big title + subtitle, scrollable content slot, sticky Next/Continue button.

struct OnboardingScaffold<Content: View>: View {
    let step: OnboardingStep
    let title: String
    let subtitle: String?
    let nextLabel: String
    let nextEnabled: Bool
    let onNext: () -> Void
    let onBack: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        step: OnboardingStep,
        title: String,
        subtitle: String? = nil,
        nextLabel: String = "Continue",
        nextEnabled: Bool = true,
        onNext: @escaping () -> Void,
        onBack: (() -> Void)?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.step = step
        self.title = title
        self.subtitle = subtitle
        self.nextLabel = nextLabel
        self.nextEnabled = nextEnabled
        self.onNext = onNext
        self.onBack = onBack
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

            OnboardingPrimaryButton(label: nextLabel, enabled: nextEnabled, action: onNext)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
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
                    Text("STEP \(step.humanIndex) OF \(OnboardingStep.total)")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            OnboardingProgressBar(step: step)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - Progress bar

struct OnboardingProgressBar: View {
    let step: OnboardingStep

    private var fillFraction: CGFloat {
        // planPreview is post-questionnaire — bar shows full.
        step == .planPreview
            ? 1.0
            : CGFloat(step.humanIndex) / CGFloat(OnboardingStep.total)
    }

    var body: some View {
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
    }
}

// MARK: - Buttons

struct OnboardingPrimaryButton: View {
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(enabled ? Color.accentInk : Color.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(enabled ? Color.accent : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Chip (single tap)

struct OnboardingChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(selected ? Color.accentInk : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? Color.accent : Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(selected ? Color.clear : Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 999))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pick row (full-width title + subtitle row, used for big single-select choices)

struct OnboardingPickRow: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    var leading: String? = nil      // optional SF Symbol
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                if let leading {
                    Image(systemName: leading)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selected ? Color.accent : Color.ink2)
                        .frame(width: 24, alignment: .center)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .styled(.displayS)
                        .foregroundStyle(Color.ink)
                    if let subtitle {
                        Text(subtitle)
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Color.accent : Color.line)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(selected ? Color.accentWash : Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.accentBorder : Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section eyebrow

struct OnboardingSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }
}

// MARK: - Preview

#Preview("Flow") {
    OnboardingFlow()
        .environmentObject(MemoryStore(defaults: UserDefaults(suiteName: "Onboarding.preview")!))
        .environmentObject(PlanStore(defaults: UserDefaults(suiteName: "Onboarding.preview.plan")!))
}
