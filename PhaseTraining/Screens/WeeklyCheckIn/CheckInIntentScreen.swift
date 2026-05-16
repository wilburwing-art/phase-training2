// CheckInIntentScreen.swift — step 1 of WeeklyCheckInFlow.

import SwiftUI

struct CheckInIntentScreen: View {
    @Binding var draft: WeeklyCheckInDraft
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        CheckInScaffold(
            step: .intent,
            title: "Next week.",
            subtitle: "What do you want out of it?",
            nextLabel: "Continue",
            nextEnabled: true,
            onNext: onNext,
            onBack: nil,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 18) {
                tagSection
                noteSection
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TONE")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            let columns = [GridItem(.adaptive(minimum: 120), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(WeeklyCheckInDraft.intentChips, id: \.0) { value, label in
                    OnboardingChip(
                        label: label,
                        selected: draft.intentTags.contains(value),
                        action: { toggle(value) }
                    )
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANYTHING ELSE? (OPTIONAL)")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surface)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5)
                if draft.intentText.isEmpty {
                    Text("Press into bench, ease off squats…")
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(Color.ink3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft.intentText)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 90)
        }
    }

    private func toggle(_ value: String) {
        if draft.intentTags.contains(value) { draft.intentTags.remove(value) }
        else { draft.intentTags.insert(value) }
    }
}
