// PlanAssumptionsRow.swift — the "here's what we guessed" strip under the Week
// header, and the shared editor host behind it.
//
// The onboarding gate only asks sport + season (see
// docs/PLAN-onboarding-as-tutorial.md). Everything else the planner needs runs
// on a default until the user says otherwise, and this strip is where those
// defaults are admitted out loud instead of quietly shaping the week.
//
// Each chip does three jobs at once:
//   1. Tells the user what the plan assumed ("3 lift days · 45 min").
//   2. Opens the REAL Profile editor for that field — not an onboarding copy of
//      it — so correcting an assumption is also the moment the user learns
//      where that setting permanently lives.
//   3. Retires itself: every editor stamps `markStated` on write.
//
// The strip disappears entirely once nothing is assumed, so a settled user
// never sees it again.

import SwiftUI

struct PlanAssumptionsRow: View {
    @EnvironmentObject private var store: MemoryStore

    /// Which editor is open. Nil = none.
    @State private var editing: ProfileField?

    var body: some View {
        let assumed = store.memory.assumedFields
        if !assumed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ASSUMED — TAP TO CHANGE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(assumed) { field in
                            chip(field)
                        }
                    }
                    .padding(.horizontal, 1)   // keeps the stroke off the clip edge
                }
            }
            .accessibilityIdentifier("plan-assumptions-row")
            .sheet(item: $editing) { field in
                ProfileFieldEditorHost(field: field)
                    .environmentObject(store)
            }
        }
    }

    private func chip(_ field: ProfileField) -> some View {
        Button {
            editing = field
        } label: {
            HStack(spacing: 6) {
                Image(systemName: field.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink3)
                Text(store.memory.assumptionSummary(for: field))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    // Dashed, so an assumption reads as provisional at a glance
                    // rather than as a setting someone chose.
                    .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    .foregroundStyle(Color.line)
            )
            .clipShape(RoundedRectangle(cornerRadius: 999))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assumption-chip-\(field.rawValue)")
        .accessibilityLabel("\(field.label): \(store.memory.assumptionSummary(for: field)), assumed. Tap to change.")
    }
}

// MARK: - Editor host

/// Maps a `ProfileField` to the Profile editor that owns it, so the assumption
/// chips and the setup checklist both route to the same place the Profile tab
/// does. One switch, one set of editors — the whole point of the exercise is
/// that there is no second implementation.
///
/// `.availability` has no sheet of its own on Profile (it's two rows with inline
/// numeric alerts), so it gets a small editor here rather than a fourth copy of
/// the stepper UI.
struct ProfileFieldEditorHost: View {
    let field: ProfileField
    @EnvironmentObject private var store: MemoryStore

    var body: some View {
        switch field {
        case .equipment:    EquipmentEditorSheet().environmentObject(store)
        case .experience:   ExperienceEditorSheet().environmentObject(store)
        case .availability: AvailabilityEditorSheet().environmentObject(store)
        }
    }
}

// MARK: - Availability editor

/// Session length + lift days. Profile edits these through two inline numeric
/// alerts on its own rows; this is the sheet form the chips and the checklist
/// open. Both paths write the same fields and both stamp `.availability`.
struct AvailabilityEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    private let minuteBounds = TrainingConstraints.sessionMinutesUIRange
    private let liftBounds = TrainingConstraints.liftDaysRange
    private let minuteStep = 15

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        stepper(
                            title: "SESSION LENGTH",
                            value: "\(store.memory.sessionMinutes)",
                            unit: "MIN",
                            footnote: "Most users land between 30 and 60 min.",
                            a11y: "availability-minutes",
                            onMinus: { adjustMinutes(-minuteStep) },
                            onPlus: { adjustMinutes(minuteStep) }
                        )
                        stepper(
                            title: "LIFT DAYS PER WEEK",
                            value: "\(store.memory.liftDaysPerWeek)",
                            unit: store.memory.liftDaysPerWeek == 1 ? "DAY" : "DAYS",
                            footnote: "0 = no lift slots. Capped at the days you have free.",
                            a11y: "availability-lift-days",
                            onMinus: { adjustLifts(-1) },
                            onPlus: { adjustLifts(1) }
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Schedule")
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

    @ViewBuilder
    private func stepper(title: String, value: String, unit: String,
                         footnote: String, a11y: String,
                         onMinus: @escaping () -> Void,
                         onPlus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 0) {
                stepButton("minus", action: onMinus, a11y: "\(a11y)-minus")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.custom("JetBrainsMono-SemiBold", size: 30))
                        .foregroundStyle(Color.ink)
                    Text(unit)
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                .accessibilityIdentifier(a11y)
                Spacer(minLength: 0)
                stepButton("plus", action: onPlus, a11y: "\(a11y)-plus")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(footnote)
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void, a11y: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 40, height: 40)
                .background(Color.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(a11y)
    }

    private func adjustMinutes(_ delta: Int) {
        store.update { mem in
            let next = mem.sessionMinutes + delta
            mem.sessionMinutes = min(max(next, minuteBounds.lowerBound), minuteBounds.upperBound)
            mem.markStated(.availability)
        }
    }

    private func adjustLifts(_ delta: Int) {
        store.update { mem in
            let next = mem.liftDaysPerWeek + delta
            mem.liftDaysPerWeek = min(max(next, liftBounds.lowerBound), liftBounds.upperBound)
            mem.markStated(.availability)
        }
    }
}
