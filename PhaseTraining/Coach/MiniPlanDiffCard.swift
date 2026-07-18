// MiniPlanDiffCard.swift — compact in-drawer diff preview.
//
// Renders below an assistant bubble whose CoachMessage carries a proposal.
// Resolves the proposal into a [PlanEdit] against the current plan, computes
// a PlanDiff via PlanStore.propose, shows the affected days before/after,
// and routes Apply through PlanStore.apply(_:) — the same seam the manual
// edit affordances use. Reject just records the status; no side effect.

import SwiftUI

struct MiniPlanDiffCard: View {
    let messageId: UUID
    let proposal: CoachProposal

    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var conv: CoachConversationStore

    @State private var resolvedDiff: PlanDiff? = nil
    @State private var resolutionNote: String? = nil

    var body: some View {
        MiniDiffCardChrome(
            icon: "wand.and.stars",
            status: chromeStatus,
            pendingLabel: "PROPOSAL",
            countLabel: "\(proposal.ops.count) edit\(proposal.ops.count == 1 ? "" : "s")",
            reasoning: proposal.reasoning,
            canApply: canApply,
            onApply: apply,
            onReject: reject
        ) {
            if let diff = resolvedDiff {
                affectedDays(diff: diff)
                if diff.isNoop {
                    Text("(No effective change — proposal resolves to a no-op.)")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            } else if let note = resolutionNote {
                Text(note)
                    .font(.monoXS)
                    .foregroundStyle(Color.danger)
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

    private func affectedDays(diff: PlanDiff) -> some View {
        // Show only days whose serialized form changed — keeps the card tight.
        let beforeMap = Dictionary(uniqueKeysWithValues: diff.before.days.map { ($0.id, $0) })
        let changed = diff.after.days.filter { day in
            guard let prior = beforeMap[day.id] else { return true }
            return !rowEqual(prior, day)
        }
        return VStack(spacing: 4) {
            ForEach(changed) { day in
                let before = beforeMap[day.id]
                row(before: before, after: day)
            }
        }
    }

    private func row(before: DayPlan?, after: DayPlan) -> some View {
        HStack(spacing: 8) {
            Text(weekday(after.date))
                .font(.custom("JetBrainsMono-SemiBold", size: 11))
                .foregroundStyle(Color.ink2)
                .frame(width: 28, alignment: .leading)
            if let before {
                Text(short(before))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .strikethrough(true, color: Color.ink3)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            Text(short(after))
                .font(.monoXS)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Logic

    private var canApply: Bool {
        guard proposal.status == .pending else { return false }
        guard let diff = resolvedDiff else { return false }
        return !diff.isNoop
    }

    /// Resolve once per view lifetime. `onAppear` fires every time the drawer
    /// re-renders (e.g. after setProposalStatus flips applied/rejected), and
    /// re-running this on every layout pass contributed to the build-60
    /// watchdog timeout. Bail early if we've already computed the diff or
    /// recorded a resolution failure.
    private func resolve() {
        guard resolvedDiff == nil, resolutionNote == nil else { return }
        guard let plan = planStore.plan else {
            resolutionNote = "No active plan to edit."
            return
        }
        let edits = CoachToolDecoder.planEdits(for: proposal, in: plan)
        guard !edits.isEmpty else {
            resolutionNote = "Couldn't match the proposed ops to your current plan."
            return
        }
        resolvedDiff = planStore.propose(edits, reasoning: proposal.reasoning)
    }

    private func apply() {
        guard let diff = resolvedDiff else { return }
        planStore.apply(diff)
        conv.setProposalStatus(messageId: messageId, .applied)
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }

    private func reject() {
        conv.setProposalStatus(messageId: messageId, .rejected)
    }

    // MARK: - Display helpers

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d).uppercased()
    }

    private func short(_ day: DayPlan) -> String {
        var parts: [String] = [day.kind.label.lowercased()]
        if day.kind == .sport, let sport = day.sport { parts.append("· \(sport.name)") }
        else if !day.title.isEmpty { parts.append("· \(day.title)") }
        if let mins = day.durationMinutes { parts.append("· \(mins)m") }
        if day.protected { parts.append("· locked") }
        if day.kind == .sport, let note = day.notes, !note.isEmpty {
            parts.append("— \(note)")
        }
        return parts.joined(separator: " ")
    }

    private func rowEqual(_ a: DayPlan, _ b: DayPlan) -> Bool {
        a.kind == b.kind && a.title == b.title &&
        a.protected == b.protected && a.durationMinutes == b.durationMinutes &&
        a.sport == b.sport && a.notes == b.notes &&
        Calendar.current.isDate(a.date, inSameDayAs: b.date)
    }
}
