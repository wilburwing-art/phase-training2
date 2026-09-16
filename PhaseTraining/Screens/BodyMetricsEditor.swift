// BodyMetricsEditor.swift — height + weight editor, extracted from the
// deleted OnboardingAboutScreen (c666ade orphaned the type: AboutYouEditorSheet
// still calls it). Extracting to its own file also closes the 08-23 backlog
// item that flagged the editor "living inside an onboarding step file."

import SwiftUI

/// Typeable editor for height + weight. Renders in the user's unit system
/// (`draft.usesImperial`) but mutates the underlying metric storage. All
/// fields optional — clear buttons appear when set.
///
/// Each field uses a local @State string mirror committed to `draft` on
/// focus loss. Parses + clamps to sane ranges; empty input = "skip".
struct BodyMetricsEditor: View {
    @Binding var draft: TrainingMemory

    private let minHeightCm = 120
    private let maxHeightCm = 230
    private let minWeightKg = 30.0
    private let maxWeightKg = 250.0

    // Local mirrors. Single source per visible field. Imperial height uses
    // two mirrors (feet + inches); metric uses one (cm). Weight always uses
    // one mirror (the unit changes but the field count doesn't).
    @State private var heightCmText: String = ""
    @State private var heightFeetText: String = ""
    @State private var heightInchesText: String = ""
    @State private var weightText: String = ""

    @FocusState private var focus: Field?

