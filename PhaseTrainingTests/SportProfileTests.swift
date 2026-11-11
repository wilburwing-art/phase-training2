import XCTest
@testable import PhaseTraining

/// Phase 3b of docs/PLAN-gap-backlog-2026-11b.md: sports without their own
/// rules. Owner report 2026-11-11: a snowboarder in pre-season with 60-minute
/// sessions got "Upper body" days of 3 movements, 1 to 2 sets, about 14 minutes,
/// because every sport outside ski and climbing resolved to the ski
/// maintenance (deload) rule in every season.
final class SportProfileTests: XCTestCase {

    // MARK: - 1. One table

    /// Every membership decision reads the profile table, for every slug the
    /// picker offers and every slug the table holds.
    func test_everyMembershipCheckReadsTheProfile() {
        let slugs = Set(Sport.catalog.map(\.slug)).union(SportProfile.table.keys)
        for slug in slugs.sorted() {
            let p = SportProfile.of(slug)
            XCTAssertEqual(SportSeasonGenerator.supports(slug), p.usesSeasonEngine, slug)
            XCTAssertEqual(SportSeasonGenerator.signatureDemand(slug), p.signature, slug)
            XCTAssertEqual(SessionMix.family(forSport: slug), p.family, slug)
            XCTAssertEqual(SkiSeason.isSkiSport(slug), p.isSki, slug)
            XCTAssertEqual(AuthoredRoutineSelector.pilotSports.contains(slug), p.authoredOverEngine, slug)
            XCTAssertEqual(SportCatalog.outdoorAuthoredSlugs.contains(slug),
                           SportProfile.table[slug]?.rules == .general, slug)
            var m = TrainingMemory()
            m.primarySport = Sport.catalog.first { $0.slug == slug } ?? Sport(slug: slug, name: slug)
            m.sports = [m.primarySport!]
            XCTAssertEqual(m.skisPrimary, p.isSki, slug)
            XCTAssertEqual(m.skis, p.isSki, slug)
        }
    }

    // MARK: - 2. Snowboarding plans as snow-sports (1A)

    private func memory(_ slug: String, _ season: SeasonPhase, exp: ExperienceLevel = .intermediate,
                        equipment: [Equipment] = [.fullGym], days: Int = 3, minutes: Int = 60,
                        week: Int = 1) -> TrainingMemory {
        var m = TrainingMemory()
        let sport = Sport.catalog.first { $0.slug == slug } ?? Sport(slug: slug, name: slug)
        m.primarySport = sport
        m.sports = [sport]
        m.seasonsBySport = [sport: season]
        m.defaultSeason = season
        m.experience = exp
        m.equipment = equipment
        m.liftDaysPerWeek = days
        m.sessionMinutes = minutes
        m.phaseStartedAt = Calendar.current.date(byAdding: .day, value: -7 * (week - 1), to: Date())
        if season == .eventPrep {
            m.peakDate = Calendar.current.date(byAdding: .day, value: 40, to: Date())
        }
        return m
    }

    /// Same rule, same engine, same week shape, same roles and movement counts
    /// as "Skiing / Snowboarding", with Discipline and the two-sport feature.
    func test_snowboardingPlansAsSnowSports() {
        let board = SportProfile.of("snowboarding"), snow = SportProfile.of("snow-sports")
        XCTAssertEqual(board, snow)
        XCTAssertTrue(SportSeasonGenerator.supports("snowboarding"))
        XCTAssertEqual(SportSeasonGenerator.poolSlug(for: "snowboarding"), "alpine-skiing")
        let routines = CoachDatabase.shared.listRoutines()
        for season in SeasonPhase.allCases {
            for variant in SportVariant.skiDisciplines {
                XCTAssertEqual(PhaseRule.resolve(sportSlug: "snowboarding", variant: variant, season: season),
                               PhaseRule.resolve(sportSlug: "snow-sports", variant: variant, season: season),
                               "\(season) \(variant)")
            }
            for days in [2, 3, 5] {
                var a = memory("snowboarding", season, days: days)
                var b = memory("snow-sports", season, days: days)
                a.skiDiscipline = .park; b.skiDiscipline = .park
                XCTAssertTrue(a.skisPrimary)
                XCTAssertEqual(a.primaryVariant, .park)
                let pa = Planner.generate(memory: a, routines: routines, today: Self.monday)
                let pb = Planner.generate(memory: b, routines: routines, today: Self.monday)
                let label = "\(season) \(days)d"
                XCTAssertEqual(pa.days.map(\.kind), pb.days.map(\.kind), label)
                XCTAssertEqual(pa.days.map { $0.kind == .lift ? $0.title : "" },
                               pb.days.map { $0.kind == .lift ? $0.title : "" }, label)
                // The seed carries the slug, so the two pick different
                // movements of the same demands, and a session's length fit
                // can then keep one movement more or fewer.
                for (da, db) in zip(pa.days, pb.days) {
                    let ca = da.generatedWorkout?.exercises.count ?? 0
                    let cb = db.generatedWorkout?.exercises.count ?? 0
                    XCTAssertLessThanOrEqual(abs(ca - cb), 1, "\(label) \(da.title): \(ca) against \(cb)")
                }
                for d in pa.days where d.kind == .lift {
                    XCTAssertFalse(d.generatedWorkout?.provenance.hasPrefix("Authored") ?? true,
                                   "\(label) '\(d.title)' served an authored routine")
                }
            }
        }
    }

