// PhysiologyNight.swift — 1c capture slice of PLAN-next-gen.md (build 145).
//
// One record per night: HRV, resting heart rate and sleep, summarised from
// Apple Health samples. Capture and store only. No reader, model or coach
// input consumes these yet; the 1c reader lands after 6+ weeks of data.
//
// Pure: HealthKit stays in PhysiologyReader, and tests feed plain values.
//
// Which night a sample belongs to. A night is keyed by the start of the day
// the user WAKES on (`date`). The boundary between one night and the next is
// 18:00 local, so:
//   - sleep: a sleep sample belongs to the night of
//     startOfDay(end + 6 h). A 23:00 to 06:30 sleep and a 22:15 to 23:40
//     first sleep segment both count toward the next morning; a 14:00 nap
//     counts toward that same day.
//   - HRV: the mean of the SDNN samples taken from 18:00 the evening before
//     to 12:00 on the wake day. Apple Watch takes most of its background HRV
//     readings overnight, when activity does not confound them, and a mean
//     over the window is steadier than any single "morning value". Samples
//     taken from 12:00 to 18:00 are daytime readings and are dropped.
//   - resting heart rate: Apple computes it per calendar day, so the mean of
//     the samples that start on that calendar day (usually exactly one).
//
// Sleep minutes are the UNION of the asleep intervals (iOS 16+ core, deep,
// REM and unspecified, and the pre-iOS 16 "asleep", which shares
// unspecified's raw value). In bed and awake never count. The union matters:
// a Watch that records stages and a phone or third-party app that records
// "asleep" for the same hours would otherwise double the night.

import Foundation

/// HKCategoryValueSleepAnalysis, mirrored by raw value so this file does not
/// import HealthKit. The raw values are Apple's stable ABI:
/// inBed 0, asleepUnspecified 1 (the deprecated `.asleep` is also 1),
/// awake 2, asleepCore 3, asleepDeep 4, asleepREM 5.
enum PhysiologySleepStage: Equatable, Sendable {
    case inBed
    case asleepUnspecified
    case awake
    case asleepCore
    case asleepDeep
    case asleepREM

    init?(healthKitValue raw: Int) {
        switch raw {
        case 0: self = .inBed
        case 1: self = .asleepUnspecified
        case 2: self = .awake
        case 3: self = .asleepCore
        case 4: self = .asleepDeep
        case 5: self = .asleepREM
        default: return nil
        }
    }

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        case .inBed, .awake: return false
        }
    }
}

struct PhysiologySleepSample: Equatable, Sendable {
    var start: Date
    var end: Date
    var stage: PhysiologySleepStage
}

/// One quantity reading: HRV SDNN in milliseconds, or resting heart rate in
/// beats per minute. `date` is the sample's start.
struct PhysiologyReading: Equatable, Sendable {
    var date: Date
    var value: Double
}

/// One night's summary. Stored on device under `pt_physiology_nights`.
struct PhysiologyNight: Codable, Equatable, Sendable, Identifiable {
    /// Start of the day the user woke on.
    var date: Date
    /// Mean SDNN (ms) of the overnight window; nil when no sample fell in it.
    var hrvMs: Double?
    var hrvSamples: Int
    /// Mean resting heart rate (bpm) for the calendar day.
    var restingHR: Double?
    var restingHRSamples: Int
    /// Minutes asleep (union of asleep stages); nil when no asleep sample.
    var asleepMinutes: Double?
    /// Asleep-stage samples that fed `asleepMinutes`, before the union.
    var sleepSamples: Int

    var id: Date { date }
}

/// Counts for the DEBUG Signals sheet.
struct PhysiologyCaptureSummary: Equatable {
    var nights: Int
    var lastNight: Date?
    var daysWithHRV: Int
    var daysWithRestingHR: Int
    var daysWithSleep: Int

    static func make(_ nights: [PhysiologyNight]) -> PhysiologyCaptureSummary {
        PhysiologyCaptureSummary(
            nights: nights.count,
            lastNight: nights.map(\.date).max(),
            daysWithHRV: nights.filter { $0.hrvMs != nil }.count,
            daysWithRestingHR: nights.filter { $0.restingHR != nil }.count,
            daysWithSleep: nights.filter { $0.asleepMinutes != nil }.count)
    }
}

enum PhysiologySummariser {

    /// A night runs from this hour the evening before to the same hour on
    /// the wake day.
    static let eveningBoundaryHour = 18
    /// HRV samples after this hour on the wake day are daytime readings.
    static let hrvWindowEndHour = 12
    /// First capture reads this many nights back.
    static let firstRunDays = 30
    /// A gap since the last stored night is refilled up to this far back.
    static let maxBackfillDays = 90
    /// Stored nights older than this are pruned on write.
    static let retentionDays = 365

    // MARK: - Summarise

