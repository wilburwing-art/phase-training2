import XCTest
@testable import PhaseTraining

/// Phase 2 of docs/PLAN-gap-backlog-2026-11b.md. Whole-week properties from
/// audits/2026-11-10-gap-round/generator.md (findings 4, 5, 6, 8, 9, 11),
/// driven through `Planner.generate`, the same path the app takes. Every
/// failure message names the grid cell. Phase 3 made all eight hold; where a
/// cell's scope was narrowed, the test says why beside the check.
final class GeneratorWeekInvariantTests: XCTestCase {

    // MARK: - Grid

    struct Cell: CustomStringConvertible {
        let sport: String, season: SeasonPhase, exp: ExperienceLevel
        let equipName: String, equip: [Equipment]
        let days: Int, minutes: Int, week: Int
        var description: String {
            "\(sport)/\(season.rawValue)/\(exp.rawValue)/\(equipName)/\(days)lift/\(minutes)min/wk\(week)"
        }
    }

    /// Every sport the app plans for (11c 2.1). Authored-only sports reach
    /// these checks through their complement days, which run on
    /// `PhaseRule.general` (Phase 3b); `engineSessions` drops their
    /// authored sport days.
    static let plannableSports = Sport.catalog.map(\.slug).filter(SportCatalog.isPlannable)

    /// The grid's sports: one per `SportProfile` (11e 1.4). A sport with its
    /// own profile row is its own entry. Sports that inherit a family row get
    /// the same `.general` profile, so their engine sessions match and the
    /// first one by slug stands for the family. The known-failure sets ride
    /// along so their exact assertions still see every sport they name.
    /// Every plannable sport took 175 s of grid build on the dev Mac and
    /// 472 s on CI, past the unit job's 25-minute timeout (run 44544230552).
    static let sports: [String] = {
        var seen: Set<String> = []
        let sampled = plannableSports.sorted().filter { slug in
            let key = SportProfile.familySlug(of: slug).map { "family:\($0)" } ?? slug
            return seen.insert(key).inserted
        }
        let known = knownRegressionSports.union(knownDeloadBandSports).union(knownAnchorDriftSports)
        return sampled + known.subtracting(sampled).sorted()
    }()
    static let equipTiers: [(String, [Equipment])] = [
        ("bw", [.bodyweight]), ("homebar", [.dumbbells, .pullUpBar, .bands]), ("gym", [.fullGym])]

    /// Sports whose own tests filter the grid to them (ski push floor,
    /// climbing push:pull) keep every session length.
    static let fullMinutesSports: Set<String> = ["alpine-skiing", "climbing"]
    static let minuteTiers = [30, 45, 75]

    /// Other sports take one session length per cell, rotated over
    /// experience, equipment and days, so every (sport, phase, days) and every
    /// (sport, experience, equipment) still sees all three lengths (11e 1.4).
    static var weekGrid: [Cell] {
        var out: [Cell] = []
        for s in sports { for p in SeasonPhase.allCases {
            for (ei, e) in ExperienceLevel.allCases.enumerated() {
            for (qi, eq) in equipTiers.enumerated() { for d in 2...6 {
                let minutes = fullMinutesSports.contains(s)
                    ? minuteTiers : [minuteTiers[(ei + qi + d) % minuteTiers.count]]
                for m in minutes {
                    out.append(Cell(sport: s, season: p, exp: e, equipName: eq.0, equip: eq.1,
                                    days: d, minutes: m, week: 1))
                }
            } }
        } } }
        return out
    }

    /// Anchor and ramp checks: off-season is the only phase on
    /// progressiveOverload, so it is the only one that owes a ramp.
    static var blockGrid: [Cell] {
        var out: [Cell] = []
        for s in sports { for e in ExperienceLevel.allCases { for d in [3, 4] {
            for w in 1...3 {
                out.append(Cell(sport: s, season: .offSeason, exp: e, equipName: "gym", equip: [.fullGym],
                                days: d, minutes: 45, week: w))
            }
        } } }
        return out
    }

    struct Week { let cell: Cell; let plan: WeekPlan }