    enum Field: Hashable { case heightCm, heightFeet, heightInches, weight }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heightRow
            weightRow
        }
        // Tapping the editor's empty space (between rows, around the labels)
        // dismisses the keyboard — covers cases where this view is hosted
        // outside a NavigationStack (the .toolbar Done below silently no-ops
        // there). Real fields and buttons still capture their own taps first.
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
        .onAppear(perform: syncMirrors)
        .onChange(of: draft.heightCm) { _, _ in if !isAnyHeightFieldFocused { syncHeightMirrors() } }
        .onChange(of: draft.weightKg) { _, _ in if focus != .weight { syncWeightMirror() } }
        // When the user toggles imperial/metric mid-edit, first commit the
        // focused field's pending text — the height TextFields are about to
        // be swapped (imperial ↔ metric), and resyncing the mirrors below
        // would silently drop uncommitted typing before the focus-loss
        // commit ever fires. Weight text is parsed in the OLD units (what
        // the user was typing in). Focus then clears so it can't point at a
        // field that no longer exists; refresh the mirrors so the new field
        // set shows the right value.
        .onChange(of: draft.usesImperial) { wasImperial, _ in
            switch focus {
            case .heightCm:     commitHeightCm()
            case .heightFeet, .heightInches: commitHeightImperial()
            case .weight:       commitWeight(asImperial: wasImperial)
            case nil:           break
            }
            focus = nil
            syncMirrors()
        }
        .onChange(of: focus) { old, new in
            // Commit whichever field just lost focus.
            switch old {
            case .heightCm:     commitHeightCm()
            case .heightFeet, .heightInches: commitHeightImperial()
            case .weight:       commitWeight(asImperial: draft.usesImperial)
            case nil:           break
            }
            _ = new // touch to satisfy old-warning, focus state is the live tracker
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .foregroundStyle(Color.accent)
            }
        }
    }

    private var isAnyHeightFieldFocused: Bool {
        focus == .heightCm || focus == .heightFeet || focus == .heightInches
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
                    Button("Clear") {
                        draft.heightCm = nil
                        heightCmText = ""
                        heightFeetText = ""
                        heightInchesText = ""
                    }
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                }
            }
            if draft.usesImperial {
                imperialHeightFields
            } else {
                metricHeightField
            }
        }
    }

    private var imperialHeightFields: some View {
        HStack(spacing: 10) {
            inputCard(border: focus == .heightFeet) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("—", text: $heightFeetText)
                        .focused($focus, equals: .heightFeet)
                        .keyboardType(.numberPad)
                        .submitLabel(.next)
                        .onSubmit { focus = .heightInches }
                        .font(.scaled("JetBrainsMono-SemiBold", size: 26))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text("FT")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
            }
            inputCard(border: focus == .heightInches) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("—", text: $heightInchesText)
                        .focused($focus, equals: .heightInches)
                        .keyboardType(.numberPad)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                        .font(.scaled("JetBrainsMono-SemiBold", size: 26))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text("IN")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private var metricHeightField: some View {
        inputCard(border: focus == .heightCm) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("—", text: $heightCmText)
                    .focused($focus, equals: .heightCm)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                    .font(.scaled("JetBrainsMono-SemiBold", size: 26))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text("CM")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
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
                    Button("Clear") {
                        draft.weightKg = nil
                        weightText = ""
                    }
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                }
            }
            inputCard(border: focus == .weight) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("—", text: $weightText)
                        .focused($focus, equals: .weight)
                        .keyboardType(.decimalPad)
                        .font(.scaled("JetBrainsMono-SemiBold", size: 26))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text(draft.usesImperial ? "LB" : "KG")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    // MARK: - Shared chrome

    private func inputCard<C: View>(border focused: Bool, @ViewBuilder content: () -> C) -> some View {
        content()
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? Color.accent : Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Commit + sync

    private func syncMirrors() {
        syncHeightMirrors()
        syncWeightMirror()
    }

    private func syncHeightMirrors() {
        if let cm = draft.heightCm {
            heightCmText = String(cm)
            let (f, i) = BodyMetrics.cmToFeetInches(cm)
            heightFeetText = String(f)
            heightInchesText = String(i)
        } else {
            heightCmText = ""
            heightFeetText = ""
            heightInchesText = ""
        }
    }

    private func syncWeightMirror() {
        if let kg = draft.weightKg {
            if draft.usesImperial {
                let lb = BodyMetrics.kgToLb(kg)
                weightText = String(format: "%.1f", lb)
            } else {
                weightText = String(format: "%.1f", kg)
            }
        } else {
            weightText = ""
        }
    }

    private func commitHeightCm() {
        let trimmed = heightCmText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let parsed = Int(trimmed) else {
            draft.heightCm = nil
            heightCmText = ""
            return
        }
        let clamped = min(max(parsed, minHeightCm), maxHeightCm)
        draft.heightCm = clamped
        heightCmText = String(clamped)
    }

    private func commitHeightImperial() {
        // Empty BOTH fields = skip. Empty one of them = treat as 0 so the
        // user can enter "6 ft" without explicitly typing "0 in".
        let f = heightFeetText.trimmingCharacters(in: .whitespaces)
        let i = heightInchesText.trimmingCharacters(in: .whitespaces)
        if f.isEmpty, i.isEmpty {
            draft.heightCm = nil
            heightFeetText = ""
            heightInchesText = ""
            return
        }
        let feet = Int(f) ?? 0
        let inches = Int(i) ?? 0
        let cm = BodyMetrics.feetInchesToCm(feet: feet, inches: inches)
        let clamped = min(max(cm, minHeightCm), maxHeightCm)
        draft.heightCm = clamped
        // Reflect the clamped value so the user sees what we stored.
        let (rf, ri) = BodyMetrics.cmToFeetInches(clamped)
        heightFeetText = String(rf)
        heightInchesText = String(ri)
    }

    /// `asImperial` says which units the typed text is in — callers pass the
    /// unit system that was active WHILE the user typed, which differs from
    /// `draft.usesImperial` when committing across a unit toggle.
    private func commitWeight(asImperial: Bool) {
        let trimmed = weightText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".") // accept European-decimal commas
        guard !trimmed.isEmpty, let parsed = Double(trimmed) else {
            draft.weightKg = nil
            weightText = ""
            return
        }
        let kg = asImperial ? BodyMetrics.lbToKg(parsed) : parsed
        // One-decimal precision keeps the JSON tidy.
        let rounded = (kg * 10).rounded() / 10
        let clamped = min(max(rounded, minWeightKg), maxWeightKg)
        draft.weightKg = clamped
        // Reflect the canonical value back into the field.
        syncWeightMirror()
    }
}