    // MARK: - 3. A season rule for the authored-only sports (2A)

    static var plannable: [String] {
        Sport.catalog.map(\.slug).filter(SportCatalog.isPlannable).sorted()
    }

    /// Only the ski and climbing transition phases are deload rules; no
    /// authored-only sport is on one in any season.
    func test_onlyATransitionPhaseResolvesToADeloadRule() {
        XCTAssertTrue(Self.plannable.contains("trail-running"), "\(Self.plannable)")
        for slug in Self.plannable {
            for season in SeasonPhase.allCases {
                let rule = PhaseRule.resolve(sportSlug: slug,
                                             variant: SportSeasonGenerator.defaultVariant(forSport: slug),
                                             season: season)
                let transition = SportProfile.of(slug).usesSeasonEngine && season == .maintenance
                XCTAssertEqual(rule.progression == .deload, transition, "\(slug) \(season): \(rule.progression)")
            }
        }
        XCTAssertEqual(PhaseRule.resolve(sportSlug: "trail-running", variant: .inbounds, season: .offSeason).progression,
                       .progressiveOverload)
        XCTAssertEqual(PhaseRule.resolve(sportSlug: "trail-running", variant: .inbounds, season: .preSeason).progression,
                       .autoregulateHold)
        XCTAssertEqual(PhaseRule.resolve(sportSlug: "trail-running", variant: .inbounds, season: .inSeason).progression,
                       .maintainMinimal)
    }

    /// Across every plannable sport and season, weeks 1 to 4: outside a
    /// mesocycle deload week and a transition phase, no complement day serves
    /// a strength row at deload dose (the `.deload` progression puts these at
    /// RPE 5-6; every other progression, the beginner cap and the week-1 ramp
    /// included, starts the band at 6 or more), and every complement session
    /// sits in the session-length band
    /// GeneratorWeekInvariantTests enforces.
    func test_noComplementDayServesDeloadDoseOutsideADeloadWeek() {
        let strength: Set<Demand> = [.upperPush, .upperPull, .legStrength, .arms]
        let primary = Dictionary(
            CoachDatabase.shared.sportMovements(sport: SportSeasonGenerator.complementPoolSlug)
                .compactMap { m in m.demands.first.map { (m.exerciseId, $0) } },
            uniquingKeysWith: { a, _ in a })
        let routines = CoachDatabase.shared.listRoutines()
        var checked = 0, rows = 0
        var dose: [String] = [], length: [String] = []
        for slug in Self.plannable { for season in SeasonPhase.allCases {
            for exp in [ExperienceLevel.beginner, .advanced] { for eq in [[Equipment.fullGym], [.bodyweight]] {
                for days in [3, 5] { for minutes in [45, 60] { for week in 1...4 {
                    let m = memory(slug, season, exp: exp, equipment: eq, days: days, minutes: minutes, week: week)
                    let athlete = AthleteState.from(m, variant: m.primaryVariant, weekNumber: m.weeksInCurrentPhase ?? 1)
                    if SportSeasonGenerator.cycleStatus(athlete).state == .deload { continue }
                    let rule = PhaseRule.resolve(sportSlug: slug, variant: m.primaryVariant, season: season)
                    let plan = Planner.generate(memory: m, routines: routines, today: Self.monday)
                    let cell = "\(slug)/\(season.rawValue)/\(exp.rawValue)/\(eq.map(\.rawValue))/\(days)d/\(minutes)min/wk\(week)"
                    for d in plan.days where d.kind == .lift && d.isComplementSession {
                        guard let g = d.generatedWorkout, !g.exercises.isEmpty else { continue }
                        checked += 1
                        let usable = min(Double(minutes), Double(rule.sessionMinutesTarget.upperBound))
                        let share = exp != .beginner ? 0.6 : (rule.deferToSport ? 0.4 : 0.5)
                        if Double(g.estimatedMinutes) > Double(minutes) + 5
                            || Double(g.estimatedMinutes) < share * usable {
                            length.append("[\(cell)] '\(g.title)' est=\(g.estimatedMinutes)")
                        }
                        // The ski and climbing transition phases are deload
                        // phases by design.
                        guard !(SportProfile.of(slug).usesSeasonEngine && season == .maintenance) else { continue }
                        for e in g.exercises where strength.contains(primary[e.exerciseId] ?? .core) {
                            rows += 1
                            let low = e.rpe?.split(whereSeparator: { !"0123456789.".contains($0) })
                                .compactMap { Double($0) }.first ?? 0
                            if low < 6 { dose.append("[\(cell)] '\(g.title)' \(e.name) \(e.sets)x\(e.reps) RPE \(e.rpe ?? "-")") }
                        }
                    }
                } } }
            } }
        } }
        print("[3b] complement sessions checked \(checked), strength rows \(rows), deload-dose \(dose.count), out of band \(length.count)")
        XCTAssertGreaterThan(checked, 1000)
        XCTAssertTrue(dose.isEmpty, "\(dose.count) deload-dose rows, first: \(dose.prefix(3))")
        XCTAssertTrue(length.isEmpty, "\(length.count) complement sessions out of band, first: \(length.prefix(3))")
    }