    private func memory(_ c: Cell, affinities: Set<String> = []) -> TrainingMemory {
        var m = TrainingMemory()
        m.exerciseAffinities = Dictionary(uniqueKeysWithValues: affinities.map { ($0, 5) })
        let sport = Sport.catalog.first { $0.slug == c.sport } ?? Sport(slug: c.sport, name: c.sport)
        m.primarySport = sport
        m.sports = [sport]
        m.seasonsBySport = [sport: c.season]
        m.defaultSeason = c.season
        m.experience = c.exp
        m.equipment = c.equip
        m.liftDaysPerWeek = c.days
        m.sessionMinutes = c.minutes
        m.phaseStartedAt = Calendar.current.date(byAdding: .day, value: -7 * (c.week - 1), to: Date())
        if c.season == .eventPrep {
            m.peakDate = Calendar.current.date(byAdding: .day, value: 40, to: Date())
        }
        return m
    }

    private func plan(_ c: Cell, routines: [BundledRoutineRow], affinities: Set<String> = [],
                      recentlyPicked: Set<Int> = []) -> Week {
        let m = memory(c, affinities: affinities)
        var cal = Calendar.current; cal.firstWeekday = 2
        var comps = DateComponents(); comps.year = 2026; comps.month = 11; comps.day = 9
        let monday = cal.date(from: comps)!
        return Week(cell: c, plan: Planner.generate(memory: m, routines: routines,
                                                           recentlyPicked: recentlyPicked, today: monday))
    }

    private static var cache: [Week]?
    private static var blockCache: [Week]?

    private func weeks() -> [Week] {
        if let c = Self.cache { return c }
        let routines = CoachDatabase.shared.listRoutines()
        print("[GWI] grid sports: \(Self.sports.count) of \(Self.plannableSports.count) plannable: \(Self.sports)")
        let w = Self.weekGrid.map { plan($0, routines: routines) }
        Self.cache = w
        return w
    }

    private func blockWeeks() -> [Week] {
        if let c = Self.blockCache { return c }
        let routines = CoachDatabase.shared.listRoutines()
        let w = Self.blockGrid.map { plan($0, routines: routines) }
        Self.blockCache = w
        return w
    }

    // MARK: - Helpers

    /// Season-engine lift sessions only: authored routines ignore the budget
    /// and carry no RPE, so they are out of scope for these properties.
    private func engineSessions(_ w: Week) -> [GeneratedWorkout] {
        w.plan.days.compactMap { d in
            guard d.kind == .lift, let g = d.generatedWorkout,
                  !g.provenance.hasPrefix("Authored"), !g.exercises.isEmpty,
                  g.exercises.allSatisfy({ $0.id.hasPrefix("ss-") }) else { return nil }
            return g
        }
    }

    private func rpeRange(_ s: String?) -> (Double, Double)? {
        guard let s else { return nil }
        let nums = s.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
        guard let lo = nums.first else { return nil }
        return (lo, nums.last ?? lo)
    }

    private func isExplosive(_ e: GeneratedExercise) -> Bool {
        e.tempo?.uppercased().contains("X") == true
    }

    private func repsLow(_ e: GeneratedExercise) -> Int? {
        Int(e.reps.prefix { $0.isNumber })
    }

    private func midRPE(_ e: GeneratedExercise) -> Double {
        rpeRange(e.rpe).map { ($0.0 + $0.1) / 2 } ?? 0
    }

    // MARK: - 1. Session length (finding 4)

