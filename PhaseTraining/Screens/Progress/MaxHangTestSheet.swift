// MaxHangTestSheet.swift — log a max hang: added load on a 20mm edge for 10s.

import SwiftUI

struct MaxHangTestSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss
    /// Added load in the lifter's unit; negative for assisted.
    @State private var addedText = ""
    @State private var bodyText = ""
    @FocusState private var focused: Bool

    private var imperial: Bool { store.memory.usesImperial }
    private var unit: String { imperial ? "lb" : "kg" }
    private func toKg(_ v: Double) -> Double { imperial ? BodyMetrics.lbToKg(v) : v }
    private func parse(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    private var bodyKg: Double? { store.memory.currentBodyKg ?? parse(bodyText).map(toKg) }

    private var preview: MaxHangTest? {
        guard let added = parse(addedText), let body = bodyKg, body > 0 else { return nil }
        return MaxHangTest(date: Date(), addedKg: toKg(added), bodyKg: body)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Hang a 20mm edge for 10 seconds with the most added weight you can hold. Use a negative number for assistance.")
                        .styled(.body)
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    field(label: "ADDED WEIGHT (\(unit.uppercased()))", text: $addedText, id: "max-hang-added")
                    if store.memory.currentBodyKg == nil {
                        field(label: "BODY WEIGHT (\(unit.uppercased()))", text: $bodyText, id: "max-hang-body")
                    }
                    if let preview {
                        Text(preview.percentLabel)
                            .font(.scaled("JetBrainsMono-SemiBold", size: 20))
                            .foregroundStyle(Color.accent)
                            .accessibilityIdentifier("max-hang-preview")
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Max hang test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(Color.accent)
                        .disabled(preview == nil)
                        .accessibilityIdentifier("max-hang-save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }

    private func field(label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            TextField("0", text: text)
                .keyboardType(.numbersAndPunctuation)
                .font(.scaled("JetBrainsMono-SemiBold", size: 20))
                .foregroundStyle(Color.ink)
                .padding(12)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($focused)
                .accessibilityIdentifier(id)
        }
    }

    private func save() {
        guard let test = preview else { return }
        store.update { $0.maxHangTests.append(test) }
        dismiss()
    }
}
