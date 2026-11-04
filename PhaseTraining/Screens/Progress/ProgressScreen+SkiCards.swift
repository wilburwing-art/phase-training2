// ProgressScreen+SkiCards.swift — the two cards a skier sees on Progress.
//
// SKI SEASON: days on snow since Aug 1, from Apple Health and the sport
// log, with vertical when the workouts carry it (SkiSeason.swift).
// SKI READINESS: the latest pre-season test, each metric against the test
// before it, and the way to log one (SkiReadinessTest.swift).

import SwiftUI

extension ProgressScreen {

    var skiSeasonCard: some View {
        let summary = skiSeasonSummary
        let imperial = memoryStore.memory.usesImperial
        return Group {
            if let summary, memoryStore.memory.skis || summary.days > 0 {
                card(title: "SKI SEASON") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(summary.days) day\(summary.days == 1 ? "" : "s")")
                                .font(.scaled("JetBrainsMono-SemiBold", size: 18))
                                .foregroundStyle(Color.ink)
                                .accessibilityIdentifier("progress-ski-days")
                            Spacer()
                            if let last = summary.lastDay {
                                Text("last \(last.formatted(.dateTime.month(.abbreviated).day()))")
                                    .font(.monoXS)
                                    .foregroundStyle(Color.ink3)
                            }
                        }
                        if let meters = summary.verticalMeters {
                            let label = SkiSeason.verticalLabel(meters: meters, imperial: imperial)
                            Text(summary.daysWithVertical < summary.days
                                 ? "\(label) vertical from \(summary.daysWithVertical) of \(summary.days) days"
                                 : "\(label) vertical")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink2)
                                .accessibilityIdentifier("progress-ski-vertical")
                        }
                        Text("Since \(summary.seasonStart.formatted(.dateTime.month(.abbreviated).day())), from Apple Health and your sport log.")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                }
            }
        }
    }

    var skiReadinessCard: some View {
        let tests = memoryStore.memory.skiReadinessTests.sorted { $0.date < $1.date }
        let imperial = memoryStore.memory.usesImperial
        return Group {
            if memoryStore.memory.skis || !tests.isEmpty {
                card(title: "SKI READINESS") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let latest = tests.last {
                            let previous = tests.dropLast().last
                            ForEach(SkiReadinessTest.Metric.allCases, id: \.self) { metric in
                                if let value = latest.label(metric, imperial: imperial) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(metric.label)
                                            .font(.monoXS)
                                            .foregroundStyle(Color.ink2)
                                        Spacer()
                                        if let previous,
                                           let delta = latest.deltaLabel(metric, from: previous, imperial: imperial) {
                                            Text(delta)
                                                .font(.monoXS)
                                                .foregroundStyle(Color.ink3)
                                        }
                                        Text(value)
                                            .font(.scaled("JetBrainsMono-SemiBold", size: 15))
                                            .foregroundStyle(Color.ink)
                                            .accessibilityIdentifier("progress-ski-\(metric.rawValue)")
                                    }
                                }
                            }
                            Text(tests.count == 1
                                 ? "Tested \(latest.date.formatted(.dateTime.month(.abbreviated).day()))."
                                 : "Tested \(latest.date.formatted(.dateTime.month(.abbreviated).day())), changes since \(previous!.date.formatted(.dateTime.month(.abbreviated).day())).")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                        } else {
                            Text("Wall sit, single-leg balance, lateral hops and a broad jump. Test before the season, then every few weeks.")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                        }
                        Button {
                            presentingSkiTestSheet = true
                        } label: {
                            Text("Log a test")
                                .styled(.micro)
                                .foregroundStyle(Color.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progress-ski-log")
                    }
                }
                .sheet(isPresented: $presentingSkiTestSheet) {
                    SkiReadinessTestSheet().environmentObject(memoryStore)
                }
            }
        }
    }

    /// Reads this season's workouts from Health and folds in the sport log.
    /// A Health error (no access, no device data) counts the log alone.
    func loadSkiSeason() async {
        let now = Date()
        let since = SkiSeason.seasonStart(now: now)
        let workouts = (try? await HealthKitImporter().skiSeasonWorkouts(since: since, now: now)) ?? []
        skiSeasonSummary = SkiSeason.summarize(workouts: workouts, sportLogs: sportLogStore.entries, now: now)
    }
}
