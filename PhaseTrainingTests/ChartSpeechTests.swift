import Accessibility
import XCTest
@testable import PhaseTraining

final class ChartSpeechTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
    private let locale = Locale(identifier: "en_US")

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func test_amount() {
        XCTAssertEqual(ChartSpeech.amount(176.5, unit: "lb", decimals: 1), "176.5 lb")
        XCTAssertEqual(ChartSpeech.amount(18.5, unit: "%", decimals: 1), "18.5%")
        XCTAssertEqual(ChartSpeech.amount(12, unit: "", decimals: 0), "12")
    }

    func test_change() {
        XCTAssertEqual(ChartSpeech.change(from: 180, to: 176.5, unit: "lb", decimals: 1), "down 3.5 lb")
        XCTAssertEqual(ChartSpeech.change(from: 176.5, to: 180, unit: "lb", decimals: 1), "up 3.5 lb")
        XCTAssertEqual(ChartSpeech.change(from: 180.00, to: 180.04, unit: "lb", decimals: 1), "no change")
        let all = [
            ChartSpeech.change(from: 180, to: 176.5, unit: "lb", decimals: 1),
            ChartSpeech.change(from: 1, to: 2, unit: "", decimals: 0),
            ChartSpeech.change(from: 5, to: 5, unit: "kg", decimals: 1),
        ]
        for text in all {
            for banned in ["\u{2212}", "\u{2013}", "\u{2014}"] {
                XCTAssertFalse(text.contains(banned), text)
            }
        }
    }

    func test_seriesValue() {
        XCTAssertNil(ChartSpeech.seriesValue([], unit: "lb", decimals: 1, noun: "entry", nounPlural: "entries"))
        XCTAssertEqual(
            ChartSpeech.seriesValue([176.5], unit: "lb", decimals: 1, noun: "entry", nounPlural: "entries"),
            "1 entry, 176.5 lb")
        XCTAssertEqual(
            ChartSpeech.seriesValue([180, 181.2, 175.9, 176.5], unit: "lb", decimals: 1,
                                    noun: "entry", nounPlural: "entries"),
            "4 entries, 180.0 lb to 176.5 lb, down 3.5 lb, low 175.9 lb, high 181.2 lb")
    }

    func test_dateRange() {
        XCTAssertEqual(ChartSpeech.dateRange(from: date(2026, 11, 3), to: date(2026, 11, 14),
                                             calendar: calendar, locale: locale), "Nov 3 to Nov 14")
        XCTAssertEqual(ChartSpeech.dateRange(from: date(2025, 12, 20), to: date(2026, 1, 5),
                                             calendar: calendar, locale: locale),
                       "Dec 20, 2025 to Jan 5, 2026")
        XCTAssertEqual(ChartSpeech.dateRange(from: date(2026, 11, 3), to: date(2026, 11, 3),
                                             calendar: calendar, locale: locale), "Nov 3")
    }

    func test_weeklyValue() {
        let values: [Double] = [2, 3, 4, 0, 3, 4, 4, 3]
        let format: (Double) -> String = { "\(Int($0))" }
        XCTAssertEqual(ChartSpeech.weeklyValue(values, target: 4, format: format),
                       "This week 3, target 4. Last 8 weeks, oldest first: 2, 3, 4, 0, 3, 4, 4, 3")
        XCTAssertEqual(ChartSpeech.weeklyValue(values, target: nil, format: format),
                       "This week 3. Last 8 weeks, oldest first: 2, 3, 4, 0, 3, 4, 4, 3")
        XCTAssertNil(ChartSpeech.weeklyValue([], target: 4, format: format))
    }

    func test_wholeNumber() {
        XCTAssertEqual(ChartSpeech.wholeNumber(12_449.6, locale: locale), "12,450")
        XCTAssertEqual(ChartSpeech.wholeNumber(0, locale: locale), "0")
    }

    func test_share() {
        XCTAssertEqual(ChartSpeech.share(24, of: 100), "24 percent of the total")
        XCTAssertEqual(ChartSpeech.share(5, of: 0), "0 percent of the total")
    }

    func test_weekLabels() {
        XCTAssertEqual(ChartSpeech.weekLabels(count: 3), ["2 weeks ago", "1 week ago", "This week"])
    }

    func test_descriptor_datedLine() {
        let points = [
            SeriesChartDescriptor.Point(x: .date(date(2026, 11, 1)), y: 180, spoken: "180.0 lb"),
            SeriesChartDescriptor.Point(x: .date(date(2026, 11, 8)), y: 176.5, spoken: "176.5 lb"),
        ]
        let d = SeriesChartDescriptor(title: "Body weight over time", summary: "summary",
                                      xTitle: "Date", yTitle: "Weight in lb", points: points, isBar: false)
        let made = d.makeChartDescriptor()
        XCTAssertEqual(made.title, "Body weight over time")
        XCTAssertEqual(made.summary, "summary")
        XCTAssertEqual(made.series.count, 1)
        XCTAssertEqual(made.series[0].dataPoints.count, 2)
        XCTAssertTrue(made.series[0].isContinuous)
        XCTAssertEqual(made.series[0].name, "Weight in lb")
        XCTAssertEqual(made.yAxis?.valueDescriptionProvider(176.5), "176.5 lb")
    }

    func test_descriptor_barIsNotContinuous() {
        let points = [SeriesChartDescriptor.Point(x: .category("This week"), y: 3, spoken: "3")]
        let d = SeriesChartDescriptor(title: "t", summary: nil, xTitle: "Week", yTitle: "Sessions",
                                      points: points, isBar: true)
        XCTAssertFalse(d.makeChartDescriptor().series[0].isContinuous)
    }

    func test_descriptor_flatSeriesHasNonEmptyRange() {
        let points = [
            SeriesChartDescriptor.Point(x: .category("1 week ago"), y: 0, spoken: "0"),
            SeriesChartDescriptor.Point(x: .category("This week"), y: 0, spoken: "0"),
        ]
        let d = SeriesChartDescriptor(title: "t", summary: nil, xTitle: "Week", yTitle: "Sessions",
                                      points: points, isBar: false)
        let range = d.makeChartDescriptor().yAxis?.range
        XCTAssertNotNil(range)
        XCTAssertLessThan(range!.lowerBound, range!.upperBound)
    }

    func test_descriptor_categoryAxisKeepsLabelOrder() {
        let labels = ChartSpeech.weekLabels(count: 3)
        let points = zip(labels, [1.0, 2, 3]).map {
            SeriesChartDescriptor.Point(x: .category($0), y: $1, spoken: "\(Int($1))")
        }
        let d = SeriesChartDescriptor(title: "t", summary: nil, xTitle: "Week", yTitle: "Sessions",
                                      points: points, isBar: true)
        let axis = d.makeChartDescriptor().xAxis as? AXCategoricalDataAxisDescriptor
        XCTAssertEqual(axis?.categoryOrder, labels)
    }
}
