// TwinScorecardSheet.swift — DEBUG-only "Signals" readout: what the app has
// collected since A2 (SignalsReadout), then the B1a shadow twin.
//
// Two numbers answer the B1b go/no-go: the frozen predictions scored against
// what was logged, and a walk-forward replay over all native plus imported
// history. Compiled only in Debug; nothing here ships.

#if DEBUG
import SwiftUI

struct TwinScorecardSheet: View {
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var memoryStore: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var replay: TwinReplay.Report?
    @State private var replayRan = false
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                let sig = SignalsReadout.make(
                    outcomes: planStore.dayOutcomes,
                    explore: planStore.exploreSessionsSince(Date().addingTimeInterval(-28 * 86_400)),
                    suggestions: planStore.currentSuggestions(),
                    decisions: memoryStore.memory.suggestionDecisions)
                Section("Collected") {
                    row("Session outcomes", "\(sig.outcomesTotal)")
                    ForEach(DayOutcomeKind.allCases, id: \.self) { kind in
                        if let n = sig.outcomesByKind[kind] { row("  \(kind.rawValue)", "\(n)") }
                    }
                    row("Browse visits, 28 days", "\(sig.exploreVisits28d)")
                    row("  that converted", "\(sig.exploreConverted28d)")
                    row("Suggestions applied / dismissed", "\(sig.decisionsApplied) / \(sig.decisionsDismissed)")
                }
                Section("Check-in would ask today") {
                    if sig.suggestionsToday.isEmpty { Text("Nothing yet.").foregroundStyle(.secondary) }
                    ForEach(sig.suggestionsToday) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title)
                            Text(s.evidence).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                let spines = SpineAggregates.make(outcomes: planStore.dayOutcomes)
                if !spines.isEmpty {
                    Section("Spines (upload schema, on device only)") {
                        ForEach(spines) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CoachDatabase.shared.authoredRoutineMeta(id: a.routineId)?.name ?? "Routine \(a.routineId)")
                                Text(String(format: "%d sessions · %.0f%% as planned · first drop at %@ · %d swaps",
                                            a.sessions, a.completionRate * 100,
                                            a.medianFirstDropPosition.map { String(format: "#%.0f", $0 + 1) } ?? "none",
                                            a.substitutions.reduce(0) { $0 + $1.count }))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !sig.zeroResultQueries28d.isEmpty {
                    Section("Searches that found nothing (catalog gaps)") {
                        ForEach(sig.zeroResultQueries28d, id: \.self) { Text($0) }
                    }
                }
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
            .navigationTitle("Signals")
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
