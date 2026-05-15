// OnboardingAboutScreen.swift — age + gender. Both optional.
//
// Why optional: privacy + the planner doesn't gate on either yet. Phase 13
// (LLM coach) will tailor language with these when present, and the rules
// engine may eventually use age for recovery defaults.

import SwiftUI

struct OnboardingAboutScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    private let minAge = 13
    private let maxAge = 99

    var body: some View {
        OnboardingScaffold(
            step: .about,
            title: "About you.",
            subtitle: "Both optional. Skip anything you'd rather not share.",
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 24) {
                ageSection
                genderSection
            }
        }
    }

    // MARK: - Age

    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                OnboardingSectionLabel(text: "Age")
                Spacer()
                if draft.age != nil {
                    Button("Clear") { draft.age = nil }
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            HStack(spacing: 14) {
                StepperButton(symbol: "minus") { adjustAge(-1) }
                VStack(spacing: 0) {
                    Text(draft.age.map(String.init) ?? "—")
                        .font(.custom("JetBrainsMono-SemiBold", size: 34))
                        .foregroundStyle(Color.ink)
                    Text("YEARS")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                .frame(maxWidth: .infinity)
                StepperButton(symbol: "plus") { adjustAge(1) }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Gender

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                OnboardingSectionLabel(text: "Gender")
                Spacer()
                if draft.gender != nil {
                    Button("Clear") { draft.gender = nil }
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            WrappingFlow(spacing: 8) {
                ForEach(Gender.allCases) { g in
                    OnboardingChip(
                        label: g.label,
                        selected: draft.gender == g,
                        action: { draft.gender = (draft.gender == g) ? nil : g }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func adjustAge(_ delta: Int) {
        let current = draft.age ?? 30
        let next = current + delta
        draft.age = min(max(next, minAge), maxAge)
    }
}

private struct StepperButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 48, height: 48)
                .background(Color.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingAboutScreen(draft: $draft, onNext: {}, onBack: {})
}
