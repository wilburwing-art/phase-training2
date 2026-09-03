// DetectedActivityBanner.swift — Today-tab confirm card for a sport
// activity found in Apple Health that the app didn't know about (see
// ActivityDetection.swift for the detection rules).
//
// One banner per detected outing; resolving it (confirm or skip) promotes
// the next pending one, mirroring the MissedWorkoutBanner pattern. The
// banner is intentionally two-tap-max: primary confirms with the
// suggested intensity, Skip makes it go away forever. Fine-tuning the
// entry (intensity, note) stays in the existing sport-log sheet.

import SwiftUI

struct DetectedActivityBanner: View {
    let activity: DetectedActivity
    /// True when confirming also rebalances the current plan week (the
    /// outing is in this training week and its day isn't already a
    /// planned sport day). Drives the copy + primary button label.
    let adjustsWeek: Bool
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Looks like you went \(activity.activityLabel.lowercased()) \(dayLabel)")
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                    Text("\(durationLabel) · from Apple Health")
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 4)
            }
            .accessibilityIdentifier("detected-activity-header")

            Text(adjustsWeek
                 ? "Confirm and I'll log it and rebalance your week around it."
                 : "Confirm and I'll log it so your training signal stays accurate.")
                .styled(.monoXS)
                .foregroundStyle(Color.ink2)
                .padding(.leading, 26)

            HStack(spacing: 8) {
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Text("Not me")
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
                .accessibilityIdentifier("detected-activity-skip")

                Button(action: onConfirm) {
                    Text(adjustsWeek ? "Log & adjust" : "Log it")
                        .styled(.monoXS)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detected-activity-confirm")
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

    // MARK: - Labels

    /// SF Symbol per detected sport. Fallback is the generic runner —
    /// every slug here matches Sport.catalog / ActivityDetector.mapping.
    private var iconName: String {
        switch activity.sport.slug {
        case "alpine-skiing", "snow-sports": return "figure.skiing.downhill"
        case "snowboarding":                 return "figure.snowboarding"
        case "climbing":                     return "figure.climbing"
        case "hiking-trekking":              return "figure.hiking"
        case "cycling":                      return "figure.outdoor.cycle"
        case "swimming":                     return "figure.pool.swim"
        case "surfing":                      return "figure.surfing"
        case "rowing":                       return "figure.rower"
        default:                             return "figure.run"
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    /// "today" / "yesterday" / weekday name — banner copy reads as a
    /// sentence, so the label is lowercase except weekday names.
    private var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(activity.startTime) { return "today" }
        if cal.isDateInYesterday(activity.startTime) { return "yesterday" }
        return "on \(Self.weekdayFormatter.string(from: activity.startTime))"
    }

    private var durationLabel: String {
        let h = activity.durationMinutes / 60
        let m = activity.durationMinutes % 60
        if h > 0 && m > 0 { return "\(h) hr \(m) min" }
        if h > 0 { return "\(h) hr" }
        return "\(m) min"
    }
}
