// OverrideTodaySheet.swift — "I want to do something other than the
// coach's plan for today."
//
// Two routes:
//   1. Pick one of the user's saved CustomRoutines (created via the coach
//      request flow, or migrated from earlier free-form custom workouts).
//   2. Ask the coach to build a fresh workout (CoachRequestScreen).
//
// Replaces the previous RoutineLibraryFlow entry point on Today + Week —
// users no longer browse the bundled routine library. The library still
// powers the planner under the hood; it's just hidden from the user.
//
// `onStartSession` fires when a workout actually begins — caller is
// responsible for dismissing whatever wrapped this sheet (Today's main
// view, or the Week day-edit sheet).

import SwiftUI

struct OverrideTodaySheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var customStore: CustomRoutineStore
    @Environment(\.dismiss) private var dismiss

    /// Called after a session is created from a picked or generated workout.
    let onStartSession: () -> Void

    @State private var showingCoachRequest = false
    @State private var editingRoutine: CustomRoutine? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Button(action: { showingCoachRequest = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.accentInk)
                                    .frame(width: 24, alignment: .center)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Build a workout")
                                        .styled(.displayS)
                                        .foregroundStyle(Color.accentInk)
                                    Text("Tell the coach the focus + duration")
                                        .styled(.body)
                                        .foregroundStyle(Color.accentInk.opacity(0.7))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.accentInk.opacity(0.7))
                            }
                            .padding(14)
                            .background(Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("override-build-workout")

                        if !customStore.routines.isEmpty {
                            sectionHeader("YOUR WORKOUTS")
                            VStack(spacing: 8) {
                                ForEach(customStore.routines) { custom in
                                    customRow(custom)
                                }
                            }
                        } else {
                            Text("Saved workouts will show up here once you build one.")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Override today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingCoachRequest) {
            CoachRequestScreen(onSaved: { custom, startNow in
                customStore.save(custom)
                showingCoachRequest = false
                if startNow {
                    startSession(with: custom)
                }
            })
        }
        .sheet(item: $editingRoutine) { routine in
            CustomRoutineEditSheet(routine: routine)
        }
    }

    // MARK: - Custom row

    private func customRow(_ custom: CustomRoutine) -> some View {
        HStack(spacing: 8) {
            Button {
                startSession(with: custom)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accent)
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(custom.name.isEmpty ? "Untitled workout" : custom.name)
                            .styled(.displayS)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text(subtitle(for: custom))
                            .styled(.body)
                            .foregroundStyle(Color.ink3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink3)
                }
                .padding(14)
                .background(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    editingRoutine = custom
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    customStore.delete(custom)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            Button {
                editingRoutine = custom
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 36, height: 36)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(custom.name.isEmpty ? "untitled workout" : custom.name)")
        }
    }

    private func subtitle(for c: CustomRoutine) -> String {
        let count = c.exercises.count
        let movements = count == 1 ? "1 movement" : "\(count) movements"
        return movements
    }

    private func sectionHeader(_ s: String) -> some View {
        Text(s)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
            .padding(.top, 6)
    }

    // MARK: - Session start

    /// Bridge the picked custom routine into the active-session runtime and
    /// fire the start callback so the host surface can dismiss itself.
    private func startSession(with custom: CustomRoutine) {
        let template = custom.toWorkoutTemplate()
        sessionStore.saveActive(sessionStore.createSession(from: template))
        dismiss()
        onStartSession()
    }
}

// MARK: - Preview

#Preview {
    let suite = "OverrideTodaySheet.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let session = SessionStore(defaults: defaults)
    let custom = CustomRoutineStore(defaults: defaults)
    let memory = MemoryStore(defaults: defaults)
    memory.update { m in
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 3
    }
    return Text("host")
        .sheet(isPresented: .constant(true)) {
            OverrideTodaySheet(onStartSession: {})
                .environmentObject(session)
                .environmentObject(custom)
                .environmentObject(memory)
        }
}