    // MARK: - 4. Signature demands

    /// Pinned per sport. For the authored-only sports no engine sport session
    /// reads the signature yet (their sport days are authored routines and
    /// `sport_movements` holds no pool for them), so this is table data.
    func test_signatureDemandPerSport() {
        let expected: [String: Demand?] = [
            "alpine-skiing": .eccentricLeg, "snowboarding": .eccentricLeg, "climbing": .fingerStrength,
            "trail-running": .eccentricLeg, "mountaineering": .legEndurance,
            "hiking-trekking": .legEndurance, "thru-hiking": .legEndurance, "mountain-biking": nil,
        ]
        for (slug, demand) in expected {
            XCTAssertEqual(SportSeasonGenerator.signatureDemand(slug), demand, slug)
        }
    }

    // MARK: - 5. Mountaineering complement emphasis

    /// A mountaineer's complement days lead with the upper back and the trunk:
    /// at every complement count the week's pulling weight outweighs its
    /// pressing, every day trains core, and the week still presses (the push
    /// floor). Generated weeks carry more upper-back sets (rows, pulldowns,
    /// face pulls) than pressing sets, and no complement day loads legs as
    /// the prime mover.
    func test_mountaineeringComplementsLeadWithUpperBackAndTrunk() {
        let family = SessionMix.family(forSport: "mountaineering")
        XCTAssertEqual(family, .legsAndCarry)
        for count in 1...4 {
            let rotation = SessionMix.complementRotation(family: family, count: count)
            let pull = rotation.reduce(0) { $0 + ($1.demandWeights[.upperPull] ?? 0) }
            let push = rotation.reduce(0) { $0 + ($1.demandWeights[.upperPush] ?? 0) }
            XCTAssertGreaterThan(pull, push, "\(count): \(rotation)")
            XCTAssertGreaterThan(push, 0, "\(count): \(rotation) presses nothing")
            for focus in rotation {
                XCTAssertGreaterThan(focus.demandWeights[.core] ?? 0, 0, "\(count): \(focus)")
                XCTAssertNil(focus.demandWeights[.legStrength], "\(count): \(focus)")
            }
        }
        let legBuckets: Set<String> = ["quads", "hamstrings", "glutes", "calves"]
        let routines = CoachDatabase.shared.listRoutines()
        for season in SeasonPhase.allCases {
            for days in [3, 5, 6] {
                let plan = Planner.generate(memory: memory("mountaineering", season, days: days),
                                            routines: routines, today: Self.monday)
                let complements = plan.days.filter { $0.kind == .lift && $0.isComplementSession }
                for d in complements {
                    let rows = d.generatedWorkout?.exercises ?? []
                    XCTAssertGreaterThanOrEqual(rows.count, 3, "\(season) \(days)d '\(d.title)'")
                    for e in rows {
                        let b = WorkoutGenerator.primaryMuscleBuckets(exerciseId: e.exerciseId)
                        XCTAssertTrue(b.isDisjoint(with: legBuckets), "\(season) \(days)d '\(d.title)' \(e.name) \(b)")
                    }
                }
                let push = WorkoutGenerator.patternSets(complements.compactMap(\.generatedWorkout),
                                                        SportSeasonGenerator.pushPatterns)
                let pull = WorkoutGenerator.patternSets(complements.compactMap(\.generatedWorkout),
                                                        SessionMix.pullPatterns.union(["scapular-retraction"]))
                if !complements.isEmpty {
                    XCTAssertGreaterThan(pull, push, "\(season) \(days)d: pull \(pull) push \(push) \(complements.map(\.title))")
                }
            }
        }
    }

