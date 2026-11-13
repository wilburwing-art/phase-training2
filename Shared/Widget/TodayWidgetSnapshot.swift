// TodayWidgetSnapshot.swift: the week's plan as the Today widget reads it.
//
// The app writes this into the App Group defaults; the widget extension reads
// only this value and never decodes the app's plan types. Foundation only, so
// the watch target (which compiles all of Shared/) builds it too.

import Foundation

struct TodayWidgetDay: Codable, Hashable {
    enum Kind: String, Codable { case lift, sport, rest, event }
    /// Start of day, local calendar.
    var date: Date
    var kind: Kind
    /// "Upper Day 1", "Skiing", "Rest day", an event title.
    var title: String
    /// "6 exercises · 18 sets", "About 45 min", nil.
    var detail: String?
    var done: Bool
}

struct TodayWidgetSnapshot: Codable, Hashable {
    static let appGroup = "group.com.phasetraining.app"
    static let defaultsKey = "pt_today_widget_snapshot"
    static let widgetKind = "TodayWidget"

    var days: [TodayWidgetDay]

    func day(on date: Date, calendar: Calendar = .current) -> TodayWidgetDay? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    /// Nil when the value is missing or does not decode.
    static func load(from defaults: UserDefaults?) -> TodayWidgetSnapshot? {
        guard let data = defaults?.data(forKey: defaultsKey) else { return nil }
        return try? decoder.decode(TodayWidgetSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults?) {
        guard let data = try? Self.encoder.encode(self) else { return }
        defaults?.set(data, forKey: Self.defaultsKey)
    }
}