    /// Holds on every engine session: 4,383 of 6,588 were out of band on
    /// a19732e, before `fitToBudget`.
    func test_sessionLengthTracksBudget() {
        var checked = 0
        var bad: [String] = []
        for w in weeks() {
            for g in engineSessions(w) {
                checked += 1
                let b = Double(w.cell.minutes)
                // The floor is 60% of the budget the phase lets a session use:
                // in-season, maintenance and event prep cap a session at 45 or
                // 55 minutes whatever the budget (T2-7), so a 75-minute
                // budget there owes 60% of the phase ceiling, not of 75.
                let rule = PhaseRule.resolve(sportSlug: w.cell.sport,
                                             variant: SportSeasonGenerator.defaultVariant(forSport: w.cell.sport),
                                             season: w.cell.season)
                let usable = min(b, Double(rule.sessionMinutesTarget.upperBound))
                // Beginners owe less: their 3-set ceiling (SetScheme.adjusted)
                // and the phase fatigue cap stop a bodyweight beginner near 40
                // of 75 minutes, near 25 of a deload phase's 45, and at 20 in
                // a skimo in-season week whose four movements already fill the
                // cap of 10. The only way past that is filler movements, so
                // the floor is 50%, and 40% in the fatigue-shedding phases.
                let share = w.cell.exp != .beginner ? 0.6 : (rule.deferToSport ? 0.4 : 0.5)
                if Double(g.estimatedMinutes) > b + 5 || Double(g.estimatedMinutes) < share * usable {
                    bad.append("[\(w.cell)] est=\(g.estimatedMinutes) budget=\(w.cell.minutes) '\(g.title)'")
                }
            }
        }
        XCTAssertGreaterThan(checked, 2000, "only \(checked) engine sessions checked")
        print("[GWI] session-length: \(bad.count) of \(checked) sessions out of band")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) sessions out of band, first: \(bad.prefix(3))")
    }

    /// The authored half of the 2.1 length invariant (11c 3.5): an authored
    /// lift day serves a routine whose estimated length sits within
    /// `durationTolerance` of the closest candidate's distance to the budget.
    /// The served minutes are not held to the budget itself: most pools have
    /// nothing near 75.
    func test_authoredSessionPicksTheRoutineClosestToBudget() {
        var checked = 0, pooled = 0
        var bad: [String] = []
        var poolCache: [String: [Int]] = [:]
        var minutesCache: [String: Int] = [:]
        for w in weeks() {
            let lifts = w.plan.days.compactMap { d -> Int? in
                d.kind == .lift ? d.generatedWorkout?.authoredRoutineId : nil
            }
            guard !lifts.isEmpty else { continue }
            // The memory and profile `Planner.generate` builds for this cell.
            let m = memory(w.cell)
            guard let sport = m.primarySport else { continue }
            let profile = DemographicProfile.from(m)
            let prefs = RoutinePreferences.from(m)
            let season = m.seasonsBySport[sport] ?? m.defaultSeason
            let week = m.weeksInCurrentPhase ?? 1
            let key = "\(sport.slug)/\(season.rawValue)/\(w.cell.exp.rawValue)/\(w.cell.equipName)"
            let pool = poolCache[key] ?? AuthoredRoutineSelector.candidates(
                sportSlug: sport.slug, phase: season, experience: m.experience,
                excludedExerciseIds: profile.excludedExerciseIds,
                allowedEquipmentSlugs: profile.allowedEquipmentSlugs, preferences: prefs)
            poolCache[key] = pool
            func minutes(_ id: Int) -> Int {
                let k = "\(id)/\(w.cell.exp.rawValue)/\(w.cell.equipName)/wk\(week)"
                if let v = minutesCache[k] { return v }
                let v = AuthoredRoutineSelector.estimatedMinutes(
                    forRoutineId: id, excluded: profile.excludedExerciseIds,
                    allowed: profile.allowedEquipmentSlugs, preferences: prefs,
                    experience: m.experience, planWeek: week)
                minutesCache[k] = v
                return v
            }
            let budget = m.sessionMinutes
            for served in lifts {
                checked += 1
                if pool.count > 1 { pooled += 1 }
                guard pool.contains(served) else {
                    bad.append("[\(w.cell)] served \(served) outside candidates \(pool)")
                    continue
                }
                let best = pool.map { abs(minutes($0) - budget) }.min() ?? 0
                let gap = abs(minutes(served) - budget)
                if gap > best + AuthoredRoutineSelector.durationTolerance {
                    bad.append("[\(w.cell)] served \(served) at \(minutes(served)) min, gap \(gap) vs best \(best) "
                               + "over \(pool.map { "\($0):\(minutes($0))" })")
                }
            }
        }
        print("[GWI] authored-length: \(bad.count) of \(checked) (\(pooled) from pools of two or more)")
        XCTAssertGreaterThan(checked, 0, "no authored lift days in the grid")
        XCTAssertGreaterThan(pooled, 0, "no authored lift day drew from a pool of two or more")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) authored days off the closest length, first: \(bad.prefix(3))")
    }

    // MARK: - 1b. Deload dose (finding 9)

    /// Off-season and pre-season run a 4-week cycle, in-season a 6-week one.
    static let deloadPhases: [(SeasonPhase, Int)] = [(.offSeason, 4), (.preSeason, 4), (.inSeason, 6)]

    private func engineSets(_ w: Week) -> Int {
        engineSessions(w).flatMap(\.exercises).reduce(0) { $0 + $1.sets }
    }

    /// A deload week is the same size for every sport: engine sets in the
    /// deload week over the week before it. The audit measured a 46% cut for
    /// ski and 13% for climbing before `deloadSetsFactor`.
    func test_deloadWeekCutsSetsByOneShareAcrossSports() {
        assertDeloadBand(rotated: false)
    }

    /// In the app the week before's accessories are in `recentMovementIDs`
    /// when the deload week is planned. The deload week still serves that
    /// week's session at 70% of its sets, so rotation must not swap them
    /// out (11e 1.7).
    func test_deloadWeekCutsSetsByOneShareUnderRotation() {
        assertDeloadBand(rotated: true)
    }

    private func assertDeloadBand(rotated: Bool) {
        let routines = CoachDatabase.shared.listRoutines()
        var swapped = 0
        var ratios: [(String, Double)] = []
        var bad: [String] = []
        var failingSports: Set<String> = []
        for s in Self.sports { for (phase, cycle) in Self.deloadPhases {
            for e in [ExperienceLevel.beginner, .intermediate, .advanced] {
                func cell(_ wk: Int) -> Cell {
                    Cell(sport: s, season: phase, exp: e, equipName: "gym", equip: [.fullGym],
                         days: 4, minutes: 45, week: wk)
                }
                let beforeWeek = plan(cell(cycle - 1), routines: routines)
                let recent = rotated
                    ? Set(beforeWeek.plan.days.compactMap(\.generatedWorkout).flatMap(\.exercises).map(\.exerciseId))
                    : []
                let deloadWeek = plan(cell(cycle), routines: routines, recentlyPicked: recent)
                let before = engineSets(beforeWeek)
                let deload = engineSets(deloadWeek)
                guard before > 0 else { continue }
                let ids = { (w: Week) in Set(self.engineSessions(w).flatMap(\.exercises).map(\.exerciseId)) }
                if ids(beforeWeek) != ids(deloadWeek) { swapped += 1 }
                let r = Double(deload) / Double(before)
                let tag = "\(s)/\(phase.rawValue)/\(e.rawValue)"
                ratios.append((tag, r))
                if r < 0.6 || r > 0.8 {
                    failingSports.insert(s)
                    if Self.knownDeloadBandSports.contains(s) { continue }
                    bad.append("[\(tag)] \(before) -> \(deload) sets = \(String(format: "%.2f", r))")
                }
            }
        } }
        XCTAssertGreaterThan(ratios.count, 20, "only \(ratios.count) sport x phase cells had engine sets")
        let lo = ratios.map(\.1).min() ?? 0, hi = ratios.map(\.1).max() ?? 0
        print("[GWI] deload rotated=\(rotated): \(swapped) of \(ratios.count) weeks changed movements")
        print("[GWI] deload rotated=\(rotated): \(ratios.count) cells, share \(String(format: "%.2f", lo))...\(String(format: "%.2f", hi)), \(bad.count) outside 0.60...0.80")
        // 0.60...0.80 is the one band: 0.7 per row, rounded on 2 to 5 set
        // rows, with cited protocol rows exempt. Measured 0.60...0.79 over
        // 126 cells on 58dcb08.
        print("[GWI] deload failing sports: \(failingSports.sorted())")
        XCTAssertEqual(failingSports.intersection(Self.knownDeloadBandSports), Self.knownDeloadBandSports,
                       "a known deload-band sport now passes; remove it from knownDeloadBandSports")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(ratios.count) deload weeks outside 60-80% of the week before, first: \(bad.prefix(3))")
    }

    // MARK: - 2. Rest day (finding 8)

    /// Holds: `Planner.reserveRestDay` keeps one (621 of 2,025 weeks had none
    /// on a19732e).
    func test_everyWeekHasARestDay() {
        var bad: [String] = []
        let all = weeks()
        for w in all where !w.plan.days.contains(where: { $0.kind == .rest }) {
            bad.append("[\(w.cell)] pattern \(w.plan.days.map { String($0.kind.rawValue.first!) }.joined())")
        }
        XCTAssertGreaterThan(all.count, 2000, "only \(all.count) weeks checked")
        XCTAssertTrue(all.contains { $0.cell.days >= 5 }, "no 5 or 6 day cells in the grid")
        print("[GWI] rest-day: \(bad.count) of \(all.count) weeks have no rest day")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(all.count) weeks have no rest day, first: \(bad.prefix(3))")
    }

    // MARK: - 3. Exercise order (finding 5)

    /// Holds: the engine sorts each session into training order (1,808
    /// violations over 6,588 sessions on a19732e). Also holds the squat cap:
    /// at most one heavy bilateral squat per session.
    func test_powerNeverFollowsHeavyStrength_andHeaviestLiftIsEarly() {
        var checked = 0
        var bad: [String] = []
        for w in weeks() {
            for g in engineSessions(w) {
                checked += 1
                let rows = g.exercises
                var seenHeavy: String?
                for e in rows {
                    let heavy = !isExplosive(e) && (rpeRange(e.rpe)?.0 ?? 0) >= 7
                    if isExplosive(e), let h = seenHeavy {
                        bad.append("[\(w.cell)] power '\(e.name)' after RPE7+ '\(h)'")
                        break
                    }
                    if heavy, seenHeavy == nil { seenHeavy = e.name }
                }
                // Heaviest compound: fewest reps among RPE 7+ non-explosive compounds,
                // earliest on a tie. It must sit in the first two non-explosive
                // slots. Explosive rows are not counted against it: a ski
                // pre-season session carries two or three jumps (power 0.20),
                // and they belong ahead of the heavy lift, which the first
                // assertion above requires.
                let cands = rows.enumerated().filter {
                    $0.element.isCompound && !isExplosive($0.element)
                        && (rpeRange($0.element.rpe)?.0 ?? 0) >= 7 && repsLow($0.element) != nil
                }
                if w.cell.equipName != "bw", let minReps = cands.compactMap({ repsLow($0.element) }).min(),
                   let first = cands.first(where: { repsLow($0.element) == minReps }),
                   rows.prefix(first.offset).filter({ !isExplosive($0) }).count > 1 {
                    bad.append("[\(w.cell)] heaviest compound '\(first.element.name)' in slot \(first.offset + 1)")
                }
                let squats = rows.filter {
                    $0.isCompound && !isExplosive($0) && (rpeRange($0.rpe)?.0 ?? 0) >= 7
                        && CoachDatabase.shared.patternsForExercise($0.exerciseId).contains("squat")
                }
                if squats.count > 1 {
                    bad.append("[\(w.cell)] \(squats.count) heavy squats: \(squats.map(\.name))")
                }
            }
        }
        XCTAssertGreaterThan(checked, 2000, "only \(checked) engine sessions checked")
        print("[GWI] order: \(bad.count) violations over \(checked) sessions")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) order violations over \(checked) sessions, first: \(bad.prefix(3))")
    }

    // MARK: - 4. Loadable strength slots (finding 6)

    /// Holds: strength slots rank loadable movements first when the athlete
    /// owns the equipment (268 of 2,072 heavy gym slots were regressions on
    /// a19732e). `knownRegressionSports` failed when the grid widened to every
    /// plannable sport (11c 2.1, 22 slots on 58dcb08, Glute Bridge and
    /// Lunge (Bodyweight)); it is asserted exactly, so fixing one sport
    /// without removing it fails, and so does a new sport.
    /// Empty since 11e 1.5: ten sports (86 of 16,723 slots) served Glute
    /// Bridge or Lunge (Bodyweight) on complement legs days until beginner
    /// bodyweight movements ranked as regressions in strength slots.
    static let knownRegressionSports: Set<String> = []

    /// Backlog 11e 1.1 widened the grid to the family sports with routines.
    /// These two sets pinned what that widening found, exactly, the same way
    /// `knownRegressionSports` does. Both emptied by 11e 1.5: the deload week
    /// reuses the week before's accessory seed, and backfilled anchor rows
    /// tie-break on the block seed.
    static let knownDeloadBandSports: Set<String> = []
    static let knownAnchorDriftSports: Set<String> = []

    func test_gymStrengthSlotsAreLoadable() {
        let regressions: Set<String> = ["Push-Up", "Push Up (Knees)", "Chest Press (Band)",
                                        "Glute Bridge", "Lunge (Bodyweight)", "Squat (Bodyweight)"]
        var checked = 0
        var bad: [String] = []
        var failingSports: Set<String> = []
        for w in weeks() where w.cell.equipName == "gym" && w.cell.exp != .beginner {
            for g in engineSessions(w) {
                for e in g.exercises where e.sets >= 3 {
                    guard let r = rpeRange(e.rpe), r.0 >= 7, r.1 <= 8, !isExplosive(e) else { continue }
                    checked += 1
                    if regressions.contains(e.name) {
                        failingSports.insert(w.cell.sport)
                        if Self.knownRegressionSports.contains(w.cell.sport) { continue }
                        bad.append("[\(w.cell)] '\(e.name)' \(e.sets)x\(e.reps) RPE \(e.rpe ?? "")")
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000, "only \(checked) heavy slots checked")
        print("[GWI] loadable failing sports: \(failingSports.sorted())")
        print("[GWI] loadable: \(bad.count) of \(checked) heavy gym slots are regressions outside \(Self.knownRegressionSports.sorted())")
        XCTAssertEqual(failingSports.intersection(Self.knownRegressionSports), Self.knownRegressionSports,
                       "a known regression sport now passes; remove it from knownRegressionSports")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) heavy slots are bodyweight or band regressions, first: \(bad.prefix(3))")
    }

    // MARK: - 5. In-block progression (finding 9)

    /// Demands whose picks are a session's anchor lifts.
    private static let anchorSlots: Set<String> = ["maxStrength", "upperStrength", "pullStrength",
                                                   "legStrength", "upperPush", "upperPull"]

    private func anchors(_ w: Week) -> [Int] {
        // Per engine session in day order, the sorted ids of the rows filling a
        // strength slot, read from the provenance's demand list (one entry per
        // row, in row order). The first draft took the first RPE 7+ compound,
        // which stopped naming the anchor once the ramp put week 1 one RPE
        // under the band: a beginner's week-1 squat reads RPE 6.
        engineSessions(w).flatMap { g -> [Int] in
            guard let r = g.provenance.range(of: "demands: ") else { return [] }
            let slots = g.provenance[r.upperBound...].split(separator: "/").map(String.init)
            return zip(slots, g.exercises).filter { Self.anchorSlots.contains($0.0) }.map(\.1.exerciseId).sorted()
        }
    }

    private func load(_ w: Week) -> Double {
        engineSessions(w).flatMap(\.exercises).reduce(0) { $0 + Double($1.sets) * midRPE($1) }
    }

    private func blockGroups() -> [[Week]] {
        let all = blockWeeks()
        var groups: [String: [Week]] = [:]
        for w in all {
            let c = w.cell
            groups["\(c.sport)/\(c.exp.rawValue)/\(c.days)lift", default: []].append(w)
        }
        return groups.values.map { $0.sorted { $0.cell.week < $1.cell.week } }
    }

    /// Holds: anchor demands are seeded by the block, not the week (18 of 18
    /// blocks changed anchor on a19732e).
    func test_anchorLiftStaysTheSameAcrossWeeks1to3() {
        var checked = 0
        var bad: [String] = []
        var failingSports: Set<String> = []
        for g in blockGroups() {
            guard g.count == 3 else { continue }
            let a = g.map(anchors)
            guard a.allSatisfy({ !$0.isEmpty }) else { continue }
            checked += 1
            if !(a[0] == a[1] && a[1] == a[2]) {
                failingSports.insert(g[0].cell.sport)
                if Self.knownAnchorDriftSports.contains(g[0].cell.sport) { continue }
                bad.append("[\(g[0].cell.sport)/\(g[0].cell.exp.rawValue)/\(g[0].cell.days)lift] anchors by week \(a)")
            }
        }
        XCTAssertGreaterThan(checked, 10, "only \(checked) blocks checked")
        print("[GWI] anchor failing sports: \(failingSports.sorted())")
        print("[GWI] anchor: \(bad.count) of \(checked) blocks change anchor lift")
        XCTAssertEqual(failingSports.intersection(Self.knownAnchorDriftSports), Self.knownAnchorDriftSports,
                       "a known anchor-drift sport now passes; remove it from knownAnchorDriftSports")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) blocks change anchor, first: \(bad.prefix(3))")
    }

    /// Holds: anchor-lift RPE climbs over the build weeks (`SetScheme.ramped`);
    /// 18 of 18 blocks were flat on a19732e.
    func test_weeklyLoadRampsAcrossWeeks1to3() {
        var checked = 0
        var bad: [String] = []
        for g in blockGroups() {
            guard g.count == 3 else { continue }
            let l = g.map(load)
            guard l.allSatisfy({ $0 > 0 }) else { continue }
            checked += 1
            // Flat (all equal) fails; any rise from week 1 to week 3 passes.
            if !(l[2] > l[0]) {
                bad.append("[\(g[0].cell.sport)/\(g[0].cell.exp.rawValue)/\(g[0].cell.days)lift] sets x RPE by week \(l)")
            }
        }
        XCTAssertGreaterThan(checked, 10, "only \(checked) blocks checked")
        print("[GWI] ramp: \(bad.count) of \(checked) blocks have flat or falling load")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) blocks do not ramp, first: \(bad.prefix(3))")
    }

    // MARK: - 6. Weekly push floor (finding 11)

    private func weeklySets(_ w: Week, patterns: Set<String>) -> Int {
        var total = 0
        for g in w.plan.days.compactMap({ $0.kind == .lift ? $0.generatedWorkout : nil }) {
            for e in g.exercises where e.exerciseId > 0 {
                if !Set(CoachDatabase.shared.patternsForExercise(e.exerciseId)).isDisjoint(with: patterns) {
                    total += e.sets
                }
            }
        }
        return total
    }

    /// Holds: `SessionMix.pushFloor` spreads 6 push sets over the week (180 of
    /// 450 ski weeks were under it on a19732e).
    func test_skiWeeksWithTwoLiftDaysHaveAPushFloor() {
        var checked = 0
        var bad: [String] = []
        for w in weeks() where w.cell.sport == "alpine-skiing" && w.cell.equipName != "bw" {
            let liftDays = w.plan.days.filter { $0.kind == .lift }.count
            guard liftDays >= 2 else { continue }
            checked += 1
            let push = weeklySets(w, patterns: ["horizontal-push", "vertical-push"])
            if push < 6 { bad.append("[\(w.cell)] push sets \(push) over \(liftDays) lift days") }
        }
        XCTAssertGreaterThan(checked, 300, "only \(checked) ski weeks checked")
        print("[GWI] push-floor: \(bad.count) of \(checked) ski weeks under 6 push sets")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) ski weeks under 6 push sets, first: \(bad.prefix(3))")
    }

    /// Holds: a climber's pressing complement day sets its presses against
    /// the rest of the week (272 of 360 weeks were outside the band on
    /// a19732e).
    func test_climbingPushPullRatioIsBalanced() {
        var checked = 0
        var bad: [String] = []
        // In-season and maintenance are out of scope. The wall carries the
        // pulling then, which lift sets do not count, and the authored
        // in-season sessions are antagonist pressing by design. Meeting 1:1
        // on lift sets alone means rows on a complement day, and the day
        // before a climbing session that costs the session its back and
        // arms to the recovery gate (RecoveryWeekProbeTests).
        for w in weeks() where w.cell.sport == "climbing" && w.cell.equipName != "bw"
            && w.cell.season != .inSeason && w.cell.season != .maintenance {
            let liftDays = w.plan.days.filter { $0.kind == .lift }.count
            guard liftDays >= 3 else { continue }
            let push = weeklySets(w, patterns: ["horizontal-push", "vertical-push"])
            let pull = weeklySets(w, patterns: ["horizontal-pull", "vertical-pull", "climbing-pull"])
            guard pull > 0 else { continue }
            checked += 1
            let r = Double(push) / Double(pull)
            if r < 0.5 || r > 1.0 {
                bad.append("[\(w.cell)] push \(push) : pull \(pull) = \(String(format: "%.2f", r))")
            }
        }
        XCTAssertGreaterThan(checked, 180, "only \(checked) climbing weeks checked")
        print("[GWI] push-pull: \(bad.count) of \(checked) climbing weeks outside 1:2 to 1:1")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) weeks outside 1:2 to 1:1, first: \(bad.prefix(3))")
    }

    // MARK: - Custom exercises stay out of generated weeks

    /// Custom exercises live in user.db and surface only through the picker
    /// and ExerciseLookupCache. The generator reaches that cache (prescription
    /// keys through `ExerciseKey`), so the test points the cache at a store
    /// full of custom exercises, gives them positive affinities the way swaps
    /// would, and checks no generated week ever carries one. No user-built
    /// routines: those are the user's own program and are served as written.
    func test_customExercisesNeverAppearInGeneratedWeeks() throws {
        try XCTSkipUnless(CoachDatabase.shared.isOpen, "coach.db not bundled")
        let userDB = UserDatabase(path: ":memory:")
        let rows: [(String, MuscleBucket?)] = [
            ("Zorblax Quad Smash", .quads), ("Zorblax Back Builder", .back),
            ("Zorblax Chest Fly", .chest), ("Zorblax Core Thing", .core), ("Zorblax No Bucket", nil)]
        for (name, bucket) in rows {
            _ = try userDB.createUserExercise(name: name, muscleBucket: bucket, notes: nil).get()
        }
        let customNames = Set(userDB.listUserExercises().map { $0.name.lowercased() })
        XCTAssertEqual(customNames.count, rows.count)

        let saved = ExerciseLookupCache.shared.userDB
        ExerciseLookupCache.shared.userDB = userDB
        defer { ExerciseLookupCache.shared.userDB = saved }
        XCTAssertEqual(ExerciseLookupCache.shared.exercise(forName: "Zorblax Quad Smash")?.isCustom, true,
                       "fixture: the generator's lookup path can see the custom store")

        let sports = Sport.catalog.filter { SportCatalog.isPlannable($0.slug) }
        XCTAssertGreaterThan(sports.count, 5, "plannable sports: \(sports.map(\.slug))")
        let routines = CoachDatabase.shared.listRoutines()
        var cells = 0, exercises = 0
        var bad: [String] = []
        for sport in sports { for season in SeasonPhase.allCases {
            for exp in [ExperienceLevel.beginner, .advanced] {
                for (equipName, equip) in [("gym", [Equipment.fullGym]), ("bw", [Equipment.bodyweight])] {
                    let cell = Cell(sport: sport.slug, season: season, exp: exp, equipName: equipName,
                                    equip: equip, days: 4, minutes: 45, week: 1)
                    let week = plan(cell, routines: routines, affinities: customNames)
                    cells += 1
                    for day in week.plan.days {
                        for e in day.generatedWorkout?.exercises ?? [] {
                            exercises += 1
                            if e.exerciseId < 0 || customNames.contains(e.name.lowercased()) {
                                bad.append("[\(cell)] \(day.kind) \(e.name) id \(e.exerciseId)")
                            }
                        }
                    }
                }
            }
        } }
        XCTAssertGreaterThan(exercises, cells, "the grid generated almost nothing")
        XCTAssertTrue(bad.isEmpty, "\(bad.count) custom rows in generated weeks, first: \(bad.prefix(3))")

        // CoachDatabase, which every generator pool reads, stays catalog-only.
        XCTAssertNil(CoachDatabase.shared.exercise(id: -1))
        for name in customNames {
            XCTAssertTrue(CoachDatabase.shared.searchExercises(search: name).exercises
                .allSatisfy { !$0.isCustom && $0.name.lowercased() != name }, name)
        }
    }
}