    // MARK: - 6. A demoted lift day leaves the roles a rebuild finds

    /// Rebuilds every lift day the way `PlanStore.applyRecovery` does (its
    /// lift index, the plan's current lift-day count) and checks the day
    /// keeps its role: same title, complement or sport as before.
    private func assertRebuildKeepsRoles(_ plan: WeekPlan, _ m: TrainingMemory, _ label: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let lifts = plan.days.filter { $0.kind == .lift }
        let profile = DemographicProfile.from(m)
        for (n, d) in lifts.enumerated() where d.generatedWorkout != nil && d.routineId == nil {
            let rebuilt = WorkoutGenerator.generateLift(
                liftIndex: d.liftIndex ?? n, totalLifts: lifts.count, memory: m, profile: profile,
                hashSeed: m.planInputsHash, date: d.date)
            XCTAssertEqual(rebuilt.title, d.title, "\(label): lift \(n) of \(lifts.count)", file: file, line: line)
            XCTAssertEqual(rebuilt.provenance.hasPrefix("complement"), d.isComplementSession,
                           "\(label): lift \(n) '\(d.title)'", file: file, line: line)
        }
    }

    private func liftWeekdays(_ plan: WeekPlan) -> [Weekday] {
        plan.days.filter { $0.kind == .lift }.map { Weekday.from(date: $0.date) }
    }

    func test_arcDeload_rebuildKeepsEveryRole() {
        let routines = CoachDatabase.shared.listRoutines()
        var demoted = 0
        for slug in ["alpine-skiing", "climbing", "trail-running"] {
            for season in [SeasonPhase.offSeason, .preSeason, .inSeason] {
                for days in [3, 4, 5] {
                    let m = memory(slug, season, days: days)
                    let normal = Planner.generate(memory: m, routines: routines, today: Self.monday)
                    let plan = Planner.generate(memory: m, routines: routines, today: Self.monday, deloadWeek: true)
                    let label = "deload \(slug) \(season) \(days)d"
                    if plan.days.contains(where: { $0.title == "Recovery" }) {
                        demoted += 1
                        XCTAssertEqual(plan.days.filter { $0.kind == .lift }.count,
                                       normal.days.filter { $0.kind == .lift }.count - 1, label)
                    }
                    assertRebuildKeepsRoles(plan, m, label)
                }
            }
        }
        XCTAssertGreaterThan(demoted, 10)
    }

    func test_skipStreak_rebuildKeepsEveryRole() {
        let routines = CoachDatabase.shared.listRoutines()
        var demoted = 0
        for slug in ["alpine-skiing", "climbing", "trail-running"] {
            for season in [SeasonPhase.offSeason, .preSeason, .inSeason] {
                for days in [3, 4, 5] {
                    let m = memory(slug, season, days: days)
                    let normal = Planner.generate(memory: m, routines: routines, today: Self.monday)
                    for weekday in Set(liftWeekdays(normal)) {
                        let plan = Planner.generate(memory: m, routines: routines, today: Self.monday,
                                                    deEmphasizedWeekdays: [weekday])
                        let label = "streak \(slug) \(season) \(days)d \(weekday)"
                        if plan.days.contains(where: { $0.generatedReason?.contains("hasn't been working") ?? false }) {
                            demoted += 1
                        }
                        assertRebuildKeepsRoles(plan, m, label)
                    }
                }
            }
        }
        XCTAssertGreaterThan(demoted, 10)
    }

