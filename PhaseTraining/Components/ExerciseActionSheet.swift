// ExerciseActionSheet.swift — half-modal that opens on row tap from a
// `.presentation` density `ExerciseTile` with the `.overflow` trailing.
//
// Replaces the inline info.circle + arrow.left.arrow.right button stack that
// used to live on every Today row. See HANDOFF-tile-system.md §4a for the
// base item set; Move up / Move down are surfaced on screens where the row's
// position is mutable (Today's pre-workout list) since the row no longer
// renders a drag handle.
//
// The sheet owns the "Recommend more / less / never" writes itself (via
// MemoryStore.bumpAffinity + dislikes). Navigation rows ("Video & instructions",
// "Exercise history", "Replace") and the destructive "Delete from workout"
// take callbacks because they need the parent screen to drive sheet state
// and template mutation — we don't want this sheet aware of the workout's
// editable model.

import SwiftUI

struct ExerciseActionSheet: View {
    /// Exercise name — the join key for affinity + dislikes writes. Same name
    /// the rest of the app uses for looking back into coach.db.
    let exerciseName: String

    /// Optional callbacks. Pass nil to hide a row entirely (e.g. omit
    /// `onDelete` from screens that don't allow in-place removal,
    /// or `onEdit` from screens that don't expose set/rep/rest editing
    /// like the Library catalog).
    var onEdit: (() -> Void)? = nil
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    var onShowDetails: (() -> Void)? = nil
    var onShowHistory: (() -> Void)? = nil
    var onShowReplace: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @EnvironmentObject private var memoryStore: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let onEdit {
                            row(icon: "slider.horizontal.3", label: "Edit sets, reps, rest") {
                                dismiss()
                                onEdit()
                            }
                            divider
                        }
                        if let onMoveUp {
                            row(icon: "arrow.up", label: "Move up") {
                                dismiss()
                                onMoveUp()
                            }
                            divider
                        }
                        if let onMoveDown {
                            row(icon: "arrow.down", label: "Move down") {
                                dismiss()
                                onMoveDown()
                            }
                            divider
                        }
                        if let onShowDetails {
                            row(icon: "play.rectangle", label: "Video & instructions") {
                                dismiss()
                                onShowDetails()
                            }
                            divider
                        }
                        if let onShowHistory {
                            row(icon: "clock.arrow.circlepath", label: "Exercise history") {
                                dismiss()
                                onShowHistory()
                            }
                            divider
                        }
                        if let onShowReplace {
                            row(icon: "arrow.left.arrow.right", label: "Replace") {
                                dismiss()
                                onShowReplace()
                            }
                            divider
                        }
                        row(icon: "hand.thumbsup", label: "Recommend more often") {
                            memoryStore.bumpAffinity(exerciseName, by: 1)
                            dismiss()
                        }
                        divider
                        row(icon: "hand.thumbsdown", label: "Recommend less often") {
                            memoryStore.bumpAffinity(exerciseName, by: -1)
                            dismiss()
                        }
                        divider
                        row(icon: "nosign", label: "Don't recommend again") {
                            memoryStore.update {
                                if !$0.dislikes.contains(exerciseName) {
                                    $0.dislikes.append(exerciseName)
                                }
                            }
                            dismiss()
                        }
                        if let onDelete {
                            divider
                            row(icon: "trash", label: "Delete from workout",
                                tint: Color.red) {
                                showDeleteConfirm = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
            }
            .alert("Delete from workout?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(exerciseName) will be removed from today's workout. The bundled routine isn't affected.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Row primitive

    private func row(icon: String, label: String, tint: Color = Color.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(tint == Color.ink ? Color.ink2 : tint)
                    .frame(width: 24, alignment: .center)
                Text(label)
                    .font(.custom("Inter-Regular", size: 15))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.lineSoft)
            .frame(height: 0.5)
    }
}

// MARK: - Preview

#Preview("All rows") {
    let suite = "ExerciseActionSheet.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return Color.bg.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ExerciseActionSheet(
                exerciseName: "Barbell bench press",
                onEdit: {},
                onShowDetails: {},
                onShowHistory: {},
                onShowReplace: {},
                onDelete: {}
            )
            .environmentObject(MemoryStore(defaults: defaults))
        }
        .preferredColorScheme(.dark)
}

#Preview("Navigation-only (no delete)") {
    let suite = "ExerciseActionSheet.preview2"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return Color.bg.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ExerciseActionSheet(
                exerciseName: "Pull up",
                onShowDetails: {},
                onShowHistory: {},
                onShowReplace: {}
            )
            .environmentObject(MemoryStore(defaults: defaults))
        }
        .preferredColorScheme(.dark)
}
