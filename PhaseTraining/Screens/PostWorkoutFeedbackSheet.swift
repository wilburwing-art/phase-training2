// PostWorkoutFeedbackSheet.swift — modal capture of FeedbackEntry after a
// session is saved.
//
// Auto-presented from CompleteScreen's Save tap. Replaces the inline
// FeedbackChips that lived on CompleteScreen pre-build-99 — one capture
// surface, not two. Same FeedbackEntry shape; the difficulty + hurtAreas
// + notes round-trip through MemoryStore.update unchanged so the
// coach context keeps reading the same field names.
//
// Difficulty is the only required input. Hurt areas (curated body-region
// list — joints + low back, not muscle slugs) and notes are optional.
// Skip dismisses without appending; Save appends one entry stamped at
// dismiss time and dismisses.

import SwiftUI

struct PostWorkoutFeedbackSheet: View {
    let sessionId: String?
    let onDone: () -> Void

    @EnvironmentObject private var memoryStore: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var difficulty: String? = nil
    @State private var hurtAreas: Set<String> = []
    @State private var notes: String = ""

    // MARK: - Catalogs

    /// Difficulty value/label pairs. Values match FeedbackEntry.difficulty
    /// strings that the coach context consumes ("too_easy" | "right" | "too_hard").
    private static let difficultyOptions: [(value: String, label: String)] = [
        ("too_easy", "Too easy"),
        ("right",    "Right"),
        ("too_hard", "Too hard"),
    ]

    /// Curated short list of body regions the user can flag as hurt. These are
    /// joint/region words (not muscle slugs) — same vocabulary the pre-workout
    /// soreness sheet uses, kept consistent so coach summaries can join them.
    private static let hurtAreaOptions: [String] = [
        "lower back", "knee", "shoulder", "elbow",
        "wrist", "neck", "hip", "ankle",
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        difficultySection
                        hurtSection
                        notesSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("How did it go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { skip() }
                        .foregroundStyle(Color.ink2)
                        .accessibilityIdentifier("feedback-skip")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(canSave ? Color.accent : Color.ink3)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("feedback-save")
                }
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(false)
    }

    // MARK: - Sections

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DIFFICULTY")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 6) {
                ForEach(Self.difficultyOptions, id: \.value) { opt in
                    // Radio behavior — difficulty is required, so re-tapping
                    // the selected chip keeps it selected instead of silently
                    // disabling Save.
                    chip(label: opt.label, active: difficulty == opt.value) {
                        difficulty = opt.value
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("feedback-difficulty-\(opt.value)")
                }
            }
        }
    }

    private var hurtSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("ANYTHING HURT?")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text("(optional)")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3.opacity(0.6))
            }
            let columns = [GridItem(.adaptive(minimum: 100), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Self.hurtAreaOptions, id: \.self) { area in
                    chip(label: area.capitalized, active: hurtAreas.contains(area)) {
                        toggleArea(area)
                    }
                    .accessibilityIdentifier("feedback-hurt-\(area.replacingOccurrences(of: " ", with: "-"))")
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES (OPTIONAL)")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surface)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5)

                if notes.isEmpty {
                    Text("Anything to remember?")
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(Color.ink3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 72)
            }
            .frame(minHeight: 92)
        }
    }

    // MARK: - Actions

    private var canSave: Bool { difficulty != nil }

    private func toggleArea(_ area: String) {
        if hurtAreas.contains(area) { hurtAreas.remove(area) }
        else                        { hurtAreas.insert(area) }
    }

    private func save() {
        guard canSave else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = FeedbackEntry(
            date: Date(),
            sessionId: sessionId,
            difficulty: difficulty,
            hurtAreas: Array(hurtAreas).sorted(),
            ranLong: false,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        memoryStore.update { $0.feedback.append(entry) }
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        dismiss()
        onDone()
    }

    private func skip() {
        dismiss()
        onDone()
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
    let suite = "PostWorkoutFeedback.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return Color.bg.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            PostWorkoutFeedbackSheet(sessionId: "upper-1", onDone: {})
                .environmentObject(MemoryStore(defaults: defaults))
        }
        .preferredColorScheme(.dark)
}
