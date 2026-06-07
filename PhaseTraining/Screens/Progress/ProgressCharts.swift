// ProgressCharts.swift — spark views for the Progress tab.
//
// Split out of ProgressScreen.swift (architecture item 9, pure move).
// LineSpark / BodyWeightSpark are hand-drawn; ExerciseSparkline uses
// Swift Charts. Access relaxed from file-private to internal so the
// ProgressScreen card extensions in this folder can use them.

import SwiftUI
import Charts

// MARK: - LineSpark (hand-drawn — used by Volume card)

struct LineSpark: View {
    let points: [Double]
    let maxValue: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(points.count, 1)
            let stepX = count > 1 ? w / CGFloat(count - 1) : w / 2

            ZStack {
                // Baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(Color.line, lineWidth: 0.5)

                // Line
                Path { p in
                    for (i, value) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = h - (h * CGFloat(value / maxValue))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                // Dots
                ForEach(points.indices, id: \.self) { i in
                    let x = CGFloat(i) * stepX
                    let y = h - (h * CGFloat(points[i] / maxValue))
                    Circle()
                        .fill(Color.accent)
                        .frame(width: i == points.count - 1 ? 6 : 3, height: i == points.count - 1 ? 6 : 3)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - BodyWeightSpark (hand-drawn — used by body-weight card)
//
// Unlike LineSpark, this one normalizes against (min, max) instead of 0 so
// small absolute weight changes stay visible — a 2-lb swing on a 175-lb
// baseline shouldn't render as a flatline.

struct BodyWeightSpark: View {
    let points: [Double]
    let minValue: Double
    let maxValue: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(points.count, 1)
            let stepX = count > 1 ? w / CGFloat(count - 1) : w / 2
            let span = maxValue - minValue
            // Flat series (all weights equal) → render centered, not pinned to
            // an edge. `frac(_:)` returns 0.5 when there's no spread.
            let frac: (Double) -> CGFloat = { value in
                span < 0.0001 ? 0.5 : CGFloat((value - minValue) / span)
            }

            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(Color.line, lineWidth: 0.5)

                Path { p in
                    for (i, value) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = h - (h * frac(value))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                if let last = points.last {
                    let x = CGFloat(points.count - 1) * stepX
                    let y = h - (h * frac(last))
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - ExerciseSparkline (Swift Charts — used by per-exercise card)

struct ExerciseSparkline: View {
    let points: [ProgressAggregates.SparkPoint]

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("date", p.date), y: .value("weight", p.weight))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            if let last = points.last {
                PointMark(x: .value("date", last.date), y: .value("weight", last.weight))
                    .foregroundStyle(Color.accent)
                    .symbolSize(24)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.background(Color.clear) }
    }
}
