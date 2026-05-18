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
        VStack(alignment: .leading, spacing: 10) {
            header
            if let reason = proposal.reasoning {
                Text(reason)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            actionBar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear(perform: resolve)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text(statusLabel)
                .styled(.micro)
                .foregroundStyle(statusColor)
            Spacer()
            Text("\(proposal.ops.count) edit\(proposal.ops.count == 1 ? "" : "s")")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
    }

    private var statusLabel: String {
        switch proposal.status {
        case .pending:  return "PROPOSAL"
        case .applied:  return "APPLIED"
        case .rejected: return "REJECTED"
        }
    }

    private var statusColor: Color {
        switch proposal.status {
        case .pending:  return Color.accent
        case .applied:  return Color.ok
        case .rejected: return Color.ink3
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

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(action: reject) {
                Text("Reject")
                    .styled(.micro)
                    .foregroundStyle(Color.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(proposal.status != .pending)

            Button(action: apply) {
                Text("Apply")
                    .styled(.micro)
                    .foregroundStyle(canApply ? Color.accentInk : Color.ink3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(canApply ? Color.accent : Color.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!canApply)

            Spacer()
        }
    }

    // MARK: - Logic

    private var canApply: Bool {
        guard proposal.status == .pending else { return false }
        guard let diff = resolvedDiff else { return false }
        return !diff.isNoop
    }

    private func resolve() {
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
        if !day.title.isEmpty { parts.append("· \(day.title)") }
        if let mins = day.durationMinutes { parts.append("· \(mins)m") }
        if day.protected { parts.append("· locked") }
        return parts.joined(separator: " ")
    }

    private func rowEqual(_ a: DayPlan, _ b: DayPlan) -> Bool {
        a.kind == b.kind && a.title == b.title &&
        a.protected == b.protected && a.durationMinutes == b.durationMinutes &&
        Calendar.current.isDate(a.date, inSameDayAs: b.date)
    }
}
