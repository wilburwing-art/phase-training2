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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let reason = proposal.reasoning {
                Text(reason)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(proposal.ops.enumerated()), id: \.offset) { _, op in
                    row(op)
                }
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
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text(statusLabel)
                .styled(.micro)
                .foregroundStyle(statusColor)
            Spacer()
            Text("\(proposal.ops.count) update\(proposal.ops.count == 1 ? "" : "s")")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
    }

    private var statusLabel: String {
        switch proposal.status {
        case .pending:  return "MEMORY UPDATE"
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
        proposal.status == .pending && !proposal.ops.isEmpty
    }

    private func apply() {
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
