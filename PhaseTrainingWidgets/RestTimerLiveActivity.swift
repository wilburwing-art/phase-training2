// RestTimerLiveActivity.swift: Lock Screen and Dynamic Island rest countdown.
//
// The countdown is `Text(timerInterval:)`, which the system ticks without
// updates. At zero the system cannot run our code, so "Rest done" comes from
// two sources: `isStale` (the app sets staleDate to the rest end date, so the
// activity goes stale when the rest runs out) and `state.finished` (the app
// sends it when it is foregrounded at expiry). The timer text itself also
// stops at 0:00.

import ActivityKit
import AppIntents
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
    /// Follows the reader's text size; the fixed `size` is the base at the
    /// default setting.
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    var body: some View {
        if state.finished || isStale {
            Text("Rest done")
                .font(.system(size: size * 0.6 * scale, weight: .semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Palette.accent)
        } else {
            Text(timerInterval: Date.now...max(Date.now, state.restEndDate), countsDown: true)
                .font(.system(size: size * scale, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Palette.accent)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Rest remaining")
                .accessibilityValue(Text(timerInterval: Date.now...max(Date.now, state.restEndDate), countsDown: true))
        }
    }
}

/// Skip and +15, run in the app through `RestActivityIntents`. Hidden once the
/// rest is done: there is nothing left to skip or extend.
private struct RestButtons: View {
    let state: RestActivityState
    let isStale: Bool

    var body: some View {
        if !(state.finished || isStale) {
            HStack(spacing: 8) {
                Button(intent: SkipRestActivityIntent()) {
                    Label("Skip", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Skip rest")
                Button(intent: AddRestActivityIntent(seconds: 15)) {
                    Label("+15s", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Add 15 seconds")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Palette.accent)
        }
    }
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            VStack(spacing: 12) {
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
                RestButtons(state: context.state, isStale: context.isStale)
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
                DynamicIslandExpandedRegion(.bottom) {
                    RestButtons(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Palette.accent)
                    .accessibilityLabel("Rest timer")
            } compactTrailing: {
                RestCountdown(state: context.state, isStale: context.isStale, size: 13)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Palette.accent)
                    .accessibilityLabel("Rest timer")
            }
            .keylineTint(Palette.accent)
        }
    }
}
