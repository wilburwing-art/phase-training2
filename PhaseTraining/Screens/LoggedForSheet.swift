// LoggedForSheet.swift — log a workout that happened earlier.
//
// A workout done without the phone still has to reach muscle recovery, the
// week's takeover and Apple Health with the time it happened. The sheet sets
// `ActiveSession.loggedFor`; `SessionStore.commitCompleted` applies it at save,
// so the time spent logging never becomes the workout's length.

import SwiftUI

struct LoggedForSheet: View {
    /// nil = today, now.
    @Binding var loggedFor: LoggedFor?
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var minutes: Int

    init(loggedFor: Binding<LoggedFor?>) {
        self._loggedFor = loggedFor
        let yesterdayEvening = Calendar.current.date(
            bySettingHour: 17, minute: 30, second: 0,
            of: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) ?? Date()
        self._start = State(initialValue: loggedFor.wrappedValue?.start ?? yesterdayEvening)
        self._minutes = State(initialValue: loggedFor.wrappedValue?.minutes ?? 60)
    }

    private var range: ClosedRange<Date> {
        let earliest = Calendar.current.date(byAdding: .day, value: -LoggedFor.maxDaysBack,
                                             to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return earliest...Date()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WHEN DID YOU TRAIN?")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            DatePicker("Started", selection: $start, in: range,
                                       displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.graphical)
                                .tint(Color.accent)
                                .accessibilityIdentifier("logged-for-date")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("HOW LONG?")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            Stepper(value: $minutes, in: 10...240, step: 5) {
                                Text("\(minutes) min")
                                    .styled(.monoM)
                                    .foregroundStyle(Color.ink)
                            }
                            .accessibilityIdentifier("logged-for-minutes")
                        }

                        if loggedFor != nil {
                            Button {
                                loggedFor = nil
                                dismiss()
                            } label: {
                                Text("Back to today")
                                    .styled(.body)
                                    .foregroundStyle(Color.ink2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("logged-for-today")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Logged for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        loggedFor = LoggedFor(start: min(start, Date()), minutes: minutes)
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                    .accessibilityIdentifier("logged-for-save")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    /// "Today" or "Tue, Oct 27 · 5:30 PM · 60 min".
    static func label(_ loggedFor: LoggedFor?) -> String {
        guard let l = loggedFor else { return "Today" }
        return "\(labelFormatter.string(from: l.start)) · \(l.minutes) min"
    }

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d h:mm a")
        return f
    }()
}
