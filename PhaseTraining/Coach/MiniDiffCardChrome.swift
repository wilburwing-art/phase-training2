// MiniDiffCardChrome.swift — shared chrome for the Mini*DiffCard family.
//
// Extracted from MiniPlanDiffCard / MiniWorkoutDiffCard / MiniMemoryDiffCard:
// the card container styling, header (icon + status + count), optional
// reasoning paragraph, and the Reject/Apply action bar. Per-card LOGIC stays
// in the call sites — resolution against PlanStore / SessionStore /
// MemoryStore, the canApply computation, and the apply/reject side effects
// are intentionally NOT unified here: the three apply paths hit different
// stores with different resolution semantics (workout diffs apply by id,
// not name).

import SwiftUI

/// Presentation-level mirror of the per-proposal `Status` enums.
/// CoachProposal.Status / CoachWorkoutProposal.Status /
/// CoachMemoryProposal.Status are three distinct persisted Codable types and
/// stay untouched; each card maps its own status into this one for display.
enum MiniDiffCardStatus {
    case pending
    case applied
    case rejected
}

struct MiniDiffCardChrome<Rows: View>: View {
    /// SF Symbol shown at the leading edge of the header.
    let icon: String
    let status: MiniDiffCardStatus
    /// Header label shown while the proposal is pending
    /// ("PROPOSAL" / "WORKOUT TWEAK" / "MEMORY UPDATE").
    let pendingLabel: String
    /// Trailing header count ("3 edits" / "1 change" / "2 updates").
    let countLabel: String
    let reasoning: String?
    let canApply: Bool
    let onApply: () -> Void
    let onReject: () -> Void
    let rows: () -> Rows

    init(
        icon: String,
        status: MiniDiffCardStatus,
        pendingLabel: String,
        countLabel: String,
        reasoning: String?,
        canApply: Bool,
        onApply: @escaping () -> Void,
        onReject: @escaping () -> Void,
        @ViewBuilder rows: @escaping () -> Rows
    ) {
        self.icon = icon
        self.status = status
        self.pendingLabel = pendingLabel
        self.countLabel = countLabel
        self.reasoning = reasoning
        self.canApply = canApply
        self.onApply = onApply
        self.onReject = onReject
        self.rows = rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let reason = reasoning {
                Text(reason)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            rows()
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
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text(statusLabel)
                .styled(.micro)
                .foregroundStyle(statusColor)
            Spacer()
            Text(countLabel)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
    }

    private var statusLabel: String {
        switch status {
        case .pending:  return pendingLabel
        case .applied:  return "APPLIED"
        case .rejected: return "REJECTED"
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending:  return Color.accent
        case .applied:  return Color.ok
        case .rejected: return Color.ink3
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(action: onReject) {
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
            .disabled(status != .pending)

            Button(action: onApply) {
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
}
