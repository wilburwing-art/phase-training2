// PreWorkoutCheckIn.swift — chip row above the Today exercise list.
//
// Build 88: simplified to two fields — energy + sore areas. Removed pain
// (redundant with areas), soreness level (also redundant — areas count is
// the proxy), time budget (covered by editing the workout directly), and
// equipment-changed (covered by the picker's environment filter). The
// SorenessEntry model still has those fields so old data renders correctly
// in the coach context; new entries just don't set them.
//
// Collapsed by default; tap to expand. Re-pulls today's entry on appear so
// closing the app doesn't reset the "LOGGED" status.

import SwiftUI

struct PreWorkoutCheckIn: View {
    @EnvironmentObject private var memoryStore: MemoryStore
    @State private var expanded = false
    @State private var energy: Energy? = nil
    @State private var areas: Set<BodyArea> = []
    @State private var submittedAt: Date? = nil

    enum Energy: String, CaseIterable, Identifiable {
        case low, normal, high
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    enum BodyArea: String, CaseIterable, Identifiable {
        case knees, lowBack = "low back", shoulders, hips, neck, wrists, elbows, ankles
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    energyRow
                    areasRow
                    submitButton
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear(perform: rehydrateFromMemory)
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            HStack {
                Text(headerTitle)
                    .styled(.micro)
                    .foregroundStyle(submittedAt != nil ? Color.accent : Color.ink3)
                Spacer()
                if submittedAt != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var headerTitle: String {
        submittedAt != nil ? "PRE-WORKOUT · LOGGED" : "PRE-WORKOUT CHECK-IN"
    }

    // MARK: - Rows

    private var energyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENERGY")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 6) {
                ForEach(Energy.allCases) { e in
                    chip(text: e.label, active: energy == e) { energy = e }
                }
            }
        }
    }

    private var areasRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("SORE AREAS")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text("(optional)")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3.opacity(0.6))
            }
            FlowChips(items: BodyArea.allCases.map { $0.label }) { idx in
                let area = BodyArea.allCases[idx]
                if areas.contains(area) { areas.remove(area) } else { areas.insert(area) }
            } isActive: { idx in
                areas.contains(BodyArea.allCases[idx])
            }
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text(submittedAt == nil ? "Save check-in" : "Update")
                .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                .foregroundStyle(Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(canSubmit ? Color.accent : Color.accentDim)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    /// Only energy is required — sore areas are optional (empty = nothing sore).
    private var canSubmit: Bool { energy != nil }

    private func submit() {
        let entry = SorenessEntry(
            date: Date(),
            energy: energy?.rawValue,
            // soreness level / pain / timeBudget / equipmentChanged left at
            // their defaults — see file header for why we cut them.
            areas: Array(areas).map(\.rawValue).sorted()
        )
        memoryStore.update { mem in
            mem.soreness.append(entry)
        }
        submittedAt = entry.date
        withAnimation(.easeInOut(duration: 0.18)) { expanded = false }
    }

    /// Re-pick up today's entry from memory so closing/reopening the app
    /// doesn't reset the "LOGGED" status. Match by Calendar.startOfDay so a
    /// check-in submitted earlier in the day still counts. Only restores
    /// the 2 fields we still collect — older multi-field entries are
    /// honored too, but unsurfaced fields stay in the model untouched.
    private func rehydrateFromMemory() {
        let cal = Calendar.current
        guard let entry = memoryStore.memory.soreness.last(where: {
            cal.isDate($0.date, inSameDayAs: Date())
        }) else { return }
        submittedAt = entry.date
        energy = entry.energy.flatMap(Energy.init(rawValue:))
        areas = Set(entry.areas.compactMap(BodyArea.init(rawValue:)))
    }

    // MARK: - Chip primitive

    private func chip(text: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(text)
                .font(.monoXS)
                .foregroundStyle(active ? Color.accentInk : Color.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? Color.accent : Color.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowChips

/// Wrapping chip row used by the body-areas selector. Lays out into rows
/// without needing a separate FlowLayout import — we wrap manually with a
/// LazyVGrid of variable columns.
private struct FlowChips: View {
    let items: [String]
    let onTap: (Int) -> Void
    let isActive: (Int) -> Bool

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 70), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button { onTap(idx) } label: {
                    Text(item)
                        .font(.monoXS)
                        .foregroundStyle(isActive(idx) ? Color.accentInk : Color.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isActive(idx) ? Color.accent : Color.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    let suite = "PreWorkout.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PreWorkoutCheckIn()
        .environmentObject(MemoryStore(defaults: defaults))
        .padding()
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
