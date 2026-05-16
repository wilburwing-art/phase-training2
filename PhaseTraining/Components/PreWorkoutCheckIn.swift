// PreWorkoutCheckIn.swift — chip row above the Today exercise list.
//
// Collapsed by default; tap a header chevron to expand. Captures everything
// the planner + future coach need before today's session: energy, soreness
// level + body areas, pain yes/no, time budget vs planned, equipment
// changed. On submit, appends a SorenessEntry to MemoryStore (one per call —
// the user can update by re-submitting; later calls supersede via date).

import SwiftUI

struct PreWorkoutCheckIn: View {
    @EnvironmentObject private var memoryStore: MemoryStore
    @State private var expanded = false
    @State private var energy: Energy? = nil
    @State private var soreness: Soreness? = nil
    @State private var pain: Bool? = nil
    @State private var time: TimeBudget? = nil
    @State private var equipmentChanged: Bool? = nil
    @State private var areas: Set<BodyArea> = []
    @State private var submittedAt: Date? = nil

    enum Energy: String, CaseIterable, Identifiable {
        case low, normal, high
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    enum Soreness: String, CaseIterable, Identifiable {
        case none, mild, high
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    enum TimeBudget: String, CaseIterable, Identifiable {
        case less, planned, more
        var id: String { rawValue }
        var label: String {
            switch self {
            case .less:    return "Less time"
            case .planned: return "On plan"
            case .more:    return "More time"
            }
        }
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
                    row("ENERGY",   chips: Energy.allCases,   selected: energy)   { energy = $0 }
                    row("SORENESS", chips: Soreness.allCases, selected: soreness) { soreness = $0 }
                    painRow
                    if soreness == .mild || soreness == .high {
                        areasRow
                    }
                    row("TIME",      chips: TimeBudget.allCases, selected: time) { time = $0 }
                    equipmentRow
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

    private func row<T: Identifiable & Equatable>(
        _ title: String,
        chips: [T],
        selected: T?,
        label labelFor: ((T) -> String)? = nil,
        onTap: @escaping (T) -> Void
    ) -> some View where T.ID == String {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 6) {
                ForEach(chips) { c in
                    chip(
                        text: labelFor?(c) ?? (c as? CustomStringConvertible).map { String(describing: $0) } ?? c.id.capitalized,
                        active: selected == c,
                        onTap: { onTap(c) }
                    )
                }
            }
        }
    }

    private var painRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PAIN")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 6) {
                chip(text: "No",  active: pain == false) { pain = false }
                chip(text: "Yes", active: pain == true)  { pain = true  }
            }
        }
    }

    private var areasRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHERE")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            FlowChips(items: BodyArea.allCases.map { $0.label }) { idx in
                let area = BodyArea.allCases[idx]
                if areas.contains(area) { areas.remove(area) } else { areas.insert(area) }
            } isActive: { idx in
                areas.contains(BodyArea.allCases[idx])
            }
        }
    }

    private var equipmentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EQUIPMENT")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 6) {
                chip(text: "Same",      active: equipmentChanged == false) { equipmentChanged = false }
                chip(text: "Different", active: equipmentChanged == true)  { equipmentChanged = true  }
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

    private var canSubmit: Bool {
        energy != nil && soreness != nil && pain != nil && time != nil && equipmentChanged != nil
    }

    private func submit() {
        let entry = SorenessEntry(
            date: Date(),
            energy: energy?.rawValue,
            soreness: soreness?.rawValue,
            pain: pain ?? false,
            areas: Array(areas).map(\.rawValue).sorted(),
            timeBudget: time.map(timeMinutes),
            equipmentChanged: equipmentChanged ?? false
        )
        memoryStore.update { mem in
            mem.soreness.append(entry)
        }
        submittedAt = entry.date
        withAnimation(.easeInOut(duration: 0.18)) { expanded = false }
    }

    private func timeMinutes(_ t: TimeBudget) -> Int {
        let planned = memoryStore.memory.sessionMinutes
        switch t {
        case .less:    return max(15, planned - 15)
        case .planned: return planned
        case .more:    return planned + 15
        }
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

// MARK: - Identifiable conformance helpers

extension PreWorkoutCheckIn.Energy: CustomStringConvertible {
    var description: String { label }
}
extension PreWorkoutCheckIn.Soreness: CustomStringConvertible {
    var description: String { label }
}
extension PreWorkoutCheckIn.TimeBudget: CustomStringConvertible {
    var description: String { label }
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
