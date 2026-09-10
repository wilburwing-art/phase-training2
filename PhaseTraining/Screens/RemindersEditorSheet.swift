// RemindersEditorSheet.swift — weekly-plan-reminder toggle.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass. Same
// async WeeklyReminderScheduler.enable() / .disable() flow as before.

import SwiftUI

struct RemindersEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var remindersOn = WeeklyReminderScheduler.isEnabled
    @State private var remindersPending = false
    @State private var remindersFailed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("REMINDERS")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        Button(action: toggleReminders) {
                            HStack(spacing: 12) {
                                Image(systemName: remindersOn ? "bell.fill" : "bell.slash")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(remindersOn ? Color.accent : Color.ink3)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Weekly plan reminder")
                                        .styled(.body)
                                        .foregroundStyle(Color.ink)
                                    Text("Sundays at 6:00 PM · walks through next week's plan")
                                        .font(.monoXS)
                                        .foregroundStyle(Color.ink3)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: remindersOn ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(remindersOn ? Color.accent : Color.ink3)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(remindersOn ? Color.accentWash : Color.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(remindersOn ? Color.accentBorder : Color.line, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(remindersPending)
                        if remindersFailed {
                            Text("Couldn't enable. Notifications are off for this app; allow them in Settings to get the reminder.")
                                .font(.monoXS)
                                .foregroundStyle(Color.danger)
                        }

                        // PR 12 — per-class push governance. Toggling a
                        // class off stops those pushes from scheduling;
                        // the daily cap (3/day) applies regardless.
                        Text("PUSH CATEGORIES")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                            .padding(.top, 8)
                        ForEach([NotificationBudget.Class.missedWorkout,
                                 NotificationBudget.Class.coachMilestone],
                                id: \.self) { cls in
                            Toggle(isOn: classBinding(cls)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cls.label)
                                        .styled(.body)
                                        .foregroundStyle(Color.ink)
                                    Text(cls == .missedWorkout
                                         ? "When the autopilot spots a missed workout"
                                         : "PRs, goal progress, streak celebrations")
                                        .font(.monoXS)
                                        .foregroundStyle(Color.ink3)
                                }
                            }
                            .toggleStyle(.switch)
                            .tint(Color.accent)
                        }
                        Text("Max 3 pushes a day · dismissed notifications are suppressed automatically")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear { remindersOn = WeeklyReminderScheduler.isEnabled }
    }

    private func toggleReminders() {
        remindersFailed = false
        if remindersOn {
            WeeklyReminderScheduler.disable()
            remindersOn = false
            return
        }
        remindersPending = true
        Task {
            let ok = await WeeklyReminderScheduler.enable()
            await MainActor.run {
                remindersOn = ok
                remindersPending = false
                // Permission denied or scheduling failed — say why the
                // toggle snapped back instead of failing silently.
                remindersFailed = !ok
            }
        }
    }

    // MARK: - PR 12 — per-class toggles

    @State private var classStates: [NotificationBudget.Class: Bool] = [:]

    private func classBinding(_ cls: NotificationBudget.Class) -> Binding<Bool> {
        Binding(
            get: { classStates[cls] ?? NotificationBudget.isEnabled(cls) },
            set: { newValue in
                classStates[cls] = newValue
                NotificationBudget.setEnabled(newValue, for: cls)
            }
        )
    }
}
