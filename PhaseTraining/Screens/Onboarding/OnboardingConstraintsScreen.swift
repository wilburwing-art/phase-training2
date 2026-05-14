// OnboardingConstraintsScreen.swift — step 8 of 8 (final).
// Two free-text lists: dislikes ("don't program these") and constraints
// ("watch out for these"). Both are advisory inputs to the planner + the
// future coach; they don't gate anything.
//
// "Finish" is enabled unconditionally — both lists are optional.

import SwiftUI

struct OnboardingConstraintsScreen: View {
    @Binding var draft: TrainingMemory
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var dislikeInput = ""
    @State private var constraintInput = ""

    var body: some View {
        OnboardingScaffold(
            step: .constraints,
            title: "Anything we should know?",
            subtitle: "Optional — exercises you hate, joints to be careful with, time blocks that change weekly.",
            nextLabel: "Finish setup",
            onNext: onFinish,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 24) {
                EntryList(
                    label: "EXERCISES TO AVOID",
                    placeholder: "e.g. burpees, deadlifts",
                    items: $draft.dislikes,
                    input: $dislikeInput
                )

                EntryList(
                    label: "INJURIES OR CONSTRAINTS",
                    placeholder: "e.g. left knee, no jumping",
                    items: $draft.constraints,
                    input: $constraintInput
                )
            }
        }
    }
}

private struct EntryList: View {
    let label: String
    let placeholder: String
    @Binding var items: [String]
    @Binding var input: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnboardingSectionLabel(text: label)

            HStack(spacing: 8) {
                TextField("", text: $input, prompt: Text(placeholder).foregroundColor(Color.ink3))
                    .focused($focused)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.line, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onSubmit(commit)

                Button(action: commit) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canCommit ? Color.accentInk : Color.ink3)
                        .frame(width: 44, height: 44)
                        .background(canCommit ? Color.accent : Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(canCommit ? Color.clear : Color.line, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
            }

            if !items.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        RemovableTag(label: item) { remove(item) }
                    }
                }
            }
        }
    }

    private var canCommit: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func commit() {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !items.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        items.append(trimmed)
        input = ""
    }

    private func remove(_ item: String) {
        items.removeAll { $0 == item }
    }
}

private struct RemovableTag: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(Color.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingConstraintsScreen(draft: $draft, onFinish: {}, onBack: {})
}
