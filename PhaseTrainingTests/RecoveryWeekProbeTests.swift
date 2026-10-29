import XCTest
@testable import PhaseTraining

/// The recovery gate must not defeat the app's own week. Walk a generated
/// week day by day the way an athlete would: rebuild for recovery, then log
/// the day's workout exactly as prescribed. A sport session that loses its
/// sport's own muscles to what the week already logged means the model and
/// the SessionMix spacing disagree, and the model gets tuned.
///
/// Measured 2026-10-29 (21 weeks): no sport session lost a signature muscle.
/// Eight lost an accessory the day before's complement session trained
/// (a climbing session's push accessory after an upper push day, say),
/// which is the gate doing its job.
final class RecoveryWeekProbeTests: XCTestCase {

    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11; c.hour = 8
        return Calendar.current.date(from: c)!
    }

    private func memory(sport slug: String, season: SeasonPhase, lifts: Int) throws -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = lifts
        let sport = try XCTUnwrap(Sport.resolve(slug: slug))
        m.sports = [sport]
        m.primarySport = sport
        m.seasonsBySport = [sport: season]
        m.defaultSeason = season
        m.onboardedAt = monday()
        return m
    }

    private struct DayResult {
        let date: Date
        let title: String
        let sport: Bool
        let skipped: [String]
        let eased: [String]
    }

    /// Generate, then for each day: rebuild for recovery as of that morning,
    /// and log every prescribed set at 5pm.
    private func walkWeek(_ m: TrainingMemory) throws -> [DayResult] {
        let suite = "RecoveryWeekProbe.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let store = PlanStore(defaults: d, today: monday())
        let sessions = SessionStore(defaults: UserDefaults(suiteName: suite + ".s")!,
                                    userDB: UserDatabase(path: ":memory:"))
        store.sessionStore = sessions
        _ = store.generate(from: m, today: monday())
        let cal = Calendar.current
        var out: [DayResult] = []
        for day in try XCTUnwrap(store.plan?.days) where day.kind == .lift {
            let morning = cal.startOfDay(for: day.date).addingTimeInterval(7 * 3600)
            store.applyRecovery(memory: m, today: morning)
            let current = try XCTUnwrap(store.plan?.days.first { $0.id == day.id })
            let w = try XCTUnwrap(current.generatedWorkout)
            out.append(DayResult(date: day.date, title: w.title, sport: !current.isComplementSession,
                                 skipped: w.skippedAreas ?? [], eased: w.soreAreas ?? []))
            let start = cal.startOfDay(for: day.date).addingTimeInterval(17 * 3600)
            let logged = w.exercises.map { ex in
                LoggedExercise(id: ex.id, name: ex.name, type: nil, unit: "lbs",
                               targetSets: ex.sets, targetReps: 8, rest: ex.restSeconds,
                               sets: (1...max(1, ex.sets)).map {
                                   LoggedSet(num: $0, weight: "50", reps: "8", rpe: "", done: true)
                               },
                               prevSets: [])
            }
            sessions.savedSessions.insert(SavedSession(templateId: "t", name: w.title, category: "lift",
                                                       startTime: start, exercises: logged,
                                                       endTime: start.addingTimeInterval(3600), duration: 3600), at: 0)
        }
        return out
    }

    func test_sportSessionsAreNotBlockedByTheWeekItself() throws {
        let cases: [(String, SeasonPhase)] = [
            ("alpine-skiing", .offSeason), ("alpine-skiing", .preSeason), ("alpine-skiing", .inSeason),
            ("snowboarding", .preSeason),
            ("climbing", .offSeason), ("climbing", .preSeason), ("climbing", .inSeason),
        ]
        let f = DateFormatter()
        f.dateFormat = "EEE"
        var blockedSport: [String] = []
        for (slug, season) in cases {
            for lifts in [3, 5, 6] {
                let m = try memory(sport: slug, season: season, lifts: lifts)
                let days = try walkWeek(m)
                let line = days.map { r in
                    let tag = r.sport ? "S" : "c"
                    let notes = (r.skipped.isEmpty ? "" : " -" + r.skipped.joined(separator: "/"))
                        + (r.eased.isEmpty ? "" : " ~" + r.eased.joined(separator: "/"))
                    return "\(f.string(from: r.date)) \(tag)\(notes)"
                }.joined(separator: " | ")
                print("RECOVERY-PROBE \(slug) \(season) \(lifts)d: \(line)")
                let signature: Set<String> = SessionMix.family(forSport: slug) == .legsDominant
                    ? ["quads", "hamstrings", "glutes"] : ["back", "forearms", "biceps"]
                for r in days where r.sport && !signature.isDisjoint(with: r.skipped) {
                    blockedSport.append("\(slug) \(season) \(lifts)d \(f.string(from: r.date)): \(r.skipped)")
                }
            }
        }
        XCTAssertEqual(blockedSport, [], "sport sessions lost their own muscles to the week's logged work")
    }
}
