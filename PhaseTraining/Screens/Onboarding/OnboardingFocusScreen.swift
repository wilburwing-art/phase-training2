// OnboardingFocusScreen.swift — multi-select with primary marker.
//
// draft.focuses is an ordered list; first entry is the primary the planner
// uses for shape resolution. Tapping a focus toggles it in/out; tapping
// a non-primary picked focus while the "set as primary" flow is implicit
// — primary is always focuses[0], so re-ordering happens via the second
// "primary?" picker that appears once 2+ are selected.

import SwiftUI

struct OnboardingFocusScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            step: .focus,
            title: "What's the goal?",
            subtitle: "Pick anything that matters — you can stack a few.",
            nextEnabled: !draft.focuses.isEmpty,
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 16) {
                OnboardingSectionLabel(text: "Focuses")
                VStack(spacing: 10) {
                    ForEach(PrimaryFocus.allCases) { focus in
                        OnboardingPickRow(
                            title: focus.label,
                            subtitle: focus.subtitle,
                            selected: draft.focuses.contains(focus),
                            action: { toggle(focus) },
                            a11yId: "onboarding-focus-\(focus.id)"
                        )
                    }
                }

                if draft.focuses.count > 1 {
                    Divider().background(Color.lineSoft).padding(.vertical, 4)
                    OnboardingSectionLabel(text: "Which is primary?")
                    Text("This is the one we plan around first.")
                        .styled(.body)
                        .foregroundStyle(Color.ink3)
                    VStack(spacing: 8) {
                        ForEach(draft.focuses) { focus in
                            OnboardingPickRow(
                                title: focus.label,
                                subtitle: nil,
                                selected: draft.focuses.first == focus,
                                action: { setPrimary(focus) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ focus: PrimaryFocus) {
        if let idx = draft.focuses.firstIndex(of: focus) {
            draft.focuses.remove(at: idx)
        } else {
            draft.focuses.append(focus)
        }
    }

    private func setPrimary(_ focus: PrimaryFocus) {
        guard let idx = draft.focuses.firstIndex(of: focus), idx != 0 else { return }
        draft.focuses.remove(at: idx)
        draft.focuses.insert(focus, at: 0)
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingFocusScreen(draft: $draft, onNext: {}, onBack: {})
}
