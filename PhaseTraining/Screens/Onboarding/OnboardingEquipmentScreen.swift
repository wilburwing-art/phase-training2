// OnboardingEquipmentScreen.swift — step 6 of 8.
// Multi-select equipment. Tapping "Bodyweight only" clears everything else
// (and vice versa) — they're mutually exclusive intents. Picking "Full gym"
// implies access to barbell + dumbbells + cables + bench but doesn't preselect
// them; the planner reads .fullGym as a wildcard at routine-pick time.

import SwiftUI

struct OnboardingEquipmentScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            step: .equipment,
            title: "What can you use?",
            subtitle: "Pick everything you have access to. We won't program around what you don't.",
            nextEnabled: !draft.equipment.isEmpty,
            onNext: onNext,
            onBack: onBack
        ) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Equipment.allCases) { eq in
                    EquipmentTile(
                        equipment: eq,
                        selected: draft.equipment.contains(eq),
                        action: { toggle(eq) }
                    )
                }
            }
        }
    }

    private func toggle(_ eq: Equipment) {
        if draft.equipment.contains(eq) {
            draft.equipment.removeAll { $0 == eq }
            return
        }
        // Mutual exclusion: bodyweight is alone; anything else removes bodyweight.
        if eq == .bodyweight {
            draft.equipment = [.bodyweight]
        } else {
            draft.equipment.removeAll { $0 == .bodyweight }
            draft.equipment.append(eq)
        }
    }
}

private struct EquipmentTile: View {
    let equipment: Equipment
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: equipment.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Color.accent : Color.ink2)
                    .frame(width: 22, alignment: .center)
                Text(equipment.label)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.accent : Color.line)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentWash : Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentBorder : Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingEquipmentScreen(draft: $draft, onNext: {}, onBack: {})
}
