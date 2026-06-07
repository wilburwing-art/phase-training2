// MiniMemoryDiffCard.swift — Phase 13f propose_memory_update preview.
//
// Sibling to MiniPlanDiffCard + MiniWorkoutDiffCard. Shows additions and
// removals against the user's dislikes / constraints lists. Apply mutates
// MemoryStore.memory; reject leaves it alone. Append-only spirit: we never
// edit typed fields (sports, age, equipment, experience) — only the free-
// text lists.

import SwiftUI

struct MiniMemoryDiffCard: View {
    let messageId: UUID
    let proposal: CoachMemoryProposal

    @EnvironmentObject private var memoryStore: MemoryStore
    @EnvironmentObject private var conv: CoachConversationStore

    // Guards against a back-to-back double-tap on Apply firing the
    // mutation + haptic twice before SwiftUI re-renders the button as
    // disabled. The local `proposal` is a snapshot captured at render
    // time, so the second tap's handler would still see status==.pending
    // without this flag.
    @State private var isApplying = false

    var body: some View {
        MiniDiffCardChrome(
            icon: "brain.head.profile",
            status: chromeStatus,
            pendingLabel: "MEMORY UPDATE",
            countLabel: "\(proposal.ops.count) update\(proposal.ops.count == 1 ? "" : "s")",
            reasoning: proposal.reasoning,
            canApply: canApply,
            onApply: apply,
            onReject: reject
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(proposal.ops.enumerated()), id: \.offset) { _, op in
                    row(op)
                }
            }
        }
    }

    // MARK: - Pieces

    private var chromeStatus: MiniDiffCardStatus {
        switch proposal.status {
        case .pending:  return .pending
        case .applied:  return .applied
        case .rejected: return .rejected
        }
    }

    private func row(_ op: MemoryOp) -> some View {
        HStack(spacing: 6) {
            Text(prefix(for: op.op))
                .font(.custom("JetBrainsMono-SemiBold", size: 10))
                .foregroundStyle(color(for: op.op))
                .frame(width: 34, alignment: .leading)
            Text(op.value)
                .font(.monoXS)
                .foregroundStyle(Color.ink)
                .strikethrough(op.op.hasPrefix("remove"), color: Color.ink3)
            Spacer(minLength: 0)
            Text(target(for: op.op))
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
    }

    private func prefix(for op: String) -> String {
        op.hasPrefix("remove") ? "REMOVE" : "ADD"
    }

    private func color(for op: String) -> Color {
        op.hasPrefix("remove") ? Color.danger : Color.ok
    }

    private func target(for op: String) -> String {
        op.contains("constraint") ? "constraints" : "dislikes"
    }

    // MARK: - Logic

    private var canApply: Bool {
        proposal.status == .pending && !proposal.ops.isEmpty && !isApplying
    }

    private func apply() {
        guard canApply else { return }
        isApplying = true
        memoryStore.update { mem in
            for op in proposal.ops {
                let trimmed = op.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                switch op.op {
                case "add_dislike":
                    if !mem.dislikes.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        mem.dislikes.append(trimmed)
                    }
                case "remove_dislike":
                    mem.dislikes.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
                case "add_constraint":
                    if !mem.constraints.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        mem.constraints.append(trimmed)
                    }
                case "remove_constraint":
                    mem.constraints.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
                default:
                    break
                }
            }
        }
        conv.setMemoryProposalStatus(messageId: messageId, .applied)
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }

    private func reject() {
        conv.setMemoryProposalStatus(messageId: messageId, .rejected)
    }
}
