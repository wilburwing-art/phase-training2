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

                Button(action: onAccept) {
                    Text(proposedDiff != nil ? "Accept" : "Got it")
                        .styled(.monoXS)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("missed-banner-accept")
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

    /// Short summary line — either where it moved to, or that we dropped.
    private var actionSummary: String {
        guard let diff = proposedDiff else {
            return "Already a full week — leaving it skipped"
        }
        // First .move edit's target date drives the summary.
        for edit in diff.edits {
            if case .move(_, let toDate) = edit {
                let f = DateFormatter()
                f.dateFormat = "EEEE"
                return "Moving to \(f.string(from: toDate))"
            }
        }
        return "Plan updated"
    }

    private var weekdayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: missedDay.date)
    }

    private func editDescription(_ edit: PlanEdit) -> String {
        switch edit {
        case .move(_, let toDate):
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return "  → moves to \(f.string(from: toDate))"
        case .swapKind(_, let to, let title, _):
            return "  → \(title) (\(to.label.lowercased()))"
        case .protectDay(_, let title):
            return "  → protect as \(title)"
        case .shorten(_, let mins):
            return "  → shorten to \(mins) min"
        case .addSession(let date, _, let title, _):
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return "  → \(title) on \(f.string(from: date))"
        case .removeSession:
            return "  → remove"
        }
    }
}
