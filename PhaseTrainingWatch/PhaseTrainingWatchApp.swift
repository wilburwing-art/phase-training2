// PhaseTrainingWatchApp.swift — the watch companion (PLAN-watch.md).
//
// Step 1: a mirror of today's session. Sets are marked done here and the
// phone folds them in. The rest timer, the Health workout and labeled motion
// land in steps 2 and 3.

import SwiftUI

@main
struct PhaseTrainingWatchApp: App {
    @StateObject private var model = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            SessionView()
                .environmentObject(model)
        }
    }
}

struct SessionView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        if let session = model.active {
            List {
                ForEach(session.exercises) { exercise in
                    Section(exercise.name) {
                        ForEach(exercise.sets, id: \.num) { set in
                            SetRow(set: set, unit: exercise.displayUnit) {
                                model.toggle(exerciseId: exercise.id, setNum: set.num)
                            }
                        }
                    }
                }
                Section {
                    Button("End session", role: .destructive) { model.endSession() }
                }
            }
            .navigationTitle(session.name)
        } else {
            VStack(spacing: 8) {
                Text("Phase Training")
                    .font(.headline)
                Text("Start today's session on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

struct SetRow: View {
    let set: LoggedSet
    let unit: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(set.done ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text("Set \(set.num)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.body)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        let weight = set.weight.isEmpty ? "" : "\(set.weight) \(unit) x "
        return "\(weight)\(set.reps.isEmpty ? "?" : set.reps)"
    }
}

#Preview {
    SessionView().environmentObject(WatchSessionModel())
}
