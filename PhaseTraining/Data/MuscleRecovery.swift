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
// check-in adds to it: "high" or a pain flag blocks the area, "mild" eases
// it. A "none" check-in newer than the last session that loaded an area
// clears the EASED tier only. It never lifts a block: soreness lags the
// work by a day or two, so "not sore" the morning after heavy legs is not
// "recovered", and the Recovery card would still read 22% beside a plan
// that trains the same legs again.
//
// The same check-in also carries today's energy and time chip. Both are about
// the morning they were given, so they apply only to a session on that day.
// `equipmentChanged` is deliberately left to the coach: the generator has no
// notion of a one-day equipment set, and the user's saved equipment is the
// plan's input.

import Foundation

struct RecoveryStatus: Equatable {
    /// MuscleBucket raw values no movement may load as a prime mover.
    var blocked: Set<String> = []
    /// MuscleBucket raw values to rank last and cap at RPE 7.
    var eased: Set<String> = []
    /// Model freshness 0...1 per bucket that has any recent load, for copy.
    var freshness: [String: Double] = [:]
    /// Today's check-in said energy is "low": the session eases (RPE capped
    /// at 7, one fewer set on every movement but the lead lift). Only a
    /// check-in dated the session's own day counts, since energy describes
    /// that morning.
    var lowEnergy = false
    /// Minutes the athlete has for the session, from a same-day check-in's
    /// time chip. Replaces the profile's session length for that day.
    var timeBudget: Int? = nil

    static let none = RecoveryStatus()
}

enum MuscleRecovery {

    /// Below this a group is blocked.
    static let blockBelow = 0.5
    /// At or above this a group is recovered. Between the two it is eased.
    static let recoveredAt = 0.8

    /// How long a post-workout hurt report keeps easing the areas it names.
    static let hurtWindow: TimeInterval = 36 * 3600

    /// Muscle buckets around each joint the post-workout sheet offers
    /// ("lower back", "knee", ...). A joint is not a muscle, so each maps to
    /// the groups that load it. Unknown words map to nothing.
    static func buckets(forHurtArea area: String) -> Set<String> {
        switch area.lowercased().trimmingCharacters(in: .whitespaces) {
        case "knee":       return [MuscleBucket.quads, .hamstrings].mapSet
        case "shoulder":   return [MuscleBucket.shoulders].mapSet
        case "lower back": return [MuscleBucket.back, .glutes].mapSet
        case "elbow":      return [MuscleBucket.biceps, .triceps, .forearms].mapSet
        case "wrist":      return [MuscleBucket.forearms].mapSet
        case "neck":       return [MuscleBucket.shoulders, .back].mapSet
        case "hip":        return [MuscleBucket.glutes, .quads].mapSet
        case "ankle":      return [MuscleBucket.calves].mapSet
        default:           return []
        }
    }

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
    ///   - feedback: post-workout reports (`TrainingMemory.feedback`). A hurt
    ///     joint named in one within `hurtWindow` before the session eases the
    ///     muscles around it.
    static func status(on date: Date,
                       exposures: [MuscleFreshness.Exposure],
                       soreness: [SorenessEntry],
                       feedback: [FeedbackEntry] = [],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> RecoveryStatus {
        let at = anchor(for: date, now: now, calendar: calendar)
        let fresh = bucketFreshness(exposures: exposures, at: at)
        var status = RecoveryStatus(freshness: fresh)
        for (bucket, f) in fresh {
            if f < blockBelow { status.blocked.insert(bucket) }
            else if f < recoveredAt { status.eased.insert(bucket) }
        }
        // Hurt after the last workout: the next session leaves those muscles
        // to the easier end of their demand. Eased, never blocked, because the
        // report names a joint and says nothing about how bad it is.
        for entry in feedback where entry.date <= at && at.timeIntervalSince(entry.date) <= hurtWindow {
            for area in entry.hurtAreas {
                status.eased.formUnion(buckets(forHurtArea: area))
            }
        }
        status.eased.subtract(status.blocked)

        // The check-in: the latest one dated that day or the day before.
        let day = calendar.startOfDay(for: date)
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: day),
              let entry = soreness
                .filter({ let d = calendar.startOfDay(for: $0.date); return (d == day || d == dayBefore) && $0.date <= at })
                .max(by: { $0.date < $1.date })
        else { return status }

        if calendar.startOfDay(for: entry.date) == day {
            status.lowEnergy = entry.energy == "low"
            status.timeBudget = entry.timeBudget.map {
                max(TrainingConstraints.sessionMinutesHardRange.lowerBound,
                    min(TrainingConstraints.sessionMinutesHardRange.upperBound, $0))
            }
        }

        if entry.soreness == "high" || entry.pain {
            let areas = Set(entry.areas).intersection(MuscleBucket.sorenessPrimarySlugs)
            status.blocked.formUnion(areas)
            status.eased.subtract(areas)
        } else if entry.soreness == "mild" {
            let areas = Set(entry.areas).intersection(MuscleBucket.sorenessPrimarySlugs)
            status.eased.formUnion(areas.subtracting(status.blocked))
        } else if entry.soreness == "none" {
            // Feeling fine after the last session that loaded a group lifts
            // the part-recovered tier for that group. A block stays: the
            // model says the group is under half recovered, and soreness
            // shows up later than the fatigue it reports.
            for bucket in status.eased {
                let members = Set(MuscleBucket(rawValue: bucket)?.memberSlugs ?? [])
                let lastLoad = exposures
                    .filter { e in e.loads.keys.contains { members.contains($0) } && e.start <= at }
                    .map(\.start).max()
                if let lastLoad, entry.date > lastLoad {
                    status.eased.remove(bucket)
                }
            }
        }
        return status
    }
}

private extension Array where Element == MuscleBucket {
    var mapSet: Set<String> { Set(map(\.rawValue)) }
}
