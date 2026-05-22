// SorenessCheckInSheet.swift — modal pre-workout body check.
//
// Surfaces from the Today tab via a header-adjacent "How sore are you
// today?" pill. Captures the three signals SorenessEntry already models:
//   energy   ("low" | "normal" | "high")
//   soreness ("none" | "mild" | "high")  — overall, single severity
//   areas    ([String])                   — multi-select MuscleBucket slugs
//                                          (chest/back/quads/...); pre-build-107
//                                          this was joints (knee/shoulder/...).
//
// Replaces the inline PreWorkoutCheckIn card that lived on Today pre-build-99.
// Same SorenessEntry append path through MemoryStore.update; the per-day
// rehydrate behavior (latest entry for today pre-fills the form) is
// preserved so re-opening doesn't double-log.
//
// Per-muscle severity (a map of muscle slug → 0..3) is NOT supported by
// SorenessEntry today — flagging it as a Stream B schema extension.

import SwiftUI

struct SorenessCheckInSheet: View {
    let onDone: () -> Void

    @EnvironmentObject private var memoryStore: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var energy: String? = nil
    @State private var severity: String? = nil
    @State private var areas: Set<String> = []
    @State private var existingEntryIndex: Int? = nil

    // MARK: - Catalogs

    private static let energyOptions: [(value: String, label: String)] = [
        ("low",    "Low"),
        ("normal", "Normal"),
        ("high",   "High"),
    ]

    private static let severityOptions: [(value: String, label: String)] = [
        ("none", "None"),
        ("mild", "Mild"),
        ("high", "High"),
    ]

    /// Muscle groups the user can flag as sore. DOMS lives in muscles, so we
    /// surface the same 11-bucket catalog the picker / filters / progress
    /// chips use (see `MuscleBucket`). The post-workout hurt list still uses
    /// joint-level vocab — that's pain, this is soreness.
    private static let areaOptions: [(slug: String, label: String)] =
        MuscleBucket.allCases.map { ($0.rawValue, $0.label) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        energySection
                        severitySection
                        areasSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("How sore are you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { skip() }
                        .foregroundStyle(Color.ink2)
                        .accessibilityIdentifier("soreness-skip")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(canSave ? Color.accent : Color.ink3)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("soreness-save")
                }
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear(perform: rehydrateFromMemory)
    }

    // MARK: - Sections

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ENERGY")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 6) {
                ForEach(Self.energyOptions, id: \.value) { opt in
                    chip(label: opt.label, active: energy == opt.value) {
                        energy = (energy == opt.value) ? nil : opt.value
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("soreness-energy-\(opt.value)")
                }
            }
        }
    }

    private var severitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OVERALL SORENESS")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 6) {
                ForEach(Self.severityOptions, id: \.value) { opt in
                    chip(label: opt.label, active: severity == opt.value) {
                        severity = (severity == opt.value) ? nil : opt.value
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("soreness-severity-\(opt.value)")
                }
            }
        }
    }

    private var areasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("SORE MUSCLES")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text("(optional)")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3.opacity(0.6))
            }
            let columns = [GridItem(.adaptive(minimum: 100), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Self.areaOptions, id: \.slug) { opt in
                    chip(label: opt.label, active: areas.contains(opt.slug)) {
                        toggleArea(opt.slug)
                    }
                    .accessibilityIdentifier("soreness-area-\(opt.slug)")
                }
            }
        }
    }

    // MARK: - Actions

    /// Energy is the only required field — areas + severity are optional.
    /// Matches the prior PreWorkoutCheckIn rule so the coach signal stays
    /// consistent ("show me a recent entry" = "show me any energy log").
    private var canSave: Bool { energy != nil }

    private func toggleArea(_ area: String) {
        if areas.contains(area) { areas.remove(area) }
        else                    { areas.insert(area) }
    }

    private func save() {
        guard canSave else { return }
        let entry = SorenessEntry(
            date: Date(),
            energy: energy,
            soreness: severity,
            pain: false,
            areas: Array(areas).sorted(),
            timeBudget: nil,
            equipmentChanged: false
        )
        memoryStore.update { mem in
            // Replace today's existing entry if we rehydrated from one, so
            // re-opening the sheet within the same day edits in place
            // instead of appending duplicates.
            if let idx = existingEntryIndex, mem.soreness.indices.contains(idx) {
                mem.soreness[idx] = entry
            } else {
                mem.soreness.append(entry)
            }
        }
        dismiss()
        onDone()
    }

    private func skip() {
        dismiss()
        onDone()
    }

    /// Pre-fill from today's most recent entry. Lets the sheet act as an
    /// edit-in-place surface within a single calendar day; only one
    /// SorenessEntry per day stays canonical.
    private func rehydrateFromMemory() {
        let cal = Calendar.current
        let today = Date()
        let entries = memoryStore.memory.soreness
        guard let idx = entries.lastIndex(where: { cal.isDate($0.date, inSameDayAs: today) }) else {
            return
        }
        let entry = entries[idx]
        existingEntryIndex = idx
        energy = entry.energy
        severity = entry.soreness
        areas = Set(entry.areas)
    }

    // MARK: - Chip primitive

    private func chip(label: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .foregroundStyle(active ? Color.accentInk : Color.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(active ? Color.accent : Color.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(active ? Color.clear : Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    let suite = "SorenessCheckIn.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return Color.bg.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SorenessCheckInSheet(onDone: {})
                .environmentObject(MemoryStore(defaults: defaults))
        }
        .preferredColorScheme(.dark)
}
