// RestTimerLiveActivity.swift: Lock Screen and Dynamic Island rest countdown.
//
// The countdown is `Text(timerInterval:)`, which the system ticks without
// updates. At zero the system cannot run our code, so "Rest done" comes from
// two sources: `isStale` (the app sets staleDate to the rest end date, so the
// activity goes stale when the rest runs out) and `state.finished` (the app
// sends it when it is foregrounded at expiry). The timer text itself also
// stops at 0:00.

import ActivityKit
import SwiftUI
import WidgetKit

private func setLine(_ s: RestActivityState) -> String {
    "After set \(s.setNumber) of \(s.totalSets)"
}

/// Countdown, or "Rest done" once the rest has run out.
private struct RestCountdown: View {
    let state: RestActivityState
    let isStale: Bool
    var size: CGFloat = 34

    var body: some View {
        if state.finished || isStale {
            Text("Rest done")
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(Palette.accent)
        } else {
            Text(timerInterval: Date.now...max(Date.now, state.restEndDate), countsDown: true)
                .font(.system(size: size, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Palette.accent)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.workoutName)
                        .font(.caption)
                        .foregroundStyle(Palette.ink2)
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(setLine(context.state))
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 12)
                RestCountdown(state: context.state, isStale: context.isStale)
            }
            .padding(16)
            .activityBackgroundTint(Palette.bg)
            .activitySystemActionForegroundColor(Palette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(setLine(context.state))
                            .font(.caption)
                            .foregroundStyle(Palette.ink2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(state: context.state, isStale: context.isStale, size: 28)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Palette.accent)
            } compactTrailing: {
                RestCountdown(state: context.state, isStale: context.isStale, size: 13)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Palette.accent)
            }
            .keylineTint(Palette.accent)
        }
    }
}
