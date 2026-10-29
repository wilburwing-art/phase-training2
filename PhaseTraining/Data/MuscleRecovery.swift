// MuscleRecovery.swift — which muscle groups a session on a given day must
// leave alone, and which it should go easy on.
//
// Rule one of the coach: never prescribe an exercise whose prime mover is
// still recovering. A group below `blockBelow` is blocked: the generator
// drops every movement that uses it as a prime mover. Between `blockBelow`
// and `recoveredAt` it is eased: those movements rank last and cap at RPE 7.
// At `recoveredAt` (about 80%, the point Fitbod also trains a muscle) it is
// fair game.
//
// Freshness comes from logged volume (MuscleFreshness). The soreness
// check-in overrides it, because the athlete knows better than a model:
// "high" or a pain flag blocks the area, "mild" eases it, and a "none"
// check-in newer than the last session that loaded the area clears it.

import Foundation

struct RecoveryStatus: Equatable {
    /// MuscleBucket raw values no movement may load as a prime mover.
    var blocked: Set<String> = []
    /// MuscleBucket raw values to rank last and cap at RPE 7.
    var eased: Set<String> = []
    /// Model freshness 0...1 per bucket that has any recent load, for copy.
    var freshness: [String: Double] = [:]

    static let none = RecoveryStatus()
}

enum MuscleRecovery {

    /// Below this a group is blocked.
    static let blockBelow = 0.5
    /// At or above this a group is recovered. Between the two it is eased.
    static let recoveredAt = 0.8

    /// Where in the day a planned session is assumed to happen: noon, or now
    /// when the day is today and noon has passed.
    static func anchor(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let noon = calendar.startOfDay(for: date).addingTimeInterval(12 * 3600)
        return calendar.isDate(date, inSameDayAs: now) ? max(noon, now) : noon
    }

    /// Bucket freshness at `at`: the least recovered member slug.
    static func bucketFreshness(exposures: [MuscleFreshness.Exposure], at: Date) -> [String: Double] {
        let loaded = Set(exposures.flatMap { $0.loads.keys })
        var out: [String: Double] = [:]
        for slug in loaded {
            guard let bucket = MuscleBucket.bucket(forSlug: slug)?.rawValue else { continue }
            let f = MuscleFreshness.freshness(of: slug, exposures: exposures, at: at)
            out[bucket] = min(out[bucket] ?? 1, f)
        }
        return out
    }

    /// Recovery picture for a session on `date`.
    /// - Parameters:
    ///   - exposures: logged sessions' muscle loads (`MuscleFreshness.exposures`).
    ///   - soreness: the athlete's check-ins (`TrainingMemory.soreness`).
    static func status(on date: Date,
                       exposures: [MuscleFreshness.Exposure],
                       soreness: [SorenessEntry],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> RecoveryStatus {
        let at = anchor(for: date, now: now, calendar: calendar)
        let fresh = bucketFreshness(exposures: exposures, at: at)
        var status = RecoveryStatus(freshness: fresh)
        for (bucket, f) in fresh {
            if f < blockBelow { status.blocked.insert(bucket) }
            else if f < recoveredAt { status.eased.insert(bucket) }
        }

        // The check-in: the latest one dated that day or the day before.
        let day = calendar.startOfDay(for: date)
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: day),
              let entry = soreness
                .filter({ let d = calendar.startOfDay(for: $0.date); return (d == day || d == dayBefore) && $0.date <= at })
                .max(by: { $0.date < $1.date })
        else { return status }

        if entry.soreness == "high" || entry.pain {
            let areas = Set(entry.areas).intersection(MuscleBucket.sorenessPrimarySlugs)
            status.blocked.formUnion(areas)
            status.eased.subtract(areas)
        } else if entry.soreness == "mild" {
            let areas = Set(entry.areas).intersection(MuscleBucket.sorenessPrimarySlugs)
            status.eased.formUnion(areas.subtracting(status.blocked))
        } else if entry.soreness == "none" {
            // Feeling fine after the last session that loaded a group beats
            // the model's estimate for that group.
            for bucket in status.blocked.union(status.eased) {
                let members = Set(MuscleBucket(rawValue: bucket)?.memberSlugs ?? [])
                let lastLoad = exposures
                    .filter { e in e.loads.keys.contains { members.contains($0) } && e.start <= at }
                    .map(\.start).max()
                if let lastLoad, entry.date > lastLoad {
                    status.blocked.remove(bucket)
                    status.eased.remove(bucket)
                }
            }
        }
        return status
    }
}
