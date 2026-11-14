import Accessibility
import Foundation
import SwiftUI

/// Spoken strings for the charts. Pure: no SwiftUI state, no dashes, and
/// direction is always a word.
enum ChartSpeech {

    /// "176.5 lb", "18.5%", "12". `unit` is "" for a bare number, "%" joins
    /// with no space, anything else joins with one space.
    static func amount(_ value: Double, unit: String, decimals: Int) -> String {
        let number = String(format: "%.\(max(decimals, 0))f", value)
        if unit.isEmpty { return number }
        if unit == "%" { return number + unit }
        return "\(number) \(unit)"
    }

    /// "up 3.5 lb", "down 3.5 lb", "no change". "no change" when the
    /// difference rounds to zero at `decimals`.
    static func change(from first: Double, to last: Double, unit: String, decimals: Int) -> String {
        let diff = last - first
        let magnitude = amount(abs(diff), unit: unit, decimals: decimals)
        let scale = pow(10.0, Double(max(decimals, 0)))
        if (abs(diff) * scale).rounded() == 0 { return "no change" }
        return "\(diff > 0 ? "up" : "down") \(magnitude)"
    }

    /// Value string for a line series, oldest first. Nil for no points.
    static func seriesValue(_ values: [Double], unit: String, decimals: Int,
                            noun: String, nounPlural: String) -> String? {
        guard let first = values.first, let last = values.last else { return nil }
        if values.count == 1 {
            return "1 \(noun), \(amount(first, unit: unit, decimals: decimals))"
        }
        let low = values.min() ?? first
        let high = values.max() ?? last
        return [
            "\(values.count) \(nounPlural)",
            "\(amount(first, unit: unit, decimals: decimals)) to \(amount(last, unit: unit, decimals: decimals))",
            change(from: first, to: last, unit: unit, decimals: decimals),
            "low \(amount(low, unit: unit, decimals: decimals))",
            "high \(amount(high, unit: unit, decimals: decimals))",
        ].joined(separator: ", ")
    }

    /// "Nov 3 to Nov 14"; adds the year to both when the years differ; one
    /// date when first and last fall on the same day.
    static func dateRange(from first: Date, to last: Date,
                          calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdy")
        if calendar.isDate(first, inSameDayAs: last) { return formatter.string(from: first) }
        return "\(formatter.string(from: first)) to \(formatter.string(from: last))"
    }

    /// Value string for a weekly series, oldest first, last element is the
    /// current week. Nil for no values.
    static func weeklyValue(_ values: [Double], target: Int?,
                            format: (Double) -> String) -> String? {
        guard let current = values.last else { return nil }
        let targetClause = target.map { ", target \($0)" } ?? ""
        let list = values.map(format).joined(separator: ", ")
        return "This week \(format(current))\(targetClause). Last \(values.count) weeks, oldest first: \(list)"
    }

    /// "12,400". Rounded to a whole number, grouped for the locale.
    static func wholeNumber(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }

    /// "24 percent of the total" for a share bar. 0 when total is 0.
    static func share(_ part: Double, of total: Double) -> String {
        guard total > 0 else { return "0 percent of the total" }
        return "\(Int((part / total * 100).rounded())) percent of the total"
    }

    /// Week labels for a categorical axis, oldest first.
    static func weekLabels(count: Int) -> [String] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let ago = count - 1 - index
            switch ago {
            case 0: return "This week"
            case 1: return "1 week ago"
            default: return "\(ago) weeks ago"
            }
        }
    }
}

/// One-series audio graph. Used through `.accessibilityChartDescriptor`.
struct SeriesChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String?
    let xTitle: String
    let yTitle: String
    let points: [Point]
    let isBar: Bool

    enum X: Equatable { case date(Date), category(String) }
    struct Point: Equatable { let x: X; let y: Double; let spoken: String }

    func makeChartDescriptor() -> AXChartDescriptor {
        let built = build()
        return AXChartDescriptor(title: title, summary: summary,
                                 xAxis: built.xAxis, yAxis: built.yAxis,
                                 additionalAxes: [], series: [built.series])
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let built = build()
        descriptor.title = title
        descriptor.summary = summary
        descriptor.xAxis = built.xAxis
        descriptor.yAxis = built.yAxis
        descriptor.series = [built.series]
    }

    private func build() -> (xAxis: AXDataAxisDescriptor, yAxis: AXNumericDataAxisDescriptor, series: AXDataSeriesDescriptor) {
        let dates: [Date] = points.compactMap { if case .date(let d) = $0.x { return d } else { return nil } }
        let categories: [String] = points.compactMap { if case .category(let c) = $0.x { return c } else { return nil } }
        precondition(dates.isEmpty || categories.isEmpty, "SeriesChartDescriptor points mix date and category x values")

        let xAxis: AXDataAxisDescriptor
        var dataPoints: [AXDataPoint] = []
        if categories.isEmpty {
            let stamps = dates.map(\.timeIntervalSince1970)
            let lower = stamps.min() ?? 0
            let upper = stamps.max() ?? 1
            xAxis = AXNumericDataAxisDescriptor(
                title: xTitle,
                range: lower < upper ? lower...upper : (lower - 1)...(upper + 1),
                gridlinePositions: []
            ) { stamp in
                Date(timeIntervalSince1970: stamp).formatted(.dateTime.month(.abbreviated).day())
            }
            dataPoints = zip(stamps, points).map { stamp, point in
                AXDataPoint(x: stamp, y: point.y, additionalValues: [], label: point.spoken)
            }
        } else {
            xAxis = AXCategoricalDataAxisDescriptor(title: xTitle, categoryOrder: categories)
            dataPoints = zip(categories, points).map { category, point in
                AXDataPoint(x: category, y: point.y, additionalValues: [], label: point.spoken)
            }
        }

        let ys = points.map(\.y)
        let low = ys.min() ?? 0
        let high = ys.max() ?? 0
        let spokenByValue = points
        let yAxis = AXNumericDataAxisDescriptor(
            title: yTitle,
            range: low < high ? low...high : (low - 1)...(high + 1),
            gridlinePositions: []
        ) { value in
            spokenByValue.first { abs($0.y - value) < 0.000_001 }?.spoken
                ?? String(format: "%g", value)
        }
        let series = AXDataSeriesDescriptor(name: yTitle, isContinuous: !isBar, dataPoints: dataPoints)
        return (xAxis, yAxis, series)
    }
}
