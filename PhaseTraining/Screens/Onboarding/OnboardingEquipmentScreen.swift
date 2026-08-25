// OnboardingEquipmentScreen.swift — tier-based with optional custom expansion.
//
// Top: 4 preset cards (Body Weight, Dumbbells, Full Commercial Gym, Custom).
// Tapping a preset writes the canonical equipment array. Custom expands an
// inline chip cloud with the granular Equipment options for fine control.
//
// Underlying data (draft.equipment: [Equipment]) is unchanged — the planner
// still reads from that array. The 4 presets are pure UI sugar that map the
// common cases.

import SwiftUI

struct OnboardingEquipmentScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void
    /// The tier the user explicitly picked; see `currentTier`.
    @State private var tierSelection: EquipmentTier?

    var body: some View {
        OnboardingScaffold(
            step: .equipment,
            title: "What can you use?",
            subtitle: "Pick a preset or go custom.",
            nextEnabled: !draft.equipment.isEmpty,
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(EquipmentTier.allCases) { tier in
                        TierCard(
                            tier: tier,
                            selected: currentTier == tier,
                            action: { selectTier(tier) }
                        )
                    }
                }

                if currentTier == .custom {
                    Divider().background(Color.lineSoft)
                    OnboardingSectionLabel(text: "Pick what you have")
                    WrappingFlow(spacing: 8) {
                        ForEach(Equipment.allCases.filter { $0 != .fullGym }) { eq in
                            OnboardingChip(
                                label: eq.label,
                                selected: draft.equipment.contains(eq),
                                action: { toggleCustom(eq) }
                            )
                        }
                    }
                }
            }
        }
    }

    /// Same collapse bug as EquipmentEditorSheet: derived by exact-matching
    /// single-element arrays, so from Custom with an empty cloud the FIRST chip
    /// tap made equipment == [.bodyweight], flipped the tier, and the custom
    /// grid vanished under the user mid-interaction. Explicit state instead.
    private var currentTier: EquipmentTier {
        tierSelection ?? EquipmentEditorSheet.inferredTier(from: draft.equipment)
    }

    private func selectTier(_ tier: EquipmentTier) {
        tierSelection = tier
        switch tier {
        case .bodyweight: draft.equipment = [.bodyweight]
        case .dumbbells:  draft.equipment = [.dumbbells]
        case .fullGym:    draft.equipment = [.fullGym]
        case .custom:
            // Drop sentinel-only selections (they're full-tier picks); start the
            // user with an empty cloud so they're explicitly choosing.
            if draft.equipment == [.bodyweight] || draft.equipment == [.fullGym] {
                draft.equipment = []
            }
            // For .dumbbells → keep the dumbbell as a starting point.
        }
    }

    private func toggleCustom(_ eq: Equipment) {
        // Editing chips keeps us in Custom no matter what the array looks like
        // between taps — including the empty and single-element states that
        // used to collapse the section.
        tierSelection = .custom
        if let idx = draft.equipment.firstIndex(of: eq) {
            draft.equipment.remove(at: idx)
        } else {
            // Custom tier shouldn't include the bodyweight sentinel mixed with real gear.
            draft.equipment.removeAll { $0 == .bodyweight || $0 == .fullGym }
            draft.equipment.append(eq)
        }
    }
}

// MARK: - Tier model

enum EquipmentTier: String, CaseIterable, Identifiable {
    case bodyweight, dumbbells, fullGym, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .bodyweight: return "Body Weight"
        case .dumbbells:  return "Dumbbells"
        case .fullGym:    return "Full Commercial Gym"
        case .custom:     return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .bodyweight: return "Nothing required"
        case .dumbbells:  return "Plus whatever's around"
        case .fullGym:    return "Bars, racks, machines, cables"
        case .custom:     return "Pick exactly what you have"
        }
    }

    var icon: String {
        switch self {
        case .bodyweight: return "figure.walk"
        case .dumbbells:  return "dumbbell.fill"
        case .fullGym:    return "building.2.fill"
        case .custom:     return "slider.horizontal.3"
        }
    }
}

private struct TierCard: View {
    let tier: EquipmentTier
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: tier.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? Color.accent : Color.ink2)
                Text(tier.label)
                    .styled(.displayS)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tier.subtitle)
                    .styled(.body)
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(selected ? Color.accentWash : Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.accentBorder : Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-equip-\(tier.rawValue)")
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingEquipmentScreen(draft: $draft, onNext: {}, onBack: {})
}
