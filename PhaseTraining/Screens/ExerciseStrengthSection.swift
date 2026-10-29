// ExerciseStrengthSection.swift — "Your strength" on the exercise detail sheet.
//
// Shows what `HistoryProfile` knows about one exercise: the estimated max and
// the workouts it rests on, the working weight for the exercise's default
// reps (the same number the Log pill suggests), trend, best, usual jump, and
// how many sets were left out as likely typos. Every string comes from
// `ExerciseStrengthSummary`, which is pure so the wording is unit-tested; the
// view only lays it out.

import Charts
import SwiftUI

struct ExerciseStrengthSummary: Equatable {

    struct ChartPoint: Equatable, Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    let estimate: String
    let basis: String
    let layoff: String?
    let forReps: String?
    let trend: String
    let best: String
    let usualJump: String?
    let excluded: String?
    /// In the display unit; empty below 3 workouts.
    let chart: [ChartPoint]

    static let layoffWeeks = 4.0

    /// Nil when there is no loaded estimate (new users, bodyweight-only).
    init?(profile p: HistoryProfile.ExerciseProfile, defaultReps: String?,
          usesImperial: Bool, now: Date) {
        guard let est = p.estimate, est.weight > 0 else { return nil }
        let unit = usesImperial ? "lb" : "kg"
        func display(_ lb: Double) -> String {
            if usesImperial { return "\(Int(lb.rounded())) \(unit)" }
            let kg = (BodyMetrics.lbToKg(lb) * 2).rounded() / 2
            return (kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg))" : "\(kg)") + " \(unit)"
        }

        estimate = display(StrengthStandards.epley1RM(weight: est.weight, reps: est.reps))

        let n = min(p.workouts, ProvenStrength.workoutsConsidered)
        let over = n == 1 ? "your last workout" : "your last \(n) workouts"
        let l = p.latestBest
        basis = "Based on \(over) · latest \(display(l.weightLb)) × \(l.reps) on \(Self.day(l.date, now: now))"

        let weeksOff = now.timeIntervalSince(p.lastTrained) / (7 * 86_400)
        layoff = weeksOff > Self.layoffWeeks
            ? "Lowered for \(Int(weeksOff.rounded())) weeks off. It builds back as you log."
            : nil

        if let reps = defaultReps.flatMap(WorkoutGenerator.repBandMidpoint), reps > 0,
           let load = ProgressionSuggestion.fromHistory(est, targetReps: reps, unit: usesImperial ? "lbs" : "kg") {
            forReps = "For \(reps) reps: about \(load.suggestedWeightString) \(unit)"
        } else {
            forReps = nil
        }

        switch p.trend {
        case .rising(let pct): trend = String(format: "Rising %.1f%% a month", pct)
        case .falling(let pct): trend = String(format: "Falling %.1f%% a month", abs(pct))
        case .flat: trend = p.plateau ? "Flat over your recent workouts (plateau)" : "Holding steady"
        case .unknown: trend = "Not enough recent workouts to call a trend"
        }

        best = "Best \(display(p.bestE1RM)) est. max · \(Self.month.string(from: p.bestDate))"

        usualJump = p.typicalStepLb.map { step in
            if usesImperial {
                return step.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(step)) lb" : "\(step) lb"
            }
            return display(step)
        }

        switch p.excludedSets {
        case 0: excluded = nil
        case 1: excluded = "1 set left out as a likely typo"
        default: excluded = "\(p.excludedSets) sets left out as likely typos"
        }

        chart = p.recentBests.count >= 3
            ? p.recentBests.map { ChartPoint(date: $0.date, value: usesImperial ? $0.e1rm : BodyMetrics.lbToKg($0.e1rm)) }
            : []
    }

    private static let month: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    private static func day(_ date: Date, now: Date) -> String {
        let f = DateFormatter()
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: now)
        f.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return f.string(from: date)
    }
}

struct ExerciseStrengthView: View {
    let summary: ExerciseStrengthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.estimate)
                    .styled(.displayS)
                    .foregroundStyle(Color.ink)
                    .accessibilityIdentifier("strength-estimate")
                Text("est. max")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Text(summary.basis)
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
            if let layoff = summary.layoff {
                Text(layoff)
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
            }
            if !summary.chart.isEmpty {
                Chart {
                    ForEach(summary.chart) { p in
                        LineMark(x: .value("date", p.date), y: .value("est. max", p.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    }
                    if let last = summary.chart.last {
                        PointMark(x: .value("date", last.date), y: .value("est. max", last.value))
                            .foregroundStyle(Color.accent)
                            .symbolSize(24)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 56)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let forReps = summary.forReps { row(forReps) }
                row(summary.trend)
                row(summary.best)
                if let jump = summary.usualJump { row("Usual jump: \(jump)") }
                if let excluded = summary.excluded { row(excluded) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exercise-strength")
    }

    private func row(_ text: String) -> some View {
        Text(text)
            .font(.monoS)
            .foregroundStyle(Color.ink)
    }
}
