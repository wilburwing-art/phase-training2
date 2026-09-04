// PlateCalculatorSheet.swift — target-weight → plate stack helper.
//
// Build 103. Standalone utility — the user enters a target weight, picks a
// bar weight, and the sheet shows the greedy plate stack per side plus the
// number of plates of each denomination needed. Pure math.
//
// Defaults to imperial because the imperial plate set (45/35/25/10/5/2.5) is
// what almost every US gym ships with, but flips to metric (25/20/15/10/5/
// 2.5/1.25) when the user's `usesImperial` is false. Bar weight defaults to
// 45 lb / 20 kg respectively.
//
// Storage: the last-used bar weight persists via @AppStorage so a specialty
// bar (e.g. 55 lb) survives re-opens. Target resets every open.

import SwiftUI

struct PlateCalculatorSheet: View {
    @EnvironmentObject private var memory: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetText: String = ""
    @State private var barText: String = ""
    @State private var imperial: Bool = true
    @FocusState private var targetFocused: Bool

    /// Last-used bar weight text, persisted across opens so a non-standard
    /// bar doesn't need re-entering every time.
    @AppStorage("plateCalculator.barText") private var savedBarText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        unitToggle
                        inputCard
                        if let result = calculate() {
                            resultCard(result)
                            barVisualization(result)
                        } else if !targetText.isEmpty {
                            errorCard
                        } else {
                            hintCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Plate calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            imperial = memory.memory.usesImperial
            if barText.isEmpty {
                barText = savedBarText.isEmpty
                    ? String(format: "%g", defaultBarWeight)
                    : savedBarText
            }
            targetFocused = true
        }
        .onChange(of: barText) { _, newValue in
            // Persist only parseable values so a half-typed entry doesn't
            // come back on the next open.
            if BodyMetrics.parseDecimalInput(newValue) != nil {
                savedBarText = newValue
            }
        }
    }

    // MARK: - Sections

    private var unitToggle: some View {
        HStack(spacing: 0) {
            unitPill(label: "LB", selected: imperial) { imperial = true }
            unitPill(label: "KG", selected: !imperial) { imperial = false }
        }
        .frame(maxWidth: 160)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func unitPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(selected ? Color.accentInk : Color.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color.accent : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputRow(
                label: "TARGET",
                text: $targetText,
                placeholder: "e.g. \(Int(defaultTarget))",
                unitLabel: unitSuffix,
                focused: $targetFocused
            )
            inputRow(
                label: "BAR",
                text: $barText,
                placeholder: String(format: "%g", defaultBarWeight),
                unitLabel: unitSuffix
            )
        }
        .cardSurface()
    }

    @ViewBuilder
    private func inputRow(
        label: String,
        text: Binding<String>,
        placeholder: String,
        unitLabel: String,
        focused: FocusState<Bool>.Binding? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 8) {
                let field = TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .font(.custom("JetBrainsMono-SemiBold", size: 22))
                    .foregroundStyle(Color.ink)
                if let focused {
                    field.focused(focused)
                } else {
                    field
                }
                Text(unitLabel)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func resultCard(_ result: PlateResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("PER SIDE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                if result.remainder > 0.01 {
                    Text(String(format: "%.1f %@ short", result.remainder, unitSuffix))
                        .styled(.micro)
                        .foregroundStyle(Color.danger)
                }
            }
            VStack(spacing: 8) {
                ForEach(result.perSide, id: \.plate) { row in
                    HStack(spacing: 12) {
                        plateGlyph(weight: row.plate)
                        Text(String(format: "%g %@", row.plate, unitSuffix))
                            .font(.custom("JetBrainsMono-SemiBold", size: 14))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text("× \(row.count)")
                            .font(.custom("JetBrainsMono-SemiBold", size: 16))
                            .foregroundStyle(Color.accent)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
            }
            Rectangle()
                .fill(Color.lineSoft)
                .frame(height: 0.5)
            HStack {
                Text("TOTAL ACHIEVED")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text(String(format: "%g %@", result.achieved, unitSuffix))
                    .font(.custom("JetBrainsMono-SemiBold", size: 16))
                    .foregroundStyle(result.remainder > 0.01 ? Color.ink2 : Color.accent)
            }
        }
        .cardSurface()
    }

    private func barVisualization(_ result: PlateResult) -> some View {
        let allPlates: [Double] = result.perSide.flatMap { row in
            Array(repeating: row.plate, count: row.count)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("BAR")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 1) {
                // Mirror so the bar reads center-out: largest plates outside,
                // matching how you'd actually load the bar.
                ForEach(Array(allPlates.reversed().enumerated()), id: \.offset) { _, p in
                    plateBar(weight: p)
                }
                Rectangle()
                    .fill(Color.ink2)
                    .frame(width: 40, height: 8)
                ForEach(Array(allPlates.enumerated()), id: \.offset) { _, p in
                    plateBar(weight: p)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .padding(.vertical, 8)
            .background(Color.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func plateGlyph(weight: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(plateColor(weight))
            Text(String(format: "%g", weight))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.accentInk)
        }
        .frame(width: 30, height: 30)
    }

    private func plateBar(weight: Double) -> some View {
        let h: CGFloat = {
            // 45/20 huge → 2.5/1.25 tiny. Imperial bar plates max at 45.
            let cap: Double = imperial ? 45 : 25
            return CGFloat(max(0.4, min(1.0, weight / cap))) * 64
        }()
        return Rectangle()
            .fill(plateColor(weight))
            .frame(width: 8, height: h)
            .overlay(
                Text(String(format: "%g", weight))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.accentInk)
                    .rotationEffect(.degrees(-90))
                    .frame(width: h)
            )
    }

    /// Color-code plates by weight tier so the bar visualization reads as
    /// "biggest plates on outside" at a glance. Roughly matches the
    /// IPF/IWF color convention.
    private func plateColor(_ weight: Double) -> Color {
        if imperial {
            switch weight {
            case 45...: return Color.accent
            case 35..<45: return Color.ok
            case 25..<35: return Color(red: 0.8, green: 0.6, blue: 0.4)
            case 10..<25: return Color.ink2
            default: return Color(red: 0.7, green: 0.7, blue: 0.7)
            }
        } else {
            switch weight {
            case 25...: return Color.accent
            case 20..<25: return Color.ok
            case 15..<20: return Color(red: 0.9, green: 0.7, blue: 0.4)
            case 10..<15: return Color.ink2
            default: return Color(red: 0.7, green: 0.7, blue: 0.7)
            }
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAN'T LOAD THIS")
                .styled(.micro)
                .foregroundStyle(Color.danger)
            Text("Target needs to be at least the bar weight. Empty bar is \(String(format: "%g", barWeight)) \(unitSuffix).")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW TO USE")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Text("Enter your target weight and we'll show the greedy plate stack, biggest plates outside. Using the standard \(imperial ? "45/35/25/10/5/2.5 lb" : "25/20/15/10/5/2.5/1.25 kg") plate set.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Math

    private var availablePlates: [Double] { PlateMath.standardPlates(imperial: imperial) }
    private var defaultBarWeight: Double { imperial ? 45 : 20 }
    private var defaultTarget: Double { imperial ? 135 : 60 }
    private var unitSuffix: String { imperial ? "lb" : "kg" }

    private var barWeight: Double {
        parseDouble(barText) ?? defaultBarWeight
    }

    private typealias PlateResult = PlateMath.Result
    private typealias PlateRow = PlateMath.Row

    /// Wrap the static math in the local input parsing — UI-side guards
    /// stay here, math sits in PlateMath for the tests to call directly.
    private func calculate() -> PlateResult? {
        guard let target = parseDouble(targetText) else { return nil }
        return PlateMath.calculate(target: target, bar: barWeight, plates: availablePlates)
    }

    private func parseDouble(_ raw: String) -> Double? {
        BodyMetrics.parseDecimalInput(raw)
    }
}

#Preview {
    let suite = "PlateCalculatorSheet.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PlateCalculatorSheet()
        .environmentObject(MemoryStore(defaults: defaults))
}
