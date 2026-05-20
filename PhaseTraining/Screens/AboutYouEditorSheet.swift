// AboutYouEditorSheet.swift — age + gender + height/weight editor.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass.
// Carries the typeable-age TextField (focus state + keyboard Done toolbar)
// from the previous inline implementation so the same keyboard ergonomics
// survive the move into a sheet.

import SwiftUI

struct AboutYouEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var ageText: String = ""
    @FocusState private var ageFocused: Bool

    private let minAge = 13
    private let maxAge = 99

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("AGE")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            Spacer()
                            if store.memory.age != nil {
                                Button("Clear") {
                                    store.update { $0.age = nil }
                                    ageText = ""
                                }
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                            }
                        }
                        ageTextField

                        HStack {
                            Text("GENDER")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            Spacer()
                            if store.memory.gender != nil {
                                Button("Clear") { store.update { $0.gender = nil } }
                                    .font(.monoXS)
                                    .foregroundStyle(Color.ink3)
                            }
                        }
                        WrappingFlow(spacing: 8) {
                            ForEach(Gender.allCases) { g in
                                OnboardingChip(
                                    label: g.label,
                                    selected: store.memory.gender == g,
                                    action: { store.update { $0.gender = $0.gender == g ? nil : g } }
                                )
                            }
                        }

                        HStack(spacing: 10) {
                            Text("HEIGHT & WEIGHT")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            Spacer()
                            Button(store.memory.usesImperial ? "Use metric" : "Use imperial") {
                                store.update { $0.usesImperial.toggle() }
                            }
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                        }
                        // BodyMetricsEditor mutates a Binding<TrainingMemory>; route
                        // it back through store.update so the change persists immediately.
                        BodyMetricsEditor(draft: Binding(
                            get: { store.memory },
                            set: { newMemory in store.update { $0 = newMemory } }
                        ))
                        Text("Used for strength-to-bodyweight ratios on Progress.")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                    .contentShape(Rectangle())
                    .onTapGesture { ageFocused = false }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("About you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        ageFocused = false
                        commitAge()
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { ageFocused = false }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear { ageText = store.memory.age.map(String.init) ?? "" }
        .onChange(of: store.memory.age) { _, new in
            if !ageFocused { ageText = new.map(String.init) ?? "" }
        }
        .onChange(of: ageFocused) { _, isFocused in
            if !isFocused { commitAge() }
        }
    }

    private var ageTextField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("—", text: $ageText)
                .focused($ageFocused)
                .keyboardType(.numberPad)
                .submitLabel(.done)
                .onSubmit { ageFocused = false }
                .font(.custom("JetBrainsMono-SemiBold", size: 28))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text("YEARS")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ageFocused ? Color.accent : Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func commitAge() {
        let trimmed = ageText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let parsed = Int(trimmed) else {
            store.update { $0.age = nil }
            ageText = ""
            return
        }
        let clamped = min(max(parsed, minAge), maxAge)
        store.update { $0.age = clamped }
        ageText = String(clamped)
    }
}
