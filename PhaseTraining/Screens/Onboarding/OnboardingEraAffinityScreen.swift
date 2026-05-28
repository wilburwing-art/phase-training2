// OnboardingEraAffinityScreen.swift — Phase-1 surface for the
// age-derived training-era cohort. Sits between .about (where age is
// captured) and .constraints in the OnboardingFlow.
//
// Three actions:
//   1. Accept derived — sets draft.eraOverride = derivedCohort.rawValue
//      and advances.
//   2. Pick a different cohort — reveals the 5-cohort chip picker
//      inline; tapping a chip sets the override and advances on
//      Continue.
//   3. No preference (skip) — leaves draft.eraOverride = nil, so the
//      generator still uses the derived cohort as a weak prior but
//      nothing is locked in.
//
// Per the phase-training-personalization-three-axes skill, this is the
// SURFACE axis (people have strong feelings about being typecast by
// age). The other two axes — competency (`ExperienceLevel`) and
// readiness (Phase 2, derived from history) — are SILENT and not
// surfaced here.
//
// Audit note (audits/full-review-2026-05-26/03-critique-onboarding-profile.md):
// the existing onboarding flow has friction around length + per-step
// repetition. This screen is kept SHORT — three pick-rows, one
// optional chip picker — so it doesn't add to that.
//
// No TextFields → no keyboard toolbar, no NavigationStack wrapping
// needed (the swiftui-keyboard-toolbar-needs-navstack gotcha from
// commit 9d7ad88 doesn't apply).

import SwiftUI

struct OnboardingEraAffinityScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    /// True after the user taps "Pick a different cohort"; reveals the
    /// inline chip picker.
    @State private var showingPicker: Bool = false

    /// Pre-Continue selection. Mirrors draft.eraOverride so back-then-
    /// forward through the flow preserves the prior pick.
    @State private var selection: Selection = .accept

    private enum Selection: Equatable {
        case accept            // derived cohort
        case pick(EraCohort)   // user-chosen
        case skip              // weak prior, no override
    }

    /// Derived cohort from age. Nil when age is nil (the user skipped
    /// the about step) — in that case we still show the screen but the
    /// "accept derived" row is hidden and the default selection is
    /// .skip.
    private var derived: EraCohort? {
        EraAffinity.derivedCohort(forAge: draft.age)
    }

    /// Style for the derived cohort (when present), used for the
    /// subtitle + accept-row body.
    private var derivedStyle: EraStyle? {
        derived.map(EraAffinity.style(for:))
    }

    var body: some View {
        OnboardingScaffold(
            step: .eraAffinity,
            title: "Your training era.",
            subtitle: subtitleText,
            onNext: {
                commitSelection()
                onNext()
            },
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let derivedStyle {
                    OnboardingPickRow(
                        title: "Looks about right — \(derivedStyle.displayName.lowercased())",
                        subtitle: derivedStyle.narrativeBlurb,
                        selected: selection == .accept,
                        leading: "checkmark.seal",
                        action: {
                            selection = .accept
                            showingPicker = false
                        }
                    )
                }

                OnboardingPickRow(
                    title: "Pick a different era",
                    subtitle: "See the full list and choose the one that fits.",
                    selected: isPickSelection,
                    leading: "rectangle.stack",
                    action: {
                        showingPicker.toggle()
                        // If toggling on and we don't have a pick yet,
                        // default to the derived cohort (or first case).
                        if showingPicker, case .accept = selection {
                            let initial = derived ?? EraCohort.allCases.first!
                            selection = .pick(initial)
                        }
                    }
                )

                if showingPicker {
                    cohortPicker
                }

                OnboardingPickRow(
                    title: "No preference",
                    subtitle: "Skip this — the planner stays flexible.",
                    selected: selection == .skip,
                    leading: "minus.circle",
                    action: {
                        selection = .skip
                        showingPicker = false
                    }
                )
            }
        }
        .onAppear { hydrateSelection() }
    }

    // MARK: - Inline chip picker

    private var cohortPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnboardingSectionLabel(text: "Eras")
            WrappingFlow(spacing: 8) {
                ForEach(EraCohort.allCases) { cohort in
                    OnboardingChip(
                        label: EraAffinity.style(for: cohort).displayName,
                        selected: pickedCohort == cohort,
                        action: { selection = .pick(cohort) }
                    )
                }
            }
            if let style = pickedCohort.map(EraAffinity.style(for:)) {
                Text(style.narrativeBlurb)
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Subtitle

    private var subtitleText: String {
        if derivedStyle != nil {
            return "Most lifters absorb a training style from whoever they were reading or watching in their late teens. Confirm or pick a different fit."
        } else {
            return "Most lifters absorb a training style from whoever they were reading or watching in their late teens. (Skip 'About you' meant we can't guess — pick one or skip.)"
        }
    }

    // MARK: - Helpers

    private var isPickSelection: Bool {
        if case .pick = selection { return true }
        return false
    }

    private var pickedCohort: EraCohort? {
        if case .pick(let c) = selection { return c }
        return nil
    }

    private func hydrateSelection() {
        // Restore from a prior pass through the screen.
        if let raw = draft.eraOverride, let cohort = EraCohort(rawValue: raw) {
            if let derived, cohort == derived {
                selection = .accept
            } else {
                selection = .pick(cohort)
                showingPicker = true
            }
        } else {
            // No prior override. If age is unknown the derived cohort is
            // nil and the user has to pick or skip — default to skip
            // since that's the least presumptuous starting point.
            selection = derived == nil ? .skip : .accept
        }
    }

    private func commitSelection() {
        switch selection {
        case .accept:
            draft.eraOverride = derived?.rawValue
        case .pick(let cohort):
            draft.eraOverride = cohort.rawValue
        case .skip:
            draft.eraOverride = nil
        }
    }
}

#Preview("Has age") {
    @Previewable @State var draft: TrainingMemory = {
        var m = TrainingMemory()
        m.age = 33
        return m
    }()
    return OnboardingEraAffinityScreen(draft: $draft, onNext: {}, onBack: {})
}

#Preview("No age") {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingEraAffinityScreen(draft: $draft, onNext: {}, onBack: {})
}
