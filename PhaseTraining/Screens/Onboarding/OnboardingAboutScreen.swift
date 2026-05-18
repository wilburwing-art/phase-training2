// OnboardingAboutScreen.swift — age, gender, height, weight. All optional.
//
// Why optional: privacy + the planner doesn't gate on any of these yet.
// Height + weight (added build 44) unlock strength-to-bodyweight ratios on
// the Progress tab; gender refines the tier thresholds. Phase 13 LLM
// coach will tailor language with these when present.

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
            subtitle: "All optional. Skip anything you'd rather not share.",
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 24) {
                ageSection
                genderSection
                bodyMetricsSection
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

    // MARK: - Body metrics (height + weight, with units toggle)

    private var bodyMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                OnboardingSectionLabel(text: "Height & weight")
                Spacer()
                Button(draft.usesImperial ? "Use metric" : "Use imperial") {
                    draft.usesImperial.toggle()
                }
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
            }
            BodyMetricsEditor(draft: $draft)
            Text("Used for strength-to-bodyweight ratios on Progress.")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
    }

    // MARK: - Actions

    private func adjustAge(_ delta: Int) {
        let current = draft.age ?? 30
        let next = current + delta
        draft.age = min(max(next, minAge), maxAge)
    }
}

// MARK: - StepperButton (shared with BodyMetricsEditor)

struct StepperButton: View {
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

// MARK: - BodyMetricsEditor — reused on ProfileScreen

/// Stepper-driven editor for height + weight. Renders in the user's unit
/// system (`draft.usesImperial`) but mutates the underlying metric storage.
/// All fields optional — clear buttons appear when set.
struct BodyMetricsEditor: View {
    @Binding var draft: TrainingMemory

    // Reasonable seeds when the user opens an unset field — these are what
    // appears the first time they tap +/–. Both metric so we don't have to
    // branch on the unit system at seed time.
    private let defaultHeightCm = 175
    private let defaultWeightKg = 75.0

    private let minHeightCm = 120
    private let maxHeightCm = 230
    private let minWeightKg = 30.0
    private let maxWeightKg = 250.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heightRow
            weightRow
        }
    }

    // MARK: - Height

    private var heightRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HEIGHT")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                if draft.heightCm != nil {
                    Button("Clear") { draft.heightCm = nil }
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            HStack(spacing: 14) {
                StepperButton(symbol: "minus") { adjustHeight(-1) }
                VStack(spacing: 0) {
                    Text(BodyMetrics.formatHeight(cm: draft.heightCm, imperial: draft.usesImperial))
                        .font(.custom("JetBrainsMono-SemiBold", size: 26))
                        .foregroundStyle(draft.heightCm == nil ? Color.ink3 : Color.ink)
                    Text(draft.usesImperial ? "FT · IN" : "CM")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                .frame(maxWidth: .infinity)
                StepperButton(symbol: "plus") { adjustHeight(1) }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // Step size matches the unit so a tap feels natural — imperial steps
    // by 1 inch (≈2.54 cm), metric steps by 1 cm. The stored value is
    // always whole-cm; the imperial path quantises to the inch boundary.
    private func adjustHeight(_ delta: Int) {
        if draft.usesImperial {
            let curCm = draft.heightCm ?? defaultHeightCm
            let (f, i) = BodyMetrics.cmToFeetInches(curCm)
            let totalInches = f * 12 + i + delta
            let cm = BodyMetrics.feetInchesToCm(feet: 0, inches: totalInches)
            draft.heightCm = min(max(cm, minHeightCm), maxHeightCm)
        } else {
            let cur = draft.heightCm ?? defaultHeightCm
            draft.heightCm = min(max(cur + delta, minHeightCm), maxHeightCm)
        }
    }

    // MARK: - Weight

    private var weightRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WEIGHT")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                if draft.weightKg != nil {
                    Button("Clear") { draft.weightKg = nil }
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            HStack(spacing: 14) {
                StepperButton(symbol: "minus") { adjustWeight(-1) }
                VStack(spacing: 0) {
                    Text(BodyMetrics.formatWeight(kg: draft.weightKg, imperial: draft.usesImperial))
                        .font(.custom("JetBrainsMono-SemiBold", size: 26))
                        .foregroundStyle(draft.weightKg == nil ? Color.ink3 : Color.ink)
                    Text(draft.usesImperial ? "POUNDS" : "KILOGRAMS")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                .frame(maxWidth: .infinity)
                StepperButton(symbol: "plus") { adjustWeight(1) }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // Imperial steps by 1 lb, metric by 0.5 kg. Round-trip through kg keeps
    // the stored value canonical even when the user toggles units.
    private func adjustWeight(_ delta: Int) {
        if draft.usesImperial {
            let curLb = draft.weightKg.map(BodyMetrics.kgToLb) ?? BodyMetrics.kgToLb(defaultWeightKg)
            let nextLb = (curLb + Double(delta)).rounded()
            let nextKg = BodyMetrics.lbToKg(nextLb)
            draft.weightKg = clamp(nextKg)
        } else {
            let cur = draft.weightKg ?? defaultWeightKg
            draft.weightKg = clamp(cur + Double(delta) * 0.5)
        }
    }

    private func clamp(_ kg: Double) -> Double {
        // One-decimal precision keeps the JSON tidy.
        let rounded = (kg * 10).rounded() / 10
        return min(max(rounded, minWeightKg), maxWeightKg)
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingAboutScreen(draft: $draft, onNext: {}, onBack: {})
}
