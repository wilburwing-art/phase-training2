// PhaseTrainingWatchApp.swift — the watch companion (PLAN-watch.md).
//
// A mirror of today's session: sets are marked done here and the phone folds
// them in. The rest countdown, the weight and rep nudge and "Start on watch"
// (the Health workout with heart rate) are step 2. Labeled motion is step 3.

import SwiftUI

@main
struct PhaseTrainingWatchApp: App {
    @StateObject private var model = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SessionView()
            }
            .environmentObject(model)
        }
    }
}

struct SessionView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        if let session = model.active {
            List {
                if model.rest.isActive {
                    Section { RestRow() }
                }
                Section {
                    if model.workout.isRunning {
                        HStack {
                            Image(systemName: "heart.fill").foregroundStyle(.red)
                            Text(model.workout.heartRate.map { "\(Int($0)) bpm" } ?? "Reading...")
                            Spacer()
                            if let kcal = model.workout.activeEnergyKcal {
                                Text("\(Int(kcal)) kcal").foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                    } else {
                        Button {
                            Task { await model.startWorkout() }
                        } label: {
                            Label("Start on watch", systemImage: "heart.fill")
                        }
                    }
                }
                ForEach(session.exercises) { exercise in
                    Section(exercise.name) {
                        ForEach(exercise.sets, id: \.num) { set in
                            SetRow(exercise: exercise, set: set)
                        }
                    }
                }
                Section {
                    Button("End session", role: .destructive) {
                        Task { await model.endSession() }
                    }
                }
            }
            .navigationTitle(session.name)
        } else if let planned = model.planned {
            VStack(spacing: 10) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Text(planned.name).font(.headline).multilineTextAlignment(.center)
                Text("\(planned.exercises.count) exercises")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Start") { model.startPlannedSession() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else {
            VStack(spacing: 8) {
                Text("Phase Training")
                    .font(.headline)
                Text("Nothing planned today. Start a session on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

/// The active rest, ticking once a second. Extend or skip in place.
struct RestRow: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = model.rest.remaining(at: context.date)
            HStack {
                VStack(alignment: .leading) {
                    Text("Rest").font(.caption).foregroundStyle(.secondary)
                    Text(WatchRestTimer.format(remaining ?? 0))
                        .font(.title3.monospacedDigit())
                }
                Spacer()
                Button("+15") { model.rest.extend() }
                    .buttonStyle(.bordered)
                Button {
                    model.rest.clear()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.bordered)
            }
            .onChange(of: context.date) { _, date in model.rest.tick(at: date) }
        }
    }
}

/// One set. Tap the circle to mark it done as planned; tap the row to nudge
/// the weight or reps first.
struct SetRow: View {
    @EnvironmentObject private var model: WatchSessionModel
    let exercise: LoggedExercise
    let set: LoggedSet

    var body: some View {
        HStack {
            Button {
                model.toggle(exerciseId: exercise.id, setNum: set.num)
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.done ? .green : .secondary)
            }
            .buttonStyle(.plain)
            NavigationLink {
                SetDetailView(exercise: exercise, set: set)
            } label: {
                VStack(alignment: .leading) {
                    Text("Set \(set.num)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(SetDetailView.label(weight: set.weight, reps: set.reps, unit: exercise.displayUnit))
                        .font(.body)
                }
            }
        }
    }
}

/// Nudge the planned weight and reps, then mark the set done.
struct SetDetailView: View {
    @EnvironmentObject private var model: WatchSessionModel
    @Environment(\.dismiss) private var dismiss
    let exercise: LoggedExercise
    let set: LoggedSet

    @State private var weight: Double = 0
    @State private var reps: Int = 0

    var body: some View {
        VStack(spacing: 10) {
            Text(exercise.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if !exercise.isBodyweight {
                Stepper(value: $weight, in: 0...2000, step: weightStep) {
                    Text("\(Self.trim(weight)) \(exercise.displayUnit)").font(.body.monospacedDigit())
                }
            }
            Stepper(value: $reps, in: 0...100) {
                Text("\(reps) reps").font(.body.monospacedDigit())
            }
            Button(set.done ? "Update set" : "Done") {
                model.complete(exerciseId: exercise.id, setNum: set.num,
                               weight: exercise.isBodyweight ? nil : Self.trim(weight),
                               reps: String(reps))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Set \(set.num)")
        .onAppear {
            weight = set.weightValue ?? 0
            reps = set.repsValue ?? exercise.targetReps
        }
    }

    /// Kilograms move in 2.5s, pounds in 5s.
    private var weightStep: Double { exercise.displayUnit.lowercased().hasPrefix("kg") ? 2.5 : 5 }

    static func trim(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    static func label(weight: String, reps: String, unit: String) -> String {
        let w = weight.isEmpty ? "" : "\(weight) \(unit) x "
        return "\(w)\(reps.isEmpty ? "?" : reps)"
    }
}

#Preview {
    NavigationStack { SessionView() }.environmentObject(WatchSessionModel())
}
