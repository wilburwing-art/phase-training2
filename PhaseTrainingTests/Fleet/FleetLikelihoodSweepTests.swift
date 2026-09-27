// FleetLikelihoodSweepTests.swift — fit 3b's knobs on one fleet run and check
// them on another (PLAN-next-gen.md, "Tune from the report").
//
// Skips unless both run directories are set:
//   TEST_RUNNER_FLEET_SWEEP_FIT=<run dir>  TEST_RUNNER_FLEET_SWEEP_HOLDOUT=<run dir>
// TEST_RUNNER_FLEET_SWEEP_FREEZE=<knob,knob> keeps those knobs at their
// shipped values. Freeze any knob whose truth the simulator simply plants:
// every persona's travel attendance is one invented constant, so fitting
// travel_factor only copies that constant back into the app.
// Coordinate descent on Brier over the fit run, one knob at a time from the
// shipped defaults, then the defaults, the fitted values and the running
// attendance baseline on both runs. Writes likelihood-sweep.json into the fit
// run. Rows and the baseline match eval-rig's scorer: planned lift or sport
// days, happened = a session that day, baseline (attended + 1) / (planned + 2)
// over prior planned days.

import XCTest
@testable import PhaseTraining

final class FleetLikelihoodSweepTests: XCTestCase {

    private typealias Params = SessionLikelihoodEngine.Params

    private struct Row { let p: Double; let happened: Bool }

    private struct Run {
        let histories: [FleetHistory]
        let baseline: [Row]
    }

    private let calendar = FleetContract.calendar

    private func load(_ dir: String) throws -> Run {
        let folder = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("athletes", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no athletes under \(dir)")
        let histories = try files.map { file in
            try FleetConverter.convert(
                try FleetContract.decodeAthlete(try Data(contentsOf: file), source: file.lastPathComponent),
                calendar: calendar)
        }
        var baseline: [Row] = []
        for h in histories {
            var planned = 0.0, attended = 0.0
            for day in h.dates {
                guard let plan = h.plannedByDate[day], plan.kind == .lift || plan.kind == .sport else { continue }
                let happened = happened(h, day)
                baseline.append(Row(p: (attended + 1) / (planned + 2), happened: happened))
                planned += 1
                if happened { attended += 1 }
            }
        }
        return Run(histories: histories, baseline: baseline)
    }

    private func happened(_ h: FleetHistory, _ day: Date) -> Bool {
        h.sessions.contains { calendar.isDate($0.startTime, inSameDayAs: day) }
    }

    private func rows(_ run: Run, _ params: Params) -> [Row] {
        run.histories.flatMap { h in
            FleetReplay.likelihood(h, calendar: calendar, params: params).compactMap { r -> Row? in
                guard let day = try? FleetContract.day(r.date) else { return nil }
                return Row(p: r.p, happened: happened(h, day))
            }
        }
    }

    private func brier(_ rows: [Row]) -> Double {
        rows.reduce(0) { $0 + pow($1.p - ($1.happened ? 1 : 0), 2) } / Double(rows.count)
    }

    private func calibration(_ rows: [Row]) -> [[String: Double]] {
        (0 ..< 10).compactMap { b -> [String: Double]? in
            let lo = Double(b) / 10, hi = Double(b + 1) / 10
            let inBucket = rows.filter { $0.p >= lo && ($0.p < hi || (b == 9 && $0.p <= 1)) }
            guard !inBucket.isEmpty else { return nil }
            let n = Double(inBucket.count)
            return ["bucket": lo, "n": n,
                    "mean_p": inBucket.reduce(0) { $0 + $1.p } / n,
                    "observed": Double(inBucket.filter(\.happened).count) / n]
        }
    }

    private func dict(_ p: Params) -> [String: Double] {
        ["prior_happened": p.priorHappened, "prior_missed": p.priorMissed, "weekday_shrink": p.weekdayShrink,
         "travel_factor": p.travelFactor]
    }

    func testSweepLikelihood() throws {
        let env = ProcessInfo.processInfo.environment
        guard let fitDir = env["FLEET_SWEEP_FIT"], let holdDir = env["FLEET_SWEEP_HOLDOUT"],
              !fitDir.isEmpty, !holdDir.isEmpty else {
            throw XCTSkip("FLEET_SWEEP_FIT and FLEET_SWEEP_HOLDOUT are not set.")
        }
        let fit = try load(fitDir)
        let hold = try load(holdDir)

        let knobs: [(String, WritableKeyPath<Params, Double>, [Double])] = [
            ("prior_happened", \.priorHappened, [0.5, 1, 2, 3, 4, 6, 8, 12]),
            ("prior_missed", \.priorMissed, [0.25, 0.5, 1, 1.5, 2, 3, 4]),
            ("weekday_shrink", \.weekdayShrink, [1, 2, 4, 6, 8, 12, 16, 24, 32]),
            ("travel_factor", \.travelFactor, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]),
        ]
        let frozen = Set((env["FLEET_SWEEP_FREEZE"] ?? "").split(separator: ",").map(String.init))
        var best = Params.defaults
        var bestScore = brier(rows(fit, best))
        var trace: [[String: Any]] = []
        for pass in 1 ... 3 {
            let before = best
            for (name, key, values) in knobs where !frozen.contains(name) {
                for v in values where v != best[keyPath: key] {
                    var candidate = best
                    candidate[keyPath: key] = v
                    let score = brier(rows(fit, candidate))
                    if score < bestScore - 1e-9 {
                        best = candidate
                        bestScore = score
                        trace.append(["pass": pass, "knob": name, "value": v, "fit_brier": score])
                    }
                }
            }
            if best == before { break }
        }

        let result: [String: Any] = [
            "fit": fitDir, "holdout": holdDir, "frozen": frozen.sorted(),
            "defaults": dict(.defaults), "fitted": dict(best), "trace": trace,
            "fit_brier": ["defaults": brier(rows(fit, .defaults)), "fitted": bestScore,
                          "baseline": brier(fit.baseline)],
            "holdout_brier": ["defaults": brier(rows(hold, .defaults)), "fitted": brier(rows(hold, best)),
                              "baseline": brier(hold.baseline)],
            "holdout_calibration": ["defaults": calibration(rows(hold, .defaults)),
                                    "fitted": calibration(rows(hold, best)),
                                    "baseline": calibration(hold.baseline)],
            "rows": ["fit": fit.baseline.count, "holdout": hold.baseline.count],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: fitDir).appendingPathComponent("likelihood-sweep.json"))
        print("likelihood sweep: \(String(decoding: data, as: UTF8.self))")
    }
}
