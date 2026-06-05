// ReadinessSignal.swift — Phase 2 in-season readiness scorer.
//
// PURE functions. No I/O, no DB calls, no Date() default arguments at
// the score-computation level — `now` is always injected by the caller
// so tests stay deterministic.
//
// The score is the SILENT axis from the
// `phase-training-personalization-three-axes` skill. It modulates
// volume / intensity / `recommendedLiftDaysPerWeek` floor inside the
// generator — it MUST NOT touch movement competency (that's the
// self-reported ExperienceLevel axis) and MUST NOT touch era / aesthetic
// (that's EraCohort + DemographicProfile.eraStyle).
//
// Inputs (28-day window, caller-aggregated):
//   - imported workouts (HK in Phase 2, CSV in Phase 3)
//   - native SavedSession start times
//   - native sport-log entries
//
// The signal is a coarse "have you been doing things lately" prior.
// 0.0 = fully detrained; 0.5 = neutral / no data; 1.0 = high training
// state. 0.5 is the no-data default so users who skip HK auth see no
// generator change — explicit anti-pattern: don't penalize the
// no-data case toward 0.0.
//
// Combining the three sub-components as a weighted geometric mean is
// deliberate: any near-zero component drags the whole score. A user
// who hit 4 sessions/wk last month but hasn't trained in 3 weeks
// shouldn't score 0.85 just because the historical density was high.

import Foundation

/// One readiness data point: when did the user train, and roughly
/// how much. Keeps the signal layer ignorant of strength-vs-cardio-vs-sport
/// — the density/recency/trend treat all sessions equally.
struct ReadinessEvent: Equatable {
    let startTime: Date
    /// Duration in seconds. Currently unused by the score itself
    /// (sessions/wk is the unit). Kept for Phase 3 in case we want to
    /// weight long ride days more than 20-min walks. Default 0.
    var duration: TimeInterval = 0
}

/// Per-axis breakdown of the readiness score. Surfaced in debug builds
/// (and persisted alongside the score for diagnostics) — the production
/// generator only reads `score`, but the breakdown is what we look at
/// when "why did this score change" questions come up.
struct ReadinessBreakdown: Equatable {
    /// 0..~1+. Ratio of (sessions/wk over last 4 wks) / (cohort norm).
    /// Clamped to [0, 1.5] before going into the geometric mean — high
    /// density shouldn't push the score above 1.0 by itself.
    let density: Double

    /// 0..1. 1.0 if the last session was ≤ 3 days ago; ramps to 0.1 at
    /// 14 days; floors at 0.05 for ≥ 28 days.
    let recency: Double

    /// 0.3..1.0. Last-2-weeks vs. prior-2-weeks ratio, capped at
    /// [0.5, 1.5] then remapped to [0.3, 1.0]. Distinguishes ramping
    /// up from detraining when density alone looks the same.
    let trend: Double
}

struct ReadinessSignal: Equatable {
    /// 0..1. 0.5 is the no-data default — generator scales by 1.0
    /// (no effect) at this score.
    let score: Double
    let breakdown: ReadinessBreakdown
}

extension ReadinessSignal {

    /// Score-computation entry point. Pass the 28-day window of events,
    /// the user's cohort (used only to pick the density norm), and the
    /// reference date. `events` need not be sorted; we sort internally.
    ///
    /// Returns the neutral signal (`score = 0.5`, all sub-components
    /// neutral) when no events are present — this is the unauthorized
    /// / opted-out / brand-new user case.
    static func compute(
        events: [ReadinessEvent],
        cohort: EraCohort?,
        now: Date
    ) -> ReadinessSignal {
        guard !events.isEmpty else { return .neutral }

        let sorted = events.sorted { $0.startTime < $1.startTime }
        let density = densityComponent(events: sorted, cohort: cohort, now: now)
        let recency = recencyComponent(events: sorted, now: now)
        let trend = trendComponent(events: sorted, now: now)

        let breakdown = ReadinessBreakdown(density: density, recency: recency, trend: trend)
        let combined = combine(density: density, recency: recency, trend: trend)
        return ReadinessSignal(score: combined, breakdown: breakdown)
    }

    /// Neutral signal — no data, no effect. The generator scales by
    /// `lerp(0.6, 1.0, 0.5) = 0.8` on the working-set multiplier at
    /// 0.5, which is mid-range; we wanted "no data → no effect" so the
    /// generator special-cases `breakdown == neutral` to skip scaling.
    /// (Documented again at the generator seam in 2-E.)
    static let neutral = ReadinessSignal(
        score: 0.5,
        breakdown: ReadinessBreakdown(density: 0.5, recency: 0.5, trend: 0.5)
    )

