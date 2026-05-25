// PlanDiffSheet.swift — bottom-sheet preview for a PlanDiff.
//
// Rendered when the user picks any plan-edit menu item on WeekScreen. Shows
// the before/after week side by side, the list of edits as labels, optional
// reasoning copy, and Apply / Cancel. Apply calls PlanStore.apply(diff) and
// dismisses; Cancel dismisses without mutating.

import SwiftUI

struct PlanDiffSheet: View {
    let diff: PlanDiff
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            handle
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let reasoning = diff.reasoning {
                        reasoningBlock(reasoning)
                    }
                    editsList
                    weekColumn(title: "BEFORE", week: diff.before)
                    weekColumn(title: "AFTER",  week: diff.after, highlight: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            bottomBar
        }
        .background(Color.bg.ignoresSafeArea())
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var handle: some View {
        Capsule()
            .fill(Color.line)
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PREVIEW")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text(diff.isNoop ? "No change" : "Review edit")
                .font(.custom("SpaceGrotesk-SemiBold", size: 26))
                .tracking(-0.025 * 26)
                .foregroundStyle(Color.ink)
        }
    }

    private func reasoningBlock(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(Color.accent)
                .padding(.top, 2)
            Text(text)
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(diff.edits.enumerated()), id: \.offset) { _, edit in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ink3)
                    Text(edit.label)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink2)
                }
            }
        }
    }

    private func weekColumn(title: String, week: WeekPlan, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(highlight ? Color.accent : Color.ink3)
            VStack(spacing: 6) {
                ForEach(week.days) { day in
                    DiffDayRow(day: day, highlight: highlight)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("Cancel")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.line, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button(action: onApply) {
                Text("Apply")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                    .foregroundStyle(Color.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(diff.isNoop ? Color.accentDim : Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(diff.isNoop)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Color.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.line).frame(height: 0.5)
        }
    }
}

private struct DiffDayRow: View {
    let day: DayPlan
    let highlight: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(weekdayShort)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .frame(width: 32, alignment: .leading)
            Text(day.kind.label)
                .styled(.micro)
                .foregroundStyle(Color.accentInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(kindColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(day.title)
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let mins = day.durationMinutes {
                Text("\(mins)m")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            if day.protected {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.ink3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(highlight ? Color.accentWash : Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(highlight ? Color.accentBorder : Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var weekdayShort: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: day.date).uppercased()
    }

    private var kindColor: Color {
        switch day.kind {
        case .lift:  return Color.accent
        case .sport: return Color.ok.opacity(0.85)
        case .rest:  return Color.elevated
        case .event: return Color.danger.opacity(0.9)
        }
    }
}

#Preview {
    let before = WeekPlan.sample()
    var after = before
    PlanStore.applyEdit(
        .swapKind(dayId: before.days[3].id, to: .rest, title: "Rest", routineId: nil),
        to: &after
    )
    let diff = PlanDiff(
        before: before, after: after,
        edits: [.swapKind(dayId: before.days[3].id, to: .rest, title: "Rest", routineId: nil)],
        reasoning: "You said you wanted Thursdays off."
    )
    return PlanDiffSheet(diff: diff, onApply: {}, onCancel: {})
}
