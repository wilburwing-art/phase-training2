// CheckInMissedScreen.swift — pre-step: resolve what the finished week missed.
//
// Build 122 moved this off Today. The banner used to interrupt a training day
// to ask about a day that had already gone; the weekly check-in is already the
// "look back, then plan forward" moment, so the misses get handled in one pass
// here instead.
//
// This is NOT cosmetic relocation. MissedWorkoutBanner's buttons are the only
// callers of applyMissedReshuffle / dismissMissed, which are the only writers
// of `missedWorkouts`, which is the only thing pendingMissedWorkouts() filters
// against. Without a resolve path a missed day stays pending forever. See
// .claude/skills/phase-training-rootview-deferred-deps-need-notify.
//
// The three actions are unchanged and still decided by the existing API:
// proposeMissedReshuffle returns nil when no valid target exists (which is the
// normal case for a week that has ended), and shouldOfferConsolidation gates
// the consolidate path. Opening the check-in mid-week therefore still offers a
// real reshuffle; opening it on Sunday offers acknowledge.

import SwiftUI

struct CheckInMissedScreen: View {
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var memoryStore: MemoryStore

    let onNext: () -> Void
    let onClose: () -> Void

    @State private var consolidationDecline: PlanStore.ConsolidationDecline?
    @State private var showConsolidationNoop = false

    private var pending: [DayPlan] {
        planStore.pendingMissedWorkouts()
    }

    var body: some View {
        CheckInScaffold(
            step: .missed,
            title: "Last week.",
            subtitle: pending.count == 1
                ? "One planned day went by. Clear it and we'll plan forward."
                : "\(pending.count) planned days went by. Clear them and we'll plan forward.",
            nextLabel: pending.isEmpty ? "Continue" : "Skip for now",
            nextEnabled: true,
            onNext: onNext,
            onBack: nil,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(pending, id: \.id) { day in
                    MissedWorkoutBanner(
                        missedDay: day,
                        proposedDiff: planStore.proposeMissedReshuffle(missedDate: day.date),
                        onAccept: { accept(day) },
                        onDismiss: { planStore.dismissMissed(date: day.date, asDropped: false) },
                        onConsolidate: planStore.shouldOfferConsolidation(missedDate: day.date)
                            ? { consolidate(day) } : nil
                    )
                }
                if pending.isEmpty {
                    Text("Nothing outstanding.")
                        .styled(.body)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
        .alert("Nothing to consolidate", isPresented: $showConsolidationNoop) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(consolidationNoopMessage)
        }
    }

    private func accept(_ day: DayPlan) {
        if let diff = planStore.proposeMissedReshuffle(missedDate: day.date) {
            planStore.applyMissedReshuffle(diff, missedDate: day.date)
        } else {
            // Drop rule fired or no valid target. Log as dropped so the same
            // date does not come back.
            planStore.dismissMissed(date: day.date, asDropped: true)
        }
    }

    private func consolidate(_ day: DayPlan) {
        // consolidateWeekDetailed reports which constraint blocked a no-op.
        // Don't pretend it worked; say the miss was dropped and why.
        let decline = planStore.consolidateWeekDetailed(memory: memoryStore.memory)
        planStore.dismissMissed(date: day.date, asDropped: true)
        if let decline {
            consolidationDecline = decline
            showConsolidationNoop = true
        }
    }

    private var consolidationNoopMessage: String {
        let reason: String
        switch consolidationDecline {
        case .weeklyCapMet:
            reason = "the weekly cap is already met"
        case .notEnoughLiftDays:
            reason = "not enough lift days left this week"
        case .unrecoverableFocus:
            reason = "the remaining workouts couldn't be merged"
        case nil:
            return "The week couldn't absorb the missed work — the workout was skipped instead."
        }
        return "The week couldn't absorb the missed work — \(reason). The workout was skipped instead."
    }
}