    static func summarise(sleep: [PhysiologySleepSample],
                          hrv: [PhysiologyReading],
                          restingHR: [PhysiologyReading],
                          calendar: Calendar = .current) -> [PhysiologyNight] {
        var nights: [Date: PhysiologyNight] = [:]
        func night(_ d: Date) -> PhysiologyNight {
            nights[d] ?? PhysiologyNight(date: d, hrvMs: nil, hrvSamples: 0, restingHR: nil,
                                         restingHRSamples: 0, asleepMinutes: nil, sleepSamples: 0)
        }

        // Sleep: group asleep samples by night, then sum the union.
        var sleepByNight: [Date: [PhysiologySleepSample]] = [:]
        for s in sleep where s.stage.isAsleep && s.end > s.start {
            sleepByNight[nightDate(forSleepEnd: s.end, calendar: calendar), default: []].append(s)
        }
        for (d, samples) in sleepByNight {
            var n = night(d)
            n.sleepSamples = samples.count
            n.asleepMinutes = unionSeconds(samples.map { ($0.start, $0.end) }) / 60
            nights[d] = n
        }

        // HRV: mean over the overnight window.
        var hrvByNight: [Date: [Double]] = [:]
        for r in hrv where r.value > 0 {
            if let d = hrvNightDate(for: r.date, calendar: calendar) {
                hrvByNight[d, default: []].append(r.value)
            }
        }
        for (d, values) in hrvByNight {
            var n = night(d)
            n.hrvSamples = values.count
            n.hrvMs = values.reduce(0, +) / Double(values.count)
            nights[d] = n
        }

        // Resting HR: mean per calendar day.
        var rhrByDay: [Date: [Double]] = [:]
        for r in restingHR where r.value > 0 {
            rhrByDay[calendar.startOfDay(for: r.date), default: []].append(r.value)
        }
        for (d, values) in rhrByDay {
            var n = night(d)
            n.restingHRSamples = values.count
            n.restingHR = values.reduce(0, +) / Double(values.count)
            nights[d] = n
        }

        return nights.values.sorted { $0.date < $1.date }
    }

    /// The night a sleep sample ending at `end` belongs to.
    static func nightDate(forSleepEnd end: Date, calendar: Calendar = .current) -> Date {
        let shift = 24 - eveningBoundaryHour
        let shifted = calendar.date(byAdding: .hour, value: shift, to: end) ?? end
        return calendar.startOfDay(for: shifted)
    }

    /// The night an HRV sample belongs to, or nil for a daytime reading
    /// (12:00 to 18:00).
    static func hrvNightDate(for date: Date, calendar: Calendar = .current) -> Date? {
        let d = nightDate(forSleepEnd: date, calendar: calendar)
        guard let windowEnd = calendar.date(byAdding: .hour, value: hrvWindowEndHour, to: d),
              date < windowEnd else { return nil }
        return d
    }

    /// Total seconds covered by the intervals, overlaps counted once.
    static func unionSeconds(_ intervals: [(Date, Date)]) -> Double {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var total: Double = 0
        var current: (Date, Date)?
        for iv in sorted {
            if let c = current, iv.0 <= c.1 {
                current = (c.0, max(c.1, iv.1))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = iv
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    // MARK: - Fetch window and merge

    /// What a refresh reads: nights from `firstNight` on, which needs Health
    /// samples from `queryStart` (18:00 the evening before). With nothing
    /// stored it reads `firstRunDays` back; otherwise it re-reads the last
    /// stored night (it may have been partial) and everything after, capped
    /// at `maxBackfillDays`.
    static func fetchWindow(lastStoredNight: Date?, now: Date,
                            calendar: Calendar = .current) -> (firstNight: Date, queryStart: Date) {
        let today = calendar.startOfDay(for: now)
        let floorDays = lastStoredNight == nil ? firstRunDays : maxBackfillDays
        let floor = calendar.date(byAdding: .day, value: -floorDays, to: today) ?? today
        var first = floor
        if let last = lastStoredNight {
            first = min(today, max(floor, calendar.startOfDay(for: last)))
        }
        let queryStart = calendar.date(byAdding: .hour, value: eveningBoundaryHour - 24, to: first) ?? first
        return (first, queryStart)
    }

    /// Fresh nights replace stored ones on the same date; a stored night the
    /// fresh read did not return is kept (a failed or empty read never erases
    /// history). Fresh nights before `firstNight` are dropped, since their
    /// window was only partly read. Prunes past `retentionDays`.
    static func merge(existing: [PhysiologyNight], fresh: [PhysiologyNight],
                      firstNight: Date, now: Date,
                      calendar: Calendar = .current) -> [PhysiologyNight] {
        var byDate: [Date: PhysiologyNight] = [:]
        for n in existing { byDate[n.date] = n }
        for n in fresh where n.date >= firstNight { byDate[n.date] = n }
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: today) ?? today
        return byDate.values.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }
}
