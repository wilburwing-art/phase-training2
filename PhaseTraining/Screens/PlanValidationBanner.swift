// PlanValidationBanner.swift — PR 7 of the weekly-coach roadmap.
//
// Inline banner that surfaces PlanValidationIssue rows below the Week
// tab header. Each row shows the issue title with a severity icon; the
// row expands inline on tap to reveal the explanation + a "Got it"
// acknowledgement button. Acknowledging logs a WeeklyPlanOverride
// via PlanStore — three weeks in a row on the same (rule, pattern)
// and the rule self-suppresses for that user.
//
// Layout: shows up to 2 issues by default. When more exist, a
// "+N more" affordance expands the full list (rare — most plans
// produce 0-1 issues).

import SwiftUI

struct PlanValidationBanner: View {
    let issues: [PlanValidationIssue]
    let onAcknowledge: (PlanValidationIssue) -> Void

    @State private var expandedIssueID: UUID? = nil
    @State private var showAll: Bool = false

    /// How many issue rows we render by default. Anything past this
    /// hides behind a "+N more" toggle. Two strikes the balance for
    /// the common case (most plans yield 0-1 issues; surfacing all 5+
    /// at once is overwhelming on a 7-day strip).
    private static let visibleByDefault = 2

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleIssues) { issue in
                    IssueRow(
                        issue: issue,
                        isExpanded: expandedIssueID == issue.id,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedIssueID = (expandedIssueID == issue.id) ? nil : issue.id
                            }
                        },
                        onAcknowledge: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onAcknowledge(issue)
                                if expandedIssueID == issue.id {
                                    expandedIssueID = nil
                                }
                            }
                        }
                    )
                }
                if hiddenCount > 0 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) { showAll.toggle() }
                    }) {
                        Text(showAll ? "Show fewer" : "+\(hiddenCount) more")
                            .styled(.monoXS)
                            .foregroundStyle(Color.ink2)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityIdentifier("plan-issues-show-more")
                }
            }
        }
    }

    private var visibleIssues: [PlanValidationIssue] {
        showAll ? issues : Array(issues.prefix(Self.visibleByDefault))
    }

    private var hiddenCount: Int {
        max(0, issues.count - Self.visibleByDefault)
    }
}

// MARK: - IssueRow

private struct IssueRow: View {
    let issue: PlanValidationIssue
    let isExpanded: Bool
    let onTap: () -> Void
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: issue.severity.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(severityColor)
                        .frame(width: 14, alignment: .center)
                        .padding(.top, 2)
                    Text(issue.title)
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.ink3)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityIdentifier("plan-issue-\(issue.ruleKey)")

            if isExpanded {
                Text(issue.explanation)
                    .styled(.monoXS)
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)

                Button(action: onAcknowledge) {
                    Text("Got it")
                        .styled(.monoXS)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.leading, 22)
                .padding(.top, 2)
                .accessibilityIdentifier("plan-issue-ack-\(issue.ruleKey)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(severityBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var severityColor: Color {
        switch issue.severity {
        case .info:   return Color.ink2
        case .warn:   return Color.accent
        case .strong: return Color.danger
        }
    }

    private var rowBackground: Color {
        switch issue.severity {
        case .info:   return Color.surface
        case .warn:   return Color.accentWash
        case .strong: return Color.danger.opacity(0.08)
        }
    }

    private var severityBorder: Color {
        switch issue.severity {
        case .info:   return Color.line
        case .warn:   return Color.accentBorder
        case .strong: return Color.danger.opacity(0.4)
        }
    }
}
