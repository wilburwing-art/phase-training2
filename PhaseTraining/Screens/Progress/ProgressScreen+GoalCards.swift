// ProgressScreen+GoalCards.swift — PR 11 of the weekly-coach roadmap.
//
// The goals card: one progress bar per active goal. Progress comes from
// `UserGoal.progress(...)` fed by the app's existing stores:
//   - best e1RM per exercise (UserDatabase.bestWeightsByExerciseAndReps
//     mapped through StrengthStandards.epley1RM)
//   - latest bodyweight (TrainingMemory.weightKg)
//   - fastest 5k + climb counts (sport logs, climbing-sport rows)
//
// An empty goals list renders nothing — the card exists only when the
// user has picked goals, keeping the tab unchanged for everyone else.

import SwiftUI

extension ProgressScreen {

    var goalsCard: some View {
        let goals = memoryStore.memory.userGoals
        if goals.isEmpty {
            return AnyView(EmptyView())
        }
        return AnyView(
            card(title: "GOALS") {
                VStack(spacing: 14) {
                    ForEach(goals) { goal in
                        GoalProgressRow(
                            goal: goal,
                            progress: goalProgress(goal)
                        )
                    }
                }
            }
        )
    }

    /// Compute progress for one goal against live stores. The metric
    /// computation lives on SessionStore (SessionStore+GoalMetrics.swift)
    /// so the CompleteScreen milestone hook and this card share one
    /// implementation.
    private func goalProgress(_ goal: UserGoal) -> Double? {
        let logs = planStore.sportLogStore?.entries ?? []
        return goal.progress(
            bestE1RM: store.bestE1RMByExercise(),
            bodyweightKg: memoryStore.memory.weightKg,
            fastestFiveKSeconds: store.fastestFiveKSeconds(sportLogs: logs),
            climbsLast30Days: store.climbsLast30Days(sportLogs: logs)
        )
    }
}

// MARK: - Row

/// One goal's progress bar. Unknown progress (nil) shows a hint naming
/// what's missing for that goal's metric instead of an empty bar.

struct GoalProgressRow: View {
    let goal: UserGoal
    let progress: Double?

    @EnvironmentObject private var memoryStore: MemoryStore

    /// Per-goal hint for nil progress — names the missing input so the
    /// row says what to do, not a blanket "log your weight".
    private func emptyReason(for goal: UserGoal, memory: TrainingMemory) -> String {
        switch goal.templateId {
        case .fiveKUnder25:
            return "Log a timed 5k run to track this goal"
        case .climbsHundredPerMonth:
            return "Log climbing sessions to track this goal"
        default:
            // Strength goals need bodyweight + history for the lift itself.
            if memory.weightKg == nil {
                return "Log your weight to track this goal"
            }
            return "Log \(goal.templateId.exerciseName ?? "the lift") to track this goal"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.templateId.label)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Spacer()
                if let p = progress {
                    Text("\(Int((p * 100).rounded()))%")
                        .font(.monoXS)
                        .foregroundStyle(p >= 1.0 ? Color.accent : Color.ink2)
                }
            }
            if let p = progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.elevated)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accent)
                            .frame(width: max(4, geo.size.width * min(p, 1.0)))
                    }
                }
                .frame(height: 6)
            } else {
                // Unknown (nil) progress: say what's actually missing for
                // this goal's metric, not a blanket "log your weight".
                Text(emptyReason(for: goal, memory: memoryStore.memory))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goal-progress-\(goal.templateId.rawValue)")
    }
}