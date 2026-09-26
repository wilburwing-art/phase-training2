// TwinScorecardSheet.swift — B1a DEBUG-only readout of the shadow twin.
//
// Two numbers answer the B1b go/no-go: the frozen predictions scored against
// what was logged, and a walk-forward replay over all native plus imported
// history. Compiled only in Debug; nothing here ships.

#if DEBUG
import SwiftUI

struct TwinScorecardSheet: View {
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var replay: TwinReplay.Report?
    @State private var replayRan = false
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                let card = TwinScorecard.from(planStore.dayOutcomes)
                Section("Frozen predictions") {
                    row("Scored pairs", "\(card.pairs.n)")
                    row("Model MAE (lb)", String(format: "%.1f", card.pairs.maeModel))
                    row("Last-value MAE (lb)", String(format: "%.1f", card.pairs.maeBaseline))
                    row("Improvement", percent(card.pairs.improvement))
                    ForEach(DayOutcomeKind.allCases, id: \.self) { kind in
                        if let r = card.readinessByKind[kind] {
                            row("Readiness · \(kind.rawValue)", String(format: "%.2f", r))
                        }
                    }
                }
                Section("Replay: fit 16 weeks, score the final 8") {
                    if let r = replay {
                        row("Training days", "\(r.trainingDays)")
                        row("Holdout pairs", "\(r.holdout.n)")
                        row("Fitted model MAE (lb)", String(format: "%.1f", r.holdout.maeModel))
                        row("Default model MAE (lb)", String(format: "%.1f", r.holdoutWithDefaults.maeModel))
                        row("Last-value MAE (lb)", String(format: "%.1f", r.holdout.maeBaseline))
                        row("Improvement (fitted)", percent(r.holdout.improvement))
                        row("Fitted params", "τF \(Int(r.fitted.tauFitness)) · τG \(Int(r.fitted.tauFatigue)) · w \(Int(r.fitted.fatigueWeight)) · k \(r.fitted.gain)")
                        row("B1b go/no-go", r.holdout.improvement > 0 ? "GO" : "NO-GO")
                    } else if replayRan {
                        Text("No loaded history to replay.")
                    } else {
                        Button(running ? "Running…" : "Run replay") { runReplay() }
                            .disabled(running)
                    }
                }
            }
            .navigationTitle("Shadow twin")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func runReplay() {
        running = true
        let sets = TwinInputs.sets(from: sessionStore.savedSessions)
            + TwinInputs.sets(from: planStore.importedSetsProvider())
        Task.detached(priority: .userInitiated) {
            let report = TwinReplay.run(sets: sets)
            await MainActor.run { replay = report; replayRan = true; running = false }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).monospacedDigit().foregroundStyle(.secondary) }
    }

    private func percent(_ v: Double) -> String { String(format: "%+.1f%%", v * 100) }
}
#endif
