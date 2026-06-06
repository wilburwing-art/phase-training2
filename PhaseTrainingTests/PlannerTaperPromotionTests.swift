// PlannerTaperPromotionTests.swift — characterization tests for the two
// Build-78 rule passes that made per-sport seasons + peak dates real:
//
//   - Planner.applyPeakDateTaper: .eventPrep + peakDate inside the week →
//     peak slot becomes a protected .event, day -1 rests (taper), day -2
//     rests (easing). Protected slots are never rewritten.
//   - Planner.applySecondarySportPromotion: each non-primary sport flagged
//     .inSeason / .eventPrep claims one unprotected rest slot, capped at 2
//     promotions per week, skipping sports the user already booked an event
//     for, in deterministic slug order.
//
// Both functions are pure slot-array transforms, so we exercise them
// directly with hand-built [DayPlan?] fixtures — no Planner.generate, no
// coach.db, no wall clock. Dates anchor to a fixed Monday.

import XCTest
@testable import PhaseTraining

final class PlannerTaperPromotionTests: XCTestCase {

    // MARK: - Fixtures

    /// Fixed-Monday anchor so dates are deterministic across CI clocks.
    private func mondayAnchor() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11   // Monday, May 11, 2026
        return Calendar.current.date(from: c)!
    }

    /// Mon..Sun, start-of-day, matching the planner's week window.
    private func weekDates() -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: mondayAnchor())
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    private func sport(_ slug: String) -> Sport {
        Sport.catalog.first { $0.slug == slug }!
    }

    private func fixtureTitle(_ kind: DayKind) -> String {
        switch kind {
        case .lift:  return "Lift"
        case .sport: return "Sport"
        case .rest:  return "Rest"
        case .event: return "Event"
        }
    }

    /// Build a full week of slots from a kinds template. Every slot carries
    /// generatedReason "fixture" so tests can detect rewrites by reason.
    private func makeSlots(
        _ kinds: [DayKind],
        dates: [Date],
        protectedIdx: Set<Int> = []
    ) -> [DayPlan?] {
        kinds.enumerated().map { i, kind -> DayPlan? in
            DayPlan(
                date: dates[i],
                kind: kind,
                title: fixtureTitle(kind),
                protected: protectedIdx.contains(i),
                generatedReason: "fixture"
            )
        }
    }

    /// Memory whose seasonForPlanner resolves to .eventPrep (no primary
    /// sport → defaultSeason wins) with the given peak date.
    private func eventPrepMemory(peak: Date?) -> TrainingMemory {
        var m = TrainingMemory()
        m.defaultSeason = .eventPrep
        m.peakDate = peak
        return m
    }

    /// Memory with a primary sport in .maintenance plus the given secondary
    /// sport seasons — the promotion pass's candidate pool.
    private func promotionMemory(
        primary: String = "climbing",
        secondaries: [String: SeasonPhase]
    ) -> TrainingMemory {
        var m = TrainingMemory()
        let p = sport(primary)
        m.primarySport = p
        m.sports = [p] + secondaries.keys.map { sport($0) }
        var seasons: [Sport: SeasonPhase] = [p: .maintenance]
        for (slug, phase) in secondaries { seasons[sport(slug)] = phase }
        m.seasonsBySport = seasons
        return m
    }

    // MARK: - applyPeakDateTaper: happy path

    func test_peakDateTaper_peakSlotBecomesProtectedEvent() {
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates)
        let memory = eventPrepMemory(peak: dates[4])   // Friday peak

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots[4]?.kind, .event)
        XCTAssertEqual(slots[4]?.title, "Peak day")
        XCTAssertTrue(slots[4]?.protected ?? false,
                      "Peak slot must be protected so later passes can't rewrite it")
        XCTAssertEqual(slots[4]?.generatedReason, "Your event-prep peak date")
        XCTAssertEqual(slots[4]?.date, dates[4])
        // Days outside the taper window keep their lifts.
        XCTAssertEqual(slots[0]?.kind, .lift)
        XCTAssertEqual(slots[1]?.kind, .lift)
        XCTAssertEqual(slots[5]?.kind, .lift)
        XCTAssertEqual(slots[6]?.kind, .lift)
    }

    func test_peakDateTaper_dayMinusOneDemotedToRestWithTaperReason() {
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates)
        let memory = eventPrepMemory(peak: dates[4])

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots[3]?.kind, .rest, "Day -1 lift should taper to rest")
        XCTAssertEqual(slots[3]?.title, "Rest")
        XCTAssertEqual(slots[3]?.generatedReason, "Tapering before peak day")
    }

    func test_peakDateTaper_dayMinusTwoDemotedToRestWithEasingReason() {
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates)
        let memory = eventPrepMemory(peak: dates[4])

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots[2]?.kind, .rest, "Day -2 lift should ease into rest")
        XCTAssertEqual(slots[2]?.title, "Rest")
        XCTAssertEqual(slots[2]?.generatedReason, "Easing into peak day")
    }

    func test_peakDateTaper_perSportEventPrepSeasonApplies() {
        // seasonForPlanner reads seasonsBySport[primarySport] before
        // defaultSeason — per-sport .eventPrep must trigger the taper even
        // when the default season is .maintenance.
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates)
        let climbing = sport("climbing")
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.seasonsBySport = [climbing: .eventPrep]
        memory.defaultSeason = .maintenance
        memory.peakDate = dates[4]

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots[4]?.kind, .event)
        XCTAssertEqual(slots[3]?.kind, .rest)
        XCTAssertEqual(slots[2]?.kind, .rest)
    }

    // MARK: - applyPeakDateTaper: protected slots

    func test_peakDateTaper_protectedPeakSlotSkipsEntireRule() {
        // A protected slot on the peak date means the user already placed an
        // event there — applyPreEventTaper owns the taper, so this pass must
        // not touch ANY slot (no double-taper of day -1 / day -2 either).
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates,
                              protectedIdx: [4])
        let before = slots
        let memory = eventPrepMemory(peak: dates[4])

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots, before,
                       "Protected peak slot must short-circuit the whole rule")
    }

    func test_peakDateTaper_protectedDayMinusOneSurvivesDemotion() {
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates,
                              protectedIdx: [3])
        let memory = eventPrepMemory(peak: dates[4])

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots[4]?.kind, .event, "Peak conversion still applies")
        XCTAssertEqual(slots[3]?.kind, .lift,
                       "Protected day -1 slot must not be demoted")
        XCTAssertTrue(slots[3]?.protected ?? false)
        XCTAssertEqual(slots[2]?.kind, .rest, "Day -2 still eases to rest")
    }

    // MARK: - applyPeakDateTaper: no-op guards

    func test_peakDateTaper_peakDateOutsideWeekDoesNotMutate() {
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates)
        let before = slots
        let nextMonth = Calendar.current.date(byAdding: .day, value: 30, to: mondayAnchor())!
        let memory = eventPrepMemory(peak: nextMonth)

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots, before,
                       "Peak date outside the week window must leave slots untouched")
    }

    func test_peakDateTaper_nonEventPrepSeasonIsNoOp() {
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates)
        let before = slots
        var memory = TrainingMemory()
        memory.defaultSeason = .maintenance
        memory.peakDate = dates[4]      // peak set, but season gate fails

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots, before, "Peak taper only applies under .eventPrep")
    }

    func test_peakDateTaper_nilPeakDateIsNoOp() {
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates)
        let before = slots
        let memory = eventPrepMemory(peak: nil)

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots, before, ".eventPrep without a peak date must not taper")
    }

    // MARK: - applyPeakDateTaper: edges

    func test_peakDateTaper_peakOnMondayDoesNotCrashOnOutOfRangeNeighbors() {
        // Peak at index 0 — day -1 and day -2 fall outside the array. The
        // demote helper guards indices, so the peak conversion still lands
        // and nothing else moves.
        let dates = weekDates()
        var slots = makeSlots(Array(repeating: .lift, count: 7), dates: dates)
        let memory = eventPrepMemory(peak: dates[0])

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots[0]?.kind, .event)
        XCTAssertEqual(slots[0]?.title, "Peak day")
        for i in 1..<7 {
            XCTAssertEqual(slots[i]?.kind, .lift, "slots[\(i)] should be untouched")
        }
    }

    func test_peakDateTaper_restNeighborsKeepOriginalReason() {
        // Demotion is a no-op when the slot is already rest (severity equal,
        // not greater) — the fixture's reason string must survive instead of
        // being rewritten to the taper reason.
        let dates = weekDates()
        var slots = makeSlots([.lift, .lift, .rest, .rest, .lift, .lift, .lift],
                              dates: dates)
        let memory = eventPrepMemory(peak: dates[4])

        Planner.applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: .current)

        XCTAssertEqual(slots[3]?.kind, .rest)
        XCTAssertEqual(slots[3]?.generatedReason, "fixture",
                       "Already-rest day -1 must not be rewritten")
        XCTAssertEqual(slots[2]?.kind, .rest)
        XCTAssertEqual(slots[2]?.generatedReason, "fixture",
                       "Already-rest day -2 must not be rewritten")
    }

    // MARK: - applySecondarySportPromotion: happy path

    func test_promotion_inSeasonSecondaryPromotesFirstRestSlot() {
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .rest, .lift, .rest],
                              dates: dates)
        let memory = promotionMemory(secondaries: ["alpine-skiing": .inSeason])

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots[1]?.kind, .sport, "First rest slot should be promoted")
        XCTAssertEqual(slots[1]?.sport?.slug, "alpine-skiing")
        XCTAssertEqual(slots[1]?.title, "Alpine Skiing session")
        XCTAssertEqual(slots[1]?.date, dates[1], "Promoted slot keeps its date")
        XCTAssertFalse(slots[1]?.protected ?? true,
                       "Promoted placeholder stays unprotected so taper rules can demote it")
        XCTAssertEqual(slots[1]?.generatedReason,
                       "Alpine Skiing is in-season — added a placeholder day")
        // Remaining rests untouched.
        XCTAssertEqual(slots[3]?.kind, .rest)
        XCTAssertEqual(slots[4]?.kind, .rest)
        XCTAssertEqual(slots[6]?.kind, .rest)
    }

    func test_promotion_eventPrepSecondaryPromotes() {
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .rest, .lift, .rest],
                              dates: dates)
        let memory = promotionMemory(secondaries: ["alpine-skiing": .eventPrep])

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots[1]?.kind, .sport,
                       ".eventPrep secondaries promote exactly like .inSeason")
        XCTAssertEqual(slots[1]?.sport?.slug, "alpine-skiing")
    }

    // MARK: - applySecondarySportPromotion: cap + ordering

    func test_promotion_cappedAtTwoPerWeek() {
        let dates = weekDates()
        var slots = makeSlots([.rest, .rest, .rest, .lift, .lift, .lift, .lift],
                              dates: dates)
        let memory = promotionMemory(secondaries: [
            "bjj":     .inSeason,
            "cycling": .inSeason,
            "tennis":  .inSeason,
        ])

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        let promoted = slots.compactMap { $0 }.filter { $0.kind == .sport }
        XCTAssertEqual(promoted.count, 2, "Promotion must cap at 2/week")
        // Slug-sorted candidates: bjj < cycling < tennis — tennis loses.
        XCTAssertEqual(slots[0]?.sport?.slug, "bjj")
        XCTAssertEqual(slots[1]?.sport?.slug, "cycling")
        XCTAssertEqual(slots[2]?.kind, .rest, "Third rest slot survives the cap")
        XCTAssertFalse(promoted.contains { $0.sport?.slug == "tennis" })
    }

    func test_promotion_deterministicOrderBySportSlug() {
        // seasonsBySport is a dictionary — ordering must come from sorting
        // by slug, not dictionary iteration. "bjj" < "tennis" so bjj claims
        // the earlier rest slot regardless of insertion order.
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .lift, .lift, .lift],
                              dates: dates)
        let memory = promotionMemory(secondaries: [
            "tennis": .inSeason,
            "bjj":    .inSeason,
        ])

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots[1]?.sport?.slug, "bjj",
                       "Lexicographically-first slug claims the first rest slot")
        XCTAssertEqual(slots[3]?.sport?.slug, "tennis")
    }

    // MARK: - applySecondarySportPromotion: already-booked events

    func test_promotion_alreadyBookedSportNotDoubleBooked() {
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .rest, .lift, .rest],
                              dates: dates)
        let before = slots
        let memory = promotionMemory(secondaries: ["alpine-skiing": .inSeason])
        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: dates[5], title: "Ski day",
                      kind: .sportSession, sport: sport("alpine-skiing"))
        ]

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: overrides, calendar: .current)

        XCTAssertEqual(slots, before,
                       "Booked event for the secondary sport must suppress its promotion")
    }

    func test_promotion_bookedSportSkippedButOtherCandidatePromotes() {
        // Skiing is booked; cycling is also in-season — the booked skip is
        // per-sport, so cycling still claims the first rest slot.
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .lift, .lift, .lift],
                              dates: dates)
        let memory = promotionMemory(secondaries: [
            "alpine-skiing": .inSeason,
            "cycling":       .inSeason,
        ])
        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: dates[5], title: "Ski day",
                      kind: .sportSession, sport: sport("alpine-skiing"))
        ]

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: overrides, calendar: .current)

        XCTAssertEqual(slots[1]?.sport?.slug, "cycling")
        XCTAssertEqual(slots[3]?.kind, .rest,
                       "Only cycling promotes — skiing's slot stays rest")
        XCTAssertFalse(slots.compactMap { $0 }.contains { $0.sport?.slug == "alpine-skiing" })
    }

    // MARK: - applySecondarySportPromotion: no-op guards

    func test_promotion_noRestSlotsLeavesWeekUnchanged() {
        let dates = weekDates()
        var slots = makeSlots([.lift, .sport, .lift, .sport, .lift, .sport, .lift],
                              dates: dates)
        let before = slots
        let memory = promotionMemory(secondaries: ["alpine-skiing": .inSeason])

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots, before,
                       "No rest slots → nothing to promote, nothing rewritten")
    }

    func test_promotion_protectedRestSlotsNotPromoted() {
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .rest, .lift, .rest],
                              dates: dates, protectedIdx: [1, 3, 4, 6])
        let before = slots
        let memory = promotionMemory(secondaries: ["alpine-skiing": .inSeason])

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots, before,
                       "Protected rest slots express user intent — never promoted")
    }

    func test_promotion_primarySportNeverPromotes() {
        // The primary's season drives the WeeklyShape, not this pass —
        // primary .inSeason must be filtered out of the candidate pool.
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .rest, .lift, .rest],
                              dates: dates)
        let before = slots
        let climbing = sport("climbing")
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.sports = [climbing]
        memory.seasonsBySport = [climbing: .inSeason]

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots, before,
                       "Primary sport must be excluded from secondary promotion")
    }

    func test_promotion_nonActiveSeasonsDoNotPromote() {
        // .offSeason / .preSeason / .maintenance secondaries are all outside
        // the .inSeason/.eventPrep gate.
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .rest, .lift, .rest],
                              dates: dates)
        let before = slots
        let memory = promotionMemory(secondaries: [
            "alpine-skiing": .offSeason,
            "cycling":       .preSeason,
            "tennis":        .maintenance,
        ])

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots, before,
                       "Only .inSeason / .eventPrep secondaries earn a placeholder day")
    }

    // MARK: - applySecondarySportPromotion: edges

    func test_promotion_moreCandidatesThanRestSlotsPromotesOnlyAvailable() {
        // Two eligible secondaries but a single rest slot — the first (by
        // slug) takes it; the second finds no slot and quietly skips.
        let dates = weekDates()
        var slots = makeSlots([.lift, .lift, .rest, .lift, .lift, .lift, .lift],
                              dates: dates)
        let memory = promotionMemory(secondaries: [
            "bjj":     .inSeason,
            "cycling": .inSeason,
        ])

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots[2]?.kind, .sport)
        XCTAssertEqual(slots[2]?.sport?.slug, "bjj")
        XCTAssertEqual(slots.compactMap { $0 }.filter { $0.kind == .sport }.count, 1,
                       "Only one rest slot existed — only one promotion lands")
    }

    func test_promotion_emptySeasonsBySportIsNoOp() {
        let dates = weekDates()
        var slots = makeSlots([.lift, .rest, .lift, .rest, .rest, .lift, .rest],
                              dates: dates)
        let before = slots
        var memory = TrainingMemory()
        memory.primarySport = sport("climbing")
        memory.seasonsBySport = [:]

        Planner.applySecondarySportPromotion(&slots, memory: memory,
                                             overrides: nil, calendar: .current)

        XCTAssertEqual(slots, before, "No per-sport seasons → nothing to do")
    }
}
