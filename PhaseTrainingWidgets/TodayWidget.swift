// TodayWidget.swift: Home Screen and Lock Screen widget for today's planned day.
//
// Reads TodayWidgetSnapshot from the App Group defaults. The timeline carries
// one entry per midnight the snapshot covers, so the right day shows after
// midnight without the app running. The app reloads the timeline whenever the
// snapshot changes.

import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    /// Nil renders the empty state.
    let day: TodayWidgetDay?
}

struct TodayProvider: TimelineProvider {
    private let calendar = Calendar.current

    private func snapshot() -> TodayWidgetSnapshot? {
        TodayWidgetSnapshot.load(from: UserDefaults(suiteName: TodayWidgetSnapshot.appGroup))
    }

    private func entry(at date: Date, in snapshot: TodayWidgetSnapshot?) -> TodayEntry {
        TodayEntry(date: date, day: TodayWidgetTimeline.day(at: date, in: snapshot, calendar: calendar))
    }

    func placeholder(in context: Context) -> TodayEntry {
        entry(at: Date(), in: snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(at: Date(), in: snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = snapshot()
        let entries = TodayWidgetTimeline.entryDates(now: Date(), snapshot: snapshot, calendar: calendar)
            .map { entry(at: $0, in: snapshot) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

private struct TodayEyebrow: View {
    let date: Date

    var body: some View {
        Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(Palette.ink2)
            .lineLimit(1)
    }
}

private struct TodaySmallView: View {
    let entry: TodayEntry
    private var text: TodayWidgetText { TodayWidgetText(day: entry.day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TodayEyebrow(date: entry.date)
            Text(text.title)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if text.done, let detail = text.detail {
                Label(detail, systemImage: "checkmark.circle.fill")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
            } else if let detail = text.detail {
                Text(detail)
                    .font(.system(.footnote))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TodayAccessoryView: View {
    let entry: TodayEntry
    private var text: TodayWidgetText { TodayWidgetText(day: entry.day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text.title)
                .font(.system(.headline))
                .lineLimit(1)
            if let detail = text.detail {
                Text(detail)
                    .font(.system(.caption))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            TodayAccessoryView(entry: entry)
                .widgetURL(URL(string: "phasetraining://today"))
                .containerBackground(for: .widget) { Color.clear }
        default:
            TodaySmallView(entry: entry)
                .widgetURL(URL(string: "phasetraining://today"))
                .containerBackground(for: .widget) { Palette.bg }
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayWidgetSnapshot.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Today's planned session.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
