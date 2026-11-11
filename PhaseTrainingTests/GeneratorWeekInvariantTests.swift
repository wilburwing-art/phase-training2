import XCTest
@testable import PhaseTraining

/// Phase 2 of docs/PLAN-gap-backlog-2026-11b.md. Whole-week properties from
/// audits/2026-11-10-gap-round/generator.md (findings 4, 5, 6, 8, 9, 11),
/// driven through `Planner.generate`, the same path the app takes. Every
/// failure message names the grid cell. Strict `XCTExpectFailure` wrappers
/// mark properties the generator does not meet yet; when Phase 3 fixes one,
/// the test reports "unexpectedly passed" and the wrapper must come out.
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

    static let sports = ["alpine-skiing", "ski-mountaineering", "climbing"]
    static let equipTiers: [(String, [Equipment])] = [
        ("bw", [.bodyweight]), ("homebar", [.dumbbells, .pullUpBar, .bands]), ("gym", [.fullGym])]

    static var weekGrid: [Cell] {
        var out: [Cell] = []
        for s in sports { for p in SeasonPhase.allCases { for e in ExperienceLevel.allCases {
            for eq in equipTiers { for d in 2...6 { for m in [30, 45, 75] {
                out.append(Cell(sport: s, season: p, exp: e, equipName: eq.0, equip: eq.1,
                                days: d, minutes: m, week: 1))
            } } }
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

    private func plan(_ c: Cell, routines: [BundledRoutineRow]) -> Week {
        var m = TrainingMemory()
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
        var cal = Calendar.current; cal.firstWeekday = 2
        var comps = DateComponents(); comps.year = 2026; comps.month = 11; comps.day = 9
        let monday = cal.date(from: comps)!
        return Week(cell: c, plan: Planner.generate(memory: m, routines: routines, today: monday))
    }

    private static var cache: [Week]?
    private static var blockCache: [Week]?

    private func weeks() -> [Week] {
        if let c = Self.cache { return c }
        let routines = CoachDatabase.shared.listRoutines()
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

    /// Fails in 4383 of 6588 sessions on a19732e (grid below).
    func test_sessionLengthTracksBudget() {
        var checked = 0
        var bad: [String] = []
        for w in weeks() {
            for g in engineSessions(w) {
                checked += 1
                let b = Double(w.cell.minutes)
                if Double(g.estimatedMinutes) > b + 5 || Double(g.estimatedMinutes) < 0.6 * b {
                    bad.append("[\(w.cell)] est=\(g.estimatedMinutes) budget=\(w.cell.minutes) '\(g.title)'")
                }
            }
        }
        XCTAssertGreaterThan(checked, 2000, "only \(checked) engine sessions checked")
        print("[GWI] session-length: \(bad.count) of \(checked) sessions out of band")
        XCTExpectFailure("Phase 3 item: session minutes calibration (finding 4)") {
            XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) sessions out of band, first: \(bad.prefix(3))")
        }
    }

    // MARK: - 2. Rest day (finding 8)

    /// Fails in 621 of 2025 weeks on a19732e (grid below).
    func test_everyWeekHasARestDay() {
        var bad: [String] = []
        let all = weeks()
        for w in all where !w.plan.days.contains(where: { $0.kind == .rest }) {
            bad.append("[\(w.cell)] pattern \(w.plan.days.map { String($0.kind.rawValue.first!) }.joined())")
        }
        XCTAssertGreaterThan(all.count, 2000, "only \(all.count) weeks checked")
        XCTAssertTrue(all.contains { $0.cell.days >= 5 }, "no 5 or 6 day cells in the grid")
        print("[GWI] rest-day: \(bad.count) of \(all.count) weeks have no rest day")
        XCTExpectFailure("Phase 3 item: reserve a rest day for 5 and 6 lift days (finding 8)") {
            XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(all.count) weeks have no rest day, first: \(bad.prefix(3))")
        }
    }

    // MARK: - 3. Exercise order (finding 5)

    /// Fails in 1808 violations over 6588 sessions on a19732e (grid below).
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
                // earliest on a tie. It must sit in the first two slots.
                let cands = rows.enumerated().filter {
                    $0.element.isCompound && !isExplosive($0.element)
                        && (rpeRange($0.element.rpe)?.0 ?? 0) >= 7 && repsLow($0.element) != nil
                }
                if w.cell.equipName != "bw", let minReps = cands.compactMap({ repsLow($0.element) }).min(),
                   let first = cands.first(where: { repsLow($0.element) == minReps }), first.offset > 1 {
                    bad.append("[\(w.cell)] heaviest compound '\(first.element.name)' in slot \(first.offset + 1)")
                }
            }
        }
        XCTAssertGreaterThan(checked, 2000, "only \(checked) engine sessions checked")
        print("[GWI] order: \(bad.count) violations over \(checked) sessions")
        XCTExpectFailure("Phase 3 item: training-order sort in the season engine (finding 5)") {
            XCTAssertTrue(bad.isEmpty, "\(bad.count) order violations over \(checked) sessions, first: \(bad.prefix(3))")
        }
    }

    // MARK: - 4. Loadable strength slots (finding 6)

    /// Fails in 268 of 2072 heavy gym slots on a19732e (grid below).
    func test_gymStrengthSlotsAreLoadable() {
        let regressions: Set<String> = ["Push-Up", "Push Up (Knees)", "Chest Press (Band)",
                                        "Glute Bridge", "Lunge (Bodyweight)", "Squat (Bodyweight)"]
        var checked = 0
        var bad: [String] = []
        for w in weeks() where w.cell.equipName == "gym" && w.cell.exp != .beginner {
            for g in engineSessions(w) {
                for e in g.exercises where e.sets >= 3 {
                    guard let r = rpeRange(e.rpe), r.0 >= 7, r.1 <= 8, !isExplosive(e) else { continue }
                    checked += 1
                    if regressions.contains(e.name) {
                        bad.append("[\(w.cell)] '\(e.name)' \(e.sets)x\(e.reps) RPE \(e.rpe ?? "")")
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000, "only \(checked) heavy slots checked")
        print("[GWI] loadable: \(bad.count) of \(checked) heavy gym slots are regressions")
        XCTExpectFailure("Phase 3 item: loadability ranking for strength demands (finding 6)") {
            XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) heavy slots are bodyweight or band regressions, first: \(bad.prefix(3))")
        }
    }

    // MARK: - 5. In-block progression (finding 9)

    private func anchors(_ w: Week) -> [Int] {
        // First RPE 7+ non-explosive compound per engine session, in day order.
        engineSessions(w).compactMap { g in
            g.exercises.first { $0.isCompound && !isExplosive($0) && (rpeRange($0.rpe)?.0 ?? 0) >= 7 }?.exerciseId
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

    /// Fails in 18 of 18 blocks on a19732e (grid below).
    func test_anchorLiftStaysTheSameAcrossWeeks1to3() {
        var checked = 0
        var bad: [String] = []
        for g in blockGroups() {
            guard g.count == 3 else { continue }
            let a = g.map(anchors)
            guard a.allSatisfy({ !$0.isEmpty }) else { continue }
            checked += 1
            if !(a[0] == a[1] && a[1] == a[2]) {
                bad.append("[\(g[0].cell.sport)/\(g[0].cell.exp.rawValue)/\(g[0].cell.days)lift] anchors by week \(a)")
            }
        }
        XCTAssertGreaterThan(checked, 10, "only \(checked) blocks checked")
        print("[GWI] anchor: \(bad.count) of \(checked) blocks change anchor lift")
        XCTExpectFailure("Phase 3 item: fixed anchor lifts across a block (finding 9)") {
            XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) blocks change anchor, first: \(bad.prefix(3))")
        }
    }

    /// Fails in 18 of 18 blocks on a19732e (grid below).
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
        XCTExpectFailure("Phase 3 item: per-week ramp in SetScheme.modulated (finding 9)") {
            XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) blocks do not ramp, first: \(bad.prefix(3))")
        }
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

    /// Fails in 180 of 450 ski weeks on a19732e (grid below).
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
        XCTExpectFailure("Phase 3 item: weekly push floor (finding 11)") {
            XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) ski weeks under 6 push sets, first: \(bad.prefix(3))")
        }
    }

    /// Fails in 272 of 360 climbing weeks on a19732e (grid below).
    func test_climbingPushPullRatioIsBalanced() {
        var checked = 0
        var bad: [String] = []
        for w in weeks() where w.cell.sport == "climbing" && w.cell.equipName != "bw" {
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
        XCTAssertGreaterThan(checked, 300, "only \(checked) climbing weeks checked")
        print("[GWI] push-pull: \(bad.count) of \(checked) climbing weeks outside 1:2 to 1:1")
        XCTExpectFailure("Phase 3 item: weekly push:pull balance (finding 11)") {
            XCTAssertTrue(bad.isEmpty, "\(bad.count) of \(checked) weeks outside 1:2 to 1:1, first: \(bad.prefix(3))")
        }
    }
}
