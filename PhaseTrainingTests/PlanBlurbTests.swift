//
//  PlanBlurbTests.swift
//  PhaseTrainingTests
//
//  The Today header's caption. These exist because the thing it replaced was
//  a generator trace that shipped to the most prominent copy on the screen
//  and read as a log line, so the bar is that every branch produces a
//  sentence a person would write.
//

import XCTest
@testable import PhaseTraining

final class PlanBlurbTests: XCTestCase {

    private func s(_ kind: DayKind, _ phase: SeasonPhase,
                   sport: String? = "Skiing / Snowboarding", week: Int? = 3) -> String? {
        PlanBlurb.sentence(kind: kind, phase: phase, sportLabel: sport, weekInPhase: week)
    }

    // MARK: - Countdown (Today subtitle)

    func testCountdown_eventPrepReadsPeak() {
        XCTAssertEqual(PlanBlurb.countdown(phase: .eventPrep, daysToTarget: 12), "peak in 12d")
        XCTAssertEqual(PlanBlurb.countdown(phase: .eventPrep, daysToTarget: 0), "peak today")
    }

    func testCountdown_offAndPreSeasonReadSeasonStart() {
        for phase in [SeasonPhase.offSeason, .preSeason] {
            XCTAssertEqual(PlanBlurb.countdown(phase: phase, daysToTarget: 34), "season in 34d", "\(phase)")
            XCTAssertEqual(PlanBlurb.countdown(phase: phase, daysToTarget: 0), "season starts today", "\(phase)")
        }
    }

    func testCountdown_nilWhenPhaseHasNoTargetOrDatePassed() {
        for phase in [SeasonPhase.inSeason, .maintenance] {
            XCTAssertNil(PlanBlurb.countdown(phase: phase, daysToTarget: 10), "\(phase) has nothing to count to")
            XCTAssertFalse(phase.countsDownToTarget)
        }
        XCTAssertNil(PlanBlurb.countdown(phase: .preSeason, daysToTarget: nil))
        XCTAssertNil(PlanBlurb.countdown(phase: .eventPrep, daysToTarget: -1))
    }

    // MARK: - Sport short name (Today eyebrow)

    func testSportShortName_cutsAtSlashAndParenOnly() {
        XCTAssertEqual(Sport(slug: "snow-sports", name: "Skiing / Snowboarding").shortName, "Skiing")
        XCTAssertEqual(Sport(slug: "x", name: "Hiking / Trekking").shortName, "Hiking")
        XCTAssertEqual(Sport(slug: "x", name: "Rowing (indoor)").shortName, "Rowing")
        XCTAssertEqual(Sport(slug: "sup", name: "Stand-Up Paddleboarding").shortName, "Stand-Up Paddleboarding")
        XCTAssertEqual(Sport(slug: "bjj", name: "Brazilian Jiu-Jitsu").shortName, "Brazilian Jiu-Jitsu")
    }

    // MARK: - Lift sentence

    func testEveryPhaseProducesALiftSentence() {
        for phase in SeasonPhase.allCases {
            let out = s(.lift, phase)
            XCTAssertNotNil(out, "\(phase) produced no lift sentence")
            XCTAssertFalse(out!.isEmpty)
        }
    }

    /// The failure this replaced: machine punctuation reaching the header.
    func testNoSentenceLooksLikeAGeneratorTrace() {
        var all: [String] = []
        for phase in SeasonPhase.allCases {
            for kind in DayKind.allCases {
                if let out = s(kind, phase) { all.append(out) }
            }
        }
        XCTAssertFalse(all.isEmpty)
        for out in all {
            XCTAssertFalse(out.contains(" · "), "trace separator in: \(out)")
            XCTAssertFalse(out.contains("demands:"), "demand mix in: \(out)")
            // A machine list joins with a bare slash ("power/maxStrength");
            // a real sport name spaces it ("Skiing / Snowboarding"). The
            // spacing is the discriminator, so the first version of this
            // rule failed on correct output.
            XCTAssertNil(out.range(of: "[^ ]/[^ ]", options: .regularExpression),
                         "slash-joined machine list in: \(out)")
            XCTAssertFalse(out.contains("_"), "raw enum value in: \(out)")
            XCTAssertTrue(out.hasSuffix("."), "not a sentence: \(out)")
        }
    }

    func testSportNameIsWovenInWhenKnown() {
        let out = s(.lift, .preSeason, sport: "Climbing")
        XCTAssertEqual(out, "Pre-season for climbing. Sharpening what the season will ask for. Week 3.")
    }

    /// A sportless athlete must still read as a sentence, not a gap.
    func testNoSportStillReadsCleanly() {
        let out = s(.lift, .offSeason, sport: nil)
        XCTAssertEqual(out, "Off-season. Building the engine while there's time. Week 3.")
    }

    /// Week is optional; a brand-new athlete has no phase start yet.
    func testNoWeekOmitsTheCounter() {
        let out = s(.lift, .maintenance, sport: nil, week: nil)
        XCTAssertEqual(out, "Staying strong, year-round.")
    }

    func testRestIsShort() {
        XCTAssertEqual(s(.rest, .inSeason), "Rest. Nothing scheduled.")
    }

    /// A sport day with no sport attached says nothing rather than guessing.
    func testSportDayWithoutASportReturnsNil() {
        XCTAssertNil(s(.sport, .inSeason, sport: nil))
    }
}
