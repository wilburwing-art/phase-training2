// MissedWorkoutBanner.swift — PR 8 of the weekly-coach roadmap.
//
// Today-tab banner that surfaces a planned workout the user missed
// (planned lift/sport day passed without a logged session). One banner
// per missed day; when the user resolves one, the next pending miss
// (if any) becomes the new banner subject.
//
// The autopilot has already decided what to do — either reshuffle to
// a future rest day, or drop entirely (drop-rule fired or no valid
// target). The user accepts the proposal, undoes it, or dismisses
// entirely. Either way the miss gets logged into `PlanStore.missedWorkouts`
// so we don't re-banner the same date.

import SwiftUI

struct MissedWorkoutBanner: View {
    let missedDay: DayPlan
    /// nil when the autopilot decided not to reshuffle (drop rule fired
    /// or no valid target). In that case the banner just informs the
    /// user without offering a "see changes" affordance.
    let proposedDiff: PlanDiff?
    let onAccept: () -> Void
    let onDismiss: () -> Void
    /// D3 — present when the week can't cleanly absorb the missed workout but
    /// CAN be consolidated onto fewer lift days (PRD §6 Q4). When set, the
    /// primary button offers "Consolidate" instead of "Got it".
    var onConsolidate: (() -> Void)? = nil

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header — always visible
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Missed \(weekdayLabel)'s \(missedDay.title)")
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                    Text(actionSummary)
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 4)
            }
            .accessibilityIdentifier("missed-banner-header")

            if expanded, let diff = proposedDiff {
                Divider().background(Color.lineSoft)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(diff.edits.enumerated()), id: \.offset) { _, edit in
                        Text(editDescription(edit))
                            .styled(.monoXS)
                            .foregroundStyle(Color.ink2)
                    }
                }
                .padding(.leading, 26)
            }

            HStack(spacing: 8) {
                if proposedDiff != nil {
                    Button(action: { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }) {
                        Text(expanded ? "Hide changes" : "See changes")
                            .styled(.monoXS)
                            .foregroundStyle(Color.ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("missed-banner-see-changes")
                }
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Text("Skip")
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.line, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("missed-banner-skip")

                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .styled(.monoXS)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(offersConsolidation ? "missed-banner-consolidate" : "missed-banner-accept")
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color.accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// True when no clean reshuffle exists but consolidation is on offer.
    private var offersConsolidation: Bool { proposedDiff == nil && onConsolidate != nil }

    private var primaryLabel: String {
        if proposedDiff != nil { return "Accept" }
        if offersConsolidation { return "Consolidate" }
        return "Got it"
    }

    private var primaryAction: () -> Void {
        if offersConsolidation, let onConsolidate { return onConsolidate }
        return onAccept
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let shortWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Short summary line — where it moved to, that we'll consolidate, or that
    /// we dropped.
    private var actionSummary: String {
        if let diff = proposedDiff {
            // First .move edit's target date drives the summary.
            for edit in diff.edits {
                if case .move(_, let toDate) = edit {
                    return "Moving to \(Self.weekdayFormatter.string(from: toDate))"
                }
            }
            return "Plan updated"
        }
        if offersConsolidation {
            return "No room to move it — consolidate the week instead?"
        }
        return "Already a full week — leaving it skipped"
    }

    private var weekdayLabel: String {
        Self.weekdayFormatter.string(from: missedDay.date)
    }

    private func editDescription(_ edit: PlanEdit) -> String {
        switch edit {
        case .move(_, let toDate):
            return "  → moves to \(Self.shortWeekdayFormatter.string(from: toDate))"
        case .swapKind(_, let to, let title, _, _, _):
            return "  → \(title) (\(to.label.lowercased()))"
        case .protectDay(_, let title):
            return "  → protect as \(title)"
        case .shorten(_, let mins):
            return "  → shorten to \(mins) min"
        case .addSession(let date, _, let title, _, _, _):
            return "  → \(title) on \(Self.shortWeekdayFormatter.string(from: date))"
        case .removeSession:
            return "  → remove"
        }
    }
}
