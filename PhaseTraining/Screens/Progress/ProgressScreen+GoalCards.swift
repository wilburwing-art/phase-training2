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

    /// Compute progress for one goal against live stores.
    private func goalProgress(_ goal: UserGoal) -> Double? {
        goal.progress(
            bestE1RM: bestE1RMByExercise(),
            bodyweightKg: memoryStore.memory.weightKg,
            fastestFiveKSeconds: fastestFiveKSeconds(),
            climbsLast30Days: climbsLast30Days()
        )
    }

    /// Best epley-1RM per lowercased exercise name over all saved sessions.
    /// Same math the generator context uses for priorBest — shared formula,
    /// independent walk (this one covers ALL history, not the 4-week window).
    private func bestE1RMByExercise() -> [String: Double] {
        var best: [String: Double] = [:]
        for s in store.savedSessions {
            for ex in s.exercises {
                var best1RM = 0.0
                for set in ex.sets where set.done && !set.isWarmup {
                    guard let w = set.weightValue, let r = set.repsValue,
                          w > 0, r > 0 else { continue }
                    let e = StrengthStandards.epley1RM(weight: w, reps: r)
                    best1RM = max(best1RM, e)
                }
                if best1RM > 0 {
                    let key = ex.name.lowercased()
                    best[key] = max(best[key] ?? 0, best1RM)
                }
            }
        }
        return best
    }

    /// Fastest logged 5k in seconds. Sport logs don't carry distance —
    /// a 5k shows up as a running entry with duration ≈ 25 min ± slack
    /// and the "5k" keyword in the note. Tolerant match: nil when the
    /// user doesn't annotate runs. (Roadmap lists 5k as a template; the
    /// annotation-based read keeps this honest instead of guessing.)
    private func fastestFiveKSeconds() -> Double? {
        guard let sportLogStore = planStore.sportLogStore else { return nil }
        let candidates = sportLogStore.entries.filter { entry in
            entry.sport.slug == "running" || entry.sport.slug.contains("run")
        }
        guard !candidates.isEmpty else { return nil }
        // Without distance fields, a "5k" is a run whose note names the
        // distance; shortest such run wins as the best-effort signal.
        let fives = candidates.filter {
            ($0.note ?? "").lowercased().contains("5k")
        }
        guard !fives.isEmpty else { return nil }
        return Double(fives.map(\.durationMinutes).min()! * 60)
    }

    /// Climbing sessions logged in the last 30 days. The goal's spec
    /// language says "climbs"; the app logs sessions — one logged session
    /// is one climb-day, which is what the log can honestly count.
    private func climbsLast30Days() -> Int {
        guard let sportLogStore = planStore.sportLogStore else { return 0 }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        return sportLogStore.entries.filter {
            $0.sport.slug == "climbing" && $0.date >= cutoff
        }.count
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