    // MARK: - Sub-components

    /// Sessions/wk over the last 4 wks, normalized to the cohort's norm.
    /// Cohort norms ladder from the older-school 3/wk magazine-bb cycle
    /// to the higher-frequency science-based norm. Default 3/wk for
    /// unknown cohort.
    static func densityComponent(events: [ReadinessEvent], cohort: EraCohort?, now: Date) -> Double {
        let cutoff = now.addingTimeInterval(-28 * 86_400)
        let inWindow = events.filter { $0.startTime >= cutoff }
        let sessionsPerWeek = Double(inWindow.count) / 4.0
        let norm = cohortNorm(cohort)
        let ratio = sessionsPerWeek / norm
        return min(max(ratio, 0.0), 1.5)
    }

    private static func cohortNorm(_ cohort: EraCohort?) -> Double {
        switch cohort {
        case .veteranStrength:      return 2.5   // 70+, lower training frequency
        case .magazineBodybuilding: return 3.0   // bro split, body-part 3-4x/wk
        case .tNationForum:         return 3.5   // 5x5 / WS-inspired upper-lower
        case .redditFitness:        return 4.0   // PPL/531 BBB norm
        case .scienceBased:         return 4.5   // higher-frequency hypertrophy
        case .currentMeta:          return 4.5   // tiktok-fitness, science-leaning
        case .none:                 return 3.0   // safe default
        }
    }

    /// 1.0 if last session ≤ 3 days ago. Ramps down linearly through
    /// 0.1 at 14 days. Floors at 0.05 for ≥ 28 days. Past 28 we cap at
    /// 0.05 instead of 0.0 so the geometric mean isn't fully zeroed by
    /// a single stale data point with otherwise OK density+trend.
    static func recencyComponent(events: [ReadinessEvent], now: Date) -> Double {
        guard let last = events.last?.startTime else { return 0.05 }
        let daysSince = now.timeIntervalSince(last) / 86_400
        if daysSince <= 3 { return 1.0 }
        if daysSince >= 28 { return 0.05 }
        if daysSince <= 14 {
            // 3 → 1.0, 14 → 0.1, linear.
            let t = (daysSince - 3) / (14 - 3)
            return 1.0 - t * (1.0 - 0.1)
        }
        // 14 → 0.1, 28 → 0.05, linear.
        let t = (daysSince - 14) / (28 - 14)
        return 0.1 - t * (0.1 - 0.05)
    }

    /// Last 14 days vs. previous 14 days. Ratio clamped to [0.5, 1.5],
    /// then remapped to [0.3, 1.0]. A ramping user (1→2→3/wk) scores
    /// higher than a flat 2/wk user even if density is comparable;
    /// a tapering user (3→2→1/wk) scores noticeably lower.
    static func trendComponent(events: [ReadinessEvent], now: Date) -> Double {
        let recent = events.filter {
            $0.startTime >= now.addingTimeInterval(-14 * 86_400)
        }.count
        let prior = events.filter {
            let t = $0.startTime
            return t >= now.addingTimeInterval(-28 * 86_400) &&
                   t <  now.addingTimeInterval(-14 * 86_400)
        }.count

        // Symmetry case: both zero → neutral (we'll let recency carry the signal).
        if recent == 0 && prior == 0 { return 0.65 }
        // Detraining from non-zero history → strong downward.
        if recent == 0 { return 0.3 }
        // Ramp from cold start → strong upward, but not perfect (data is sparse).
        if prior == 0 { return 0.9 }

        let ratio = Double(recent) / Double(prior)
        let clamped = min(max(ratio, 0.5), 1.5)
        // Remap [0.5, 1.5] → [0.3, 1.0]: t = (clamped - 0.5)
        return 0.3 + (clamped - 0.5) * (0.7 / 1.0)
    }

    /// Weighted geometric mean. Weights: density 0.4, recency 0.4, trend 0.2.
    /// Geometric mean (instead of arithmetic) so any near-zero sub-component
    /// drags the score — the failure mode we want to catch is "looked fine
    /// 3 weeks ago, hasn't trained since" where recency=0.05 should pull
    /// the score down hard.
    static func combine(density: Double, recency: Double, trend: Double) -> Double {
        // Geometric mean is exp(weighted sum of logs). Floor each component
        // at a small epsilon so a zero doesn't make the whole thing log(0).
        let eps = 0.01
        let d = max(density, eps)
        let r = max(recency, eps)
        let t = max(trend, eps)
        let logSum = 0.4 * log(d) + 0.4 * log(r) + 0.2 * log(t)
        return min(max(exp(logSum), 0.0), 1.0)
    }
}
