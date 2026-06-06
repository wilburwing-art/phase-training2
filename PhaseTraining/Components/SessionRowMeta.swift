// SessionRowMeta.swift — shared date/duration formatting for session rows.
//
// HistoryScreen's accordion rows and ProgressScreen's "Recent sessions"
// card both render a "MMM d" date plus an h/m duration. The hour-plus
// string is identical ("1h 5m"); below an hour the screens deliberately
// diverge — History's tight meta line uses "42m", Progress's roomier card
// uses "42 min" — so the sub-hour suffix is a style knob, not a fork.

import Foundation

enum SessionRowMeta {
    /// Cached — both screens call this per row per render; allocating a
    /// DateFormatter each call is needless churn.
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "MMM d" — e.g. "Jun 5". Progress uppercases at the call site.
    static func monthDayLabel(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    enum DurationStyle {
        case compact  // "42m"    (History meta line)
        case spelled  // "42 min" (Progress recent-sessions card)
    }

    /// "1h 5m" at an hour or more; sub-hour rendering per `style`.
    static func durationLabel(_ seconds: Int, style: DurationStyle) -> String {
        let minutes = max(0, seconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        switch style {
        case .compact: return "\(minutes)m"
        case .spelled: return "\(minutes) min"
        }
    }
}
