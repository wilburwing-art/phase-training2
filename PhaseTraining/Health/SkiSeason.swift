// SkiSeason.swift — this season's days on snow, from Apple Health and the
// sport log.
//
// A day counts when the watch (or any outside app) recorded a downhill
// skiing, snowboarding or snow sports workout on it, or the user logged a
// ski sport that day (by hand or by confirming a detection banner). The two
// sources are unioned per day, so a confirmed banner and the workout behind
// it count once. Cross-country is a different load and stays out.
//
// No duration floor: detection waits for 30 minutes before it prompts, but
// a short lap is still a day on snow. The season starts Aug 1, which assumes
// a northern hemisphere winter.
//
// Vertical is the sum of `HKMetadataKeyElevationDescended` over the
// workouts that carry it. HealthKit marks the key optional, so the card
// says how many days it covers rather than presenting a partial total as
// the season's.

import Foundation
import HealthKit

struct SkiSeasonSummary: Equatable {
    var days: Int
    /// Nil when no counted workout carried a descent value.
    var verticalMeters: Double?
    var daysWithVertical: Int
    var lastDay: Date?
    var seasonStart: Date
}

enum SkiSeason {

    static let countedTypes: Set<HKWorkoutActivityType> = [.downhillSkiing, .snowboarding, .snowSports]

    static func isSkiSport(_ slug: String) -> Bool {
        SportProfile.of(slug).isSki
    }

    /// Aug 1 on or before `now`.
    static func seasonStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let year = calendar.component(.year, from: now)
        let thisYear = calendar.date(from: DateComponents(year: year, month: 8, day: 1))!
        return now >= thisYear ? thisYear : calendar.date(from: DateComponents(year: year - 1, month: 8, day: 1))!
    }

    static func summarize(workouts: [HKWorkoutLike],
                          sportLogs: [SportLogEntry],
                          now: Date = Date(),
                          calendar: Calendar = .current) -> SkiSeasonSummary {
        let start = seasonStart(now: now, calendar: calendar)
        let inSeason: (Date) -> Bool = { $0 >= start && $0 <= now }

        let skiWorkouts = workouts.filter {
            !$0.isOwn && countedTypes.contains($0.activityType) && inSeason($0.startDate)
        }
        var days = Set(skiWorkouts.map { calendar.startOfDay(for: $0.startDate) })
        days.formUnion(sportLogs
            .filter { isSkiSport($0.sport.slug) && inSeason($0.date) }
            .map { calendar.startOfDay(for: $0.date) })

        let withVertical = skiWorkouts.filter { $0.elevationDescendedMeters != nil }
        let vertical = withVertical.isEmpty ? nil : withVertical.reduce(0) { $0 + ($1.elevationDescendedMeters ?? 0) }
        let verticalDays = Set(withVertical.map { calendar.startOfDay(for: $0.startDate) })

        return SkiSeasonSummary(days: days.count,
                                verticalMeters: vertical,
                                daysWithVertical: verticalDays.count,
                                lastDay: days.max(),
                                seasonStart: start)
    }

    /// "48,200 ft" / "14,690 m".
    static func verticalLabel(meters: Double, imperial: Bool) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let value = imperial ? meters / 0.3048 : meters
        return "\(f.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))") \(imperial ? "ft" : "m")"
    }
}