    /// Two light races beside the lift days build the 3+ high-CNS runs the
    /// balance pass demotes in. Light, because a moderate or hard race tapers
    /// the day before inside `generateUnbiased`, which is a separate demotion
    /// (left open, see the Phase 3b report).
    func test_cnsBalance_rebuildKeepsEveryRole() {
        let routines = CoachDatabase.shared.listRoutines()
        var demoted = 0
        let cal = Calendar.current
        for slug in ["alpine-skiing", "climbing", "trail-running"] {
            for season in [SeasonPhase.offSeason, .preSeason] {
                for days in [3, 4, 5] {
                    let m = memory(slug, season, days: days)
                    for pair in [(1, 3), (2, 4), (0, 2), (3, 5), (1, 4), (0, 1), (2, 3), (4, 5)] {
                        var o = WeekOverrides(weekStart: Self.monday)
                        for d in [pair.0, pair.1] {
                            o.events.append(WeekEvent(date: cal.date(byAdding: .day, value: d, to: Self.monday)!,
                                                      title: "Race", kind: .race, intensity: .light))
                        }
                        let plan = Planner.generate(memory: m, overrides: o, routines: routines, today: Self.monday)
                        let label = "cns \(slug) \(season) \(days)d races \(pair)"
                        if plan.days.contains(where: { $0.generatedReason?.contains("balanced against") ?? false }) {
                            demoted += 1
                        }
                        assertRebuildKeepsRoles(plan, m, label)
                    }
                }
            }
        }
        print("[3b] cns demotions \(demoted)")
        XCTAssertGreaterThan(demoted, 0)
    }

    // MARK: - Owner case

    static func ownerMemory() -> TrainingMemory {
        var m = TrainingMemory()
        let sport = Sport.catalog.first { $0.slug == "snowboarding" }!
        m.primarySport = sport
        m.sports = [sport]
        m.seasonsBySport = [sport: .preSeason]
        m.defaultSeason = .preSeason
        m.experience = .advanced
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        m.sessionMinutes = 60
        m.age = 36
        m.gender = .male
        m.phaseStartedAt = Calendar.current.date(byAdding: .day, value: -7, to: Date())
        return m
    }

    static var monday: Date {
        var cal = Calendar.current; cal.firstWeekday = 2
        var comps = DateComponents(); comps.year = 2026; comps.month = 11; comps.day = 9
        return cal.date(from: comps)!
    }

    /// Prints the owner's week (evidence for the phase report).
    func test_ownerCase_printsWeek() {
        let plan = Planner.generate(memory: Self.ownerMemory(),
                                    routines: CoachDatabase.shared.listRoutines(),
                                    today: Self.monday)
        let f = DateFormatter(); f.dateFormat = "EEE"
        var lines: [String] = []
        for d in plan.days {
            let g = d.generatedWorkout
            lines.append("\(f.string(from: d.date)) \(d.kind.rawValue) '\(g?.title ?? d.title)'"
                + (g.map { " est=\($0.estimatedMinutes)min prov=\($0.provenance)" } ?? ""))
            for e in g?.exercises ?? [] {
                lines.append("    \(e.name): \(e.sets) x \(e.reps) rpe=\(e.rpe ?? "-")")
            }
        }
        print("[OWNER]\n" + lines.joined(separator: "\n") + "\n[/OWNER]")
        // Item 7: what the selector serves for the four cells with no routine
        // of their own phase.
        var cells: [String] = []
        for (slug, season) in [("mountaineering", SeasonPhase.inSeason), ("hiking-trekking", .inSeason),
                               ("thru-hiking", .inSeason), ("trail-running", .preSeason)] {
            let ids = (0..<3).map {
                AuthoredRoutineSelector.select(sportSlug: slug, phase: season, sessionIndex: $0,
                                               experience: .advanced)
            }
            let p = Planner.generate(memory: memory(slug, season, exp: .advanced, days: 3),
                                     routines: CoachDatabase.shared.listRoutines(), today: Self.monday)
            cells.append("\(slug) \(season.rawValue): select slot0-2 = \(ids.map { $0.map(String.init) ?? "nil" }) week = "
                + p.days.filter { $0.kind == .lift }.map { "'\($0.title)'" }.joined(separator: ", "))
        }
        print("[CELLS]\n" + cells.joined(separator: "\n") + "\n[/CELLS]")
        XCTAssertFalse(plan.days.isEmpty)
    }
}
