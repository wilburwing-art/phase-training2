// SkiReadinessTestSheet.swift — log a pre-season ski test. Any subset of
// the four tests saves; a blank field is a test not run this time. The
// timed tests carry a "Time it" button: HoldTimerSheet counts up until Stop
// and writes the seconds into the field.

import SwiftUI

struct SkiReadinessTestSheet: View {
    /// A field the hold timer is running for.
    enum TimedField: String, Identifiable {
        case wallSit, balanceLeft, balanceRight
        var id: String { rawValue }

        var title: String {
            switch self {
            case .wallSit: return "Wall sit"
            case .balanceLeft: return "Balance, left leg"
            case .balanceRight: return "Balance, right leg"
            }
        }

        var capSeconds: Int? {
            self == .wallSit ? nil : SkiReadinessTest.balanceCapSeconds
        }
    }

    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var wallSitText = ""
    @State private var balanceLeftText = ""
    @State private var balanceRightText = ""
    @State private var hopsText = ""
    @State private var jumpText = ""
    @FocusState private var focused: Bool
    @State private var timerField: TimedField?

    private var imperial: Bool { store.memory.usesImperial }

    private func int(_ s: String) -> Int? {
        Int(s.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
    }

    private func balance(_ s: String) -> Int? {
        int(s).map { min($0, SkiReadinessTest.balanceCapSeconds) }
    }

    private var jumpCm: Double? {
        guard let v = BodyMetrics.parseDecimalInput(jumpText), v > 0 else { return nil }
        return imperial ? v * BodyMetrics.cmPerInch : v
    }

    private var draft: SkiReadinessTest {
        SkiReadinessTest(date: Date(),
                         wallSitSeconds: int(wallSitText),
                         balanceLeftSeconds: balance(balanceLeftText),
                         balanceRightSeconds: balance(balanceRightText),
                         lateralHops30s: int(hopsText),
                         broadJumpCm: jumpCm)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Run any of these before the season and again every few weeks. Leave a field blank to skip that test.")
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        field(label: "WALL SIT (SECONDS)",
                              how: "Back flat on the wall, thighs level. Hold until you can't.",
                              text: $wallSitText, id: "ski-test-wall-sit", timed: .wallSit)
                        field(label: "BALANCE, LEFT LEG (SECONDS)",
                              how: "Stand on the left foot, eyes closed. Stop when anything touches down. Max 60.",
                              text: $balanceLeftText, id: "ski-test-balance-left", timed: .balanceLeft)
                        field(label: "BALANCE, RIGHT LEG (SECONDS)",
                              how: "Same test on the right foot.",
                              text: $balanceRightText, id: "ski-test-balance-right", timed: .balanceRight)
                        field(label: "LATERAL HOPS (IN 30 SECONDS)",
                              how: "Feet together, hop side to side over a line. Count every landing.",
                              text: $hopsText, id: "ski-test-hops")
                        field(label: "BROAD JUMP (\(imperial ? "INCHES" : "CM"))",
                              how: "Two-foot standing jump. Measure toe line to the back of the nearer heel.",
                              text: $jumpText, id: "ski-test-broad-jump", decimal: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Ski readiness test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(Color.accent)
                        .disabled(draft.isEmpty)
                        .accessibilityIdentifier("ski-test-save")
                }
                // Number pads have no return key; this is the way out.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                        .foregroundStyle(Color.accent)
                        .accessibilityIdentifier("ski-test-keyboard-done")
                }
            }
        }
        .sheet(item: $timerField) { field in
            HoldTimerSheet(exerciseName: field.title, capSeconds: field.capSeconds) { seconds in
                guard seconds > 0 else { return }
                text(for: field).wrappedValue = String(seconds)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    private func text(for field: TimedField) -> Binding<String> {
        switch field {
        case .wallSit: return $wallSitText
        case .balanceLeft: return $balanceLeftText
        case .balanceRight: return $balanceRightText
        }
    }

    private func field(label: String, how: String, text: Binding<String>, id: String,
                       decimal: Bool = false, timed: TimedField? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Text(how)
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("-", text: text)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                    .font(.scaled("JetBrainsMono-SemiBold", size: 20))
                    .foregroundStyle(Color.ink)
                    .padding(12)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .focused($focused)
                    .accessibilityIdentifier(id)
                if let timed {
                    Button {
                        focused = false
                        timerField = timed
                    } label: {
                        Label("Time it", systemImage: "stopwatch")
                            .styled(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .foregroundStyle(Color.accent)
                    .accessibilityIdentifier("\(id)-timer")
                }
            }
        }
    }

    private func save() {
        let test = draft
        guard !test.isEmpty else { return }
        store.update { $0.skiReadinessTests.append(test) }
        dismiss()
    }
}
