// EquipmentEditorSheet.swift — equipment tier picker + custom-equipment chips.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass.

import SwiftUI

struct EquipmentEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("EQUIPMENT")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(EquipmentTier.allCases) { tier in
                                Button {
                                    selectTier(tier)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: tier.icon)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(currentTier == tier ? Color.accent : Color.ink2)
                                        Text(tier.label)
                                            .styled(.body)
                                            .foregroundStyle(Color.ink)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(currentTier == tier ? Color.accentWash : Color.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(currentTier == tier ? Color.accentBorder : Color.line, lineWidth: 0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if currentTier == .custom {
                            Text("PICK WHAT YOU HAVE")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                                .padding(.top, 6)
                            WrappingFlow(spacing: 8) {
                                ForEach(Equipment.allCases.filter { $0 != .fullGym }) { eq in
                                    OnboardingChip(
                                        label: eq.label,
                                        selected: store.memory.equipment.contains(eq),
                                        action: { toggleCustomEquipment(eq) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    private var currentTier: EquipmentTier {
        let eq = store.memory.equipment
        if eq == [.bodyweight] { return .bodyweight }
        if eq == [.dumbbells]  { return .dumbbells  }
        if eq == [.fullGym]    { return .fullGym    }
        return .custom
    }

    private func selectTier(_ tier: EquipmentTier) {
        store.update { mem in
            switch tier {
            case .bodyweight: mem.equipment = [.bodyweight]
            case .dumbbells:  mem.equipment = [.dumbbells]
            case .fullGym:    mem.equipment = [.fullGym]
            case .custom:
                if currentTier != .custom {
                    mem.equipment = [.bodyweight, .dumbbells]
                }
            }
        }
    }

    private func toggleCustomEquipment(_ eq: Equipment) {
        store.update { mem in
            if let idx = mem.equipment.firstIndex(of: eq) {
                mem.equipment.remove(at: idx)
            } else {
                mem.equipment.append(eq)
            }
        }
    }
}
