// MiniWorkoutDiffCard.swift — Phase 13d inline workout-change preview.
//
// Sibling to MiniPlanDiffCard. Renders below the assistant bubble that
// produced a propose_workout_changes call. Resolves the proposal against
// today's DayPlan.generatedWorkout, shows changed exercises before/after,
// and routes Apply through PlanStore.applyWorkoutDiff.
//
// Refuses to apply when SessionStore has an active session — the user is
// already logging and we'd lose their sets.

import SwiftUI

struct MiniWorkoutDiffCard: View {
    let messageId: UUID
    let proposal: CoachWorkoutProposal

    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var conv: CoachConversationStore

    @State private var diff: WorkoutDiff? = nil
    @State private var resolutionNote: String? = nil
    /// Latches on the first Apply tap; see `apply()`.
    @State private var isApplying = false

    var body: some View {
        MiniDiffCardChrome(
            icon: "figure.strengthtraining.traditional",
            status: chromeStatus,
            pendingLabel: "WORKOUT TWEAK",
            countLabel: "\(proposal.changes.count) change\(proposal.changes.count == 1 ? "" : "s")",
            reasoning: proposal.reasoning,
            canApply: canApply,
            onApply: apply,
            onReject: reject
        ) {
            if let d = diff {
                changedRows(diff: d)
                if d.isNoop {
                    Text("(No matching exercises in today's workout — nothing to change.)")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            } else if let note = resolutionNote {
                Text(note)
                    .font(.monoXS)
                    .foregroundStyle(Color.danger)
            }
            if sessionStore.active != nil {
                Text("You've started today's session — applying will update your live exercises and keep any logged sets.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: resolve)
    }

    // MARK: - Pieces

    private var chromeStatus: MiniDiffCardStatus {
        switch proposal.status {
        case .pending:  return .pending
        case .applied:  return .applied
        case .rejected: return .rejected
        }
    }

    private func changedRows(diff: WorkoutDiff) -> some View {
        let before = Dictionary(uniqueKeysWithValues: diff.before.exercises.map { ($0.id, $0) })
        let changed: [(GeneratedExercise?, GeneratedExercise)] = diff.after.exercises.compactMap { after in
            guard let priorOpt = before[after.id] else { return (nil, after) }
            return rowEqual(priorOpt, after) ? nil : (priorOpt, after)
        }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(changed.enumerated()), id: \.offset) { _, pair in
                row(before: pair.0, after: pair.1)
            }
        }
    }

    private func row(before: GeneratedExercise?, after: GeneratedExercise) -> some View {
        HStack(spacing: 8) {
            if let before {
                Text(short(before))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .strikethrough(true, color: Color.ink3)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            Text(short(after))
                .font(.monoXS)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Logic

    /// DateFormatter is expensive to allocate; resolve() runs on every card
    /// appearance and apply() on tap, both parsing the proposal's yyyy-MM-dd
    /// date string, so cache one instance.
    private static let isoDay: DateFormatter = DayKeyFormatter.iso

    private var canApply: Bool {
        guard proposal.status == .pending,
              let diff = diff,
              !diff.isNoop else { return false }
        return true
    }

    /// Same early-bail its sibling MiniPlanDiffCard documents as a build-60
    /// watchdog fix — this card never had it. In a LazyVStack `onAppear`
    /// re-fires after scrolling away and back, so POST-apply it recomputed the
    /// diff against the already-mutated workout, got isNoop, and rendered
    /// "(No matching exercises in today's workout — nothing to change.)"
    /// underneath an APPLIED header.
    private func resolve() {
        guard diff == nil, resolutionNote == nil else { return }
        guard let plan = planStore.plan,
              let target = Self.isoDay.date(from: proposal.dateString) else {
            resolutionNote = "No active plan to edit."
            return
        }
        guard let day = plan.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: target) }),
              let workout = day.generatedWorkout else {
            resolutionNote = "That day doesn't have a generated workout to edit."
            return
        }
        diff = WorkoutDiffBuilder.diff(for: proposal, workout: workout)
    }

    private func apply() {
        // Double-tap guard. MiniMemoryDiffCard documents why this is needed —
        // the captured `proposal` is a render-time snapshot that still reads
        // .pending on a second tap — but neither this card nor MiniPlanDiffCard
        // had it, so a fast double-tap fired applyWorkoutDiff and the haptic
        // twice.
        guard !isApplying else { return }
        isApplying = true
        guard let diff = diff, let target = Self.isoDay.date(from: proposal.dateString) else { return }
        let planOk = planStore.applyWorkoutDiff(diff, on: target)
        // If the user has already started the session, mirror the edit into
        // the live ActiveSession so they don't have to restart.
        if sessionStore.active != nil {
            sessionStore.applyWorkoutDiffToActiveSession(diff)
        }
        if planOk || sessionStore.active != nil {
            conv.setWorkoutProposalStatus(messageId: messageId, .applied)
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        }
    }

    private func reject() {
        conv.setWorkoutProposalStatus(messageId: messageId, .rejected)
    }

    // MARK: - Display helpers

    private func short(_ ex: GeneratedExercise) -> String {
        "\(ex.name) · \(ex.sets)×\(ex.reps)"
    }

    private func rowEqual(_ a: GeneratedExercise, _ b: GeneratedExercise) -> Bool {
        a.name == b.name && a.sets == b.sets && a.reps == b.reps && a.restSeconds == b.restSeconds
    }
}
