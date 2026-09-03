import SwiftUI

@main
struct PhaseTrainingApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CoachConsent.storageKey) private var coachConsentGranted: Bool = false

    @StateObject private var session = SessionStore()
    @StateObject private var memory  = MemoryStore()
    @StateObject private var plan    = PlanStore()
    @StateObject private var custom  = CustomRoutineStore()
    @StateObject private var recentPicks = RecentPicksStore()
    @StateObject private var tabSelection = TabSelectionStore()
    @StateObject private var conv = CoachConversationStore()
    @StateObject private var sportLog = SportLogStore()
    @StateObject private var subscriptions = SubscriptionStore()
    @StateObject private var activityDetection = ActivityDetectionStore()

    /// UI tests pass `--ui-test-onboarded` to skip the first-launch onboarding cover
    /// without persisting state to UserDefaults.
    private let uiTestSkipsOnboarding = ProcessInfo.processInfo.arguments.contains("--ui-test-onboarded")

    #if DEBUG
    /// DEBUG-only: when `--regenerate-muscle-chips` is passed, present the
    /// MuscleChipGeneratorView on launch with `autoRunOnAppear: true` so a
    /// single simctl launch + ~5s pause completes the entire generation
    /// cycle. Pair with `--ui-test-onboarded` to skip the welcome gate.
    @State private var autoRegenerateChips: Bool = ProcessInfo.processInfo.arguments.contains("--regenerate-muscle-chips")
    #endif

    /// UI tests pass `--ui-test-reset` to start from a clean slate. Routes
    /// through `MemoryStore.wipeAllUserData()` (UserDefaults + SQLite) on launch
    /// so it matches the production "Erase all my data" path exactly.
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset") {
            // Same canonical wipe the production "Erase all my data" action
            // uses, so the two can't drift. Unlike the old inline key list,
            // this also clears the SQLite store — a hand-kept list missed it,
            // so UI tests could inherit saved sessions/routines from a prior run.
            MemoryStore.wipeAllUserData()
        }
        // UITest seeds, DEBUG-only so they can't ship in a release binary and
        // overwrite a real user's plan:
        //   --seed-supersets-demo → a 5-exercise active session with two
        //     supersets (A1/A2, B1/B2) plus a solo, so the live LogScreen shows
        //     the band + A1/A2/B1/B2 label rendering at runtime. Writes the REAL
        //     `pt_active_session` key in `.standard` (not a separate suite —
        //     LogScreen reads SessionStore, which only looks there), so it must
        //     stay inside this DEBUG block. Pair with --ui-test-reset.
        //   --seed-plan-demo  → TODAY is a lift day with a 5-exercise
        //     generatedWorkout (TodayScreen resolves the planned-user branch,
        //     not the upper-1 fallback) — the start→log→save path.
        //   --seed-sport-demo → TODAY is a SPORT day (today-log-sport CTA) —
        //     the log-a-sport-session path.
        // Both pair with --ui-test-onboarded + --ui-test-reset; the latter
        // clears pt_week_plan first so the seed lands last. Auto-regen is gated
        // on memory.onboardedAt (nil under reset), so the seed isn't clobbered.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--seed-supersets-demo") {
            Self.seedSupersetsDemo()
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-plan-demo") {
            Self.seedPlanDemo()
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-sport-demo") {
            Self.seedSportDemo()
        }
        //   --seed-saved-workouts → three CustomRoutines, so Today's title
        //     wheel has somewhere to scroll TO. Without saved workouts the
        //     wheel has one stop and is deliberately not rendered, so this is
        //     required to exercise it at all. Pair with --seed-plan-demo.
        if ProcessInfo.processInfo.arguments.contains("--seed-saved-workouts") {
            Self.seedSavedWorkouts()
        }
        //   --seed-snow-sport-demo → TODAY is a SNOWBOARDING sport day, so the
        //     sport-matched Kettle loop (KettlePose.forSport) shows him carving.
        if ProcessInfo.processInfo.arguments.contains("--seed-snow-sport-demo") {
            Self.seedSnowSportDemo()
        }
        //   --seed-rest-day-demo → TODAY is a REST day, so the stretch Kettle shows.
        if ProcessInfo.processInfo.arguments.contains("--seed-rest-day-demo") {
            Self.seedRestDayDemo()
        }
        //   --seed-missed-consolidation-demo → a PAST missed push day in a
        //     week-full plan (4 lifts → reshuffle drop-rule fires), with
        //     focus-tagged future lifts, so TodayScreen's missed-workout banner
        //     offers "Consolidate" (D3). Drives the consolidate flow.
        if ProcessInfo.processInfo.arguments.contains("--seed-missed-consolidation-demo") {
            Self.seedMissedConsolidationDemo()
        }
        //   --seed-support-demo → ski-primary + climbing-support (Tue medium,
        //     Sat big) with a plan that has climbing .sport days on those
        //     weekdays, so the Week tab renders the SupportBadge. Pair with
        //     --ui-test-onboarded --ui-test-reset.
        if ProcessInfo.processInfo.arguments.contains("--seed-support-demo") {
            Self.seedSupportDemo()
        }
        //   --seed-ski-primary → ski-primary, no support pattern; the Profile
        //     "Support sport" row appears and its editor opens empty.
        if ProcessInfo.processInfo.arguments.contains("--seed-ski-primary") {
            Self.seedSkiPrimary()
        }
        #endif
        // Upsize URLCache so coach.db image bytes survive across app launches.
        // The catalog serves ~555 images from raw.githubusercontent.com; the
        // default 4 MB memory + 20 MB disk evicts them almost immediately.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        WeeklyReminderScheduler.registerDelegate()
    }

    #if DEBUG
    /// Debug-only: write a 5-exercise supersetted ActiveSession into
    /// UserDefaults so the live LogScreen shows the band + A1/A2/B1/B2
    /// labels. Mirrors the encoder config in SessionStore so the on-disk
    /// shape matches. Pair with `--ui-test-onboarded` to skip the welcome
    /// gate so the active-session bar surfaces immediately on launch.
    ///
    /// Writes the REAL `pt_active_session` key in `.standard` — SessionStore
    /// reads only there, so a separate suite would make the seed invisible.
    /// That is exactly why this is DEBUG-gated: in a release binary it would
    /// overwrite a user's in-flight workout.
    private static func seedSupersetsDemo() {
        let session = ActiveSession(
            templateId: "demo-supersets",
            name: "Upper · superset demo",
            category: "Demo",
            startTime: Date().addingTimeInterval(-12 * 60),
            exercises: [
                LoggedExercise(
                    id: "bench", name: "Bench Press", type: "Barbell", unit: "lbs",
                    targetSets: 3, targetReps: 8, rest: 90,
                    sets: [
                        LoggedSet(num: 1, weight: "135", reps: "8", rpe: "7", done: true),
                        LoggedSet(num: 2, weight: "135", reps: "8", rpe: "", done: false),
                        LoggedSet(num: 3, weight: "135", reps: "8", rpe: "", done: false),
                    ],
                    prevSets: [],
                    supersetGroup: 1
                ),
                LoggedExercise(
                    id: "row", name: "DB Row", type: "Dumbbell", unit: "lbs",
                    targetSets: 3, targetReps: 10, rest: 90,
                    sets: [
                        LoggedSet(num: 1, weight: "55", reps: "10", rpe: "7", done: true),
                        LoggedSet(num: 2, weight: "55", reps: "10", rpe: "", done: false),
                        LoggedSet(num: 3, weight: "55", reps: "10", rpe: "", done: false),
                    ],
                    prevSets: [],
                    supersetGroup: 1
                ),
                LoggedExercise(
                    id: "squat", name: "Back Squat", type: "Barbell", unit: "lbs",
                    targetSets: 3, targetReps: 5, rest: 180,
                    sets: [
                        LoggedSet(num: 1, weight: "225", reps: "5", rpe: "8", done: false),
                        LoggedSet(num: 2, weight: "225", reps: "5", rpe: "", done: false),
                        LoggedSet(num: 3, weight: "225", reps: "5", rpe: "", done: false),
                    ],
                    prevSets: [],
                    supersetGroup: nil
                ),
                LoggedExercise(
                    id: "curl", name: "Cable Curl", type: "Cable", unit: "lbs",
                    targetSets: 3, targetReps: 12, rest: 60,
                    sets: [
                        LoggedSet(num: 1, weight: "40", reps: "12", rpe: "", done: false),
                        LoggedSet(num: 2, weight: "40", reps: "12", rpe: "", done: false),
                        LoggedSet(num: 3, weight: "40", reps: "12", rpe: "", done: false),
                    ],
                    prevSets: [],
                    supersetGroup: 2
                ),
                LoggedExercise(
                    id: "pushdown", name: "Tricep Pushdown", type: "Cable", unit: "lbs",
                    targetSets: 3, targetReps: 12, rest: 60,
                    sets: [
                        LoggedSet(num: 1, weight: "50", reps: "12", rpe: "", done: false),
                        LoggedSet(num: 2, weight: "50", reps: "12", rpe: "", done: false),
                        LoggedSet(num: 3, weight: "50", reps: "12", rpe: "", done: false),
                    ],
                    prevSets: [],
                    supersetGroup: 2
                ),
            ],
            feel: nil,
            note: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(session) {
            UserDefaults.standard.set(data, forKey: "pt_active_session")
        }
    }

    /// UITest-only: write a deterministic 7-day WeekPlan to `pt_week_plan` where
    /// `day(date)` builds each day, encoded with `.secondsSince1970` to match
    /// `PlanStore.decoder()`. Shared by the --seed-*-demo hooks.
    ///
    /// EVERY day is built by `day(_:)` (same kind), not just today, so a midnight
    /// rollover between `init()` (which stamps these dates) and the first Today
    /// render (which re-resolves "today" via `startOfDay(now)`) can't land
    /// "today" on a different day kind and make the seeded CTA vanish.
    ///
    /// Safe against clobber: PlanStore's auto-regen is gated on
    /// `memory.onboardedAt` (nil under --ui-test-reset), and --ui-test-reset
    /// clears `pt_week_plan` in `init()` before this runs.
    private static func seedWeekPlan(day: (Date) -> DayPlan) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let days: [DayPlan] = (0..<7).map { i in
            day(cal.date(byAdding: .day, value: i, to: start) ?? start)
        }
        let plan = WeekPlan(days: days, generatedAt: Date(), inputsHash: "ui-test-seed")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(plan) {
            UserDefaults.standard.set(data, forKey: "pt_week_plan")
        }
    }

    /// --seed-plan-demo: TODAY is a lift day carrying a 5-exercise
    /// generatedWorkout, so TodayScreen resolves the planned-user branch rather
    /// than the upper-1 fallback (which only fires when `planStore.plan == nil`).
    /// --seed-saved-workouts: three saved routines for the Today title wheel.
    /// Real exercise ids so the rows resolve photos and muscle buckets like
    /// any other workout.
    private static func seedSavedWorkouts() {
        let store = CustomRoutineStore()
        let specs: [(String, [(Int, String)])] = [
            ("Quick Push",  [(900, "Bench Press"), (904, "Overhead Press"), (953, "Tricep Pushdown")]),
            ("Pull Day",    [(922, "Pull Up"), (1028, "Incline Row"), (546, "Lateral Raise")]),
            ("Legs, Short", [(544, "Skullcrusher"), (24, "Face Pull")]),
        ]
        for (offset, spec) in specs.enumerated() {
            let exercises = spec.1.enumerated().map { i, ex in
                CustomRoutineExercise(id: UUID().uuidString, exerciseId: ex.0, name: ex.1,
                                      position: i, sets: 3, reps: "8", rest: "90", notes: nil)
            }
            store.save(CustomRoutine(id: "seed-routine-\(offset)",
                                     name: spec.0,
                                     exercises: exercises,
                                     createdAt: Date().addingTimeInterval(Double(-offset) * 60)))
        }
    }

    private static func seedPlanDemo() {
        let workout = GeneratedWorkout(
            title: "Push day",
            summary: "5 movements · ~50 min",
            exercises: [
                GeneratedExercise(id: "seed-1", exerciseId: 1, name: "Bench Press",
                                  pattern: "horizontal-press", isCompound: true,
                                  sets: 4, reps: "5", restSeconds: 150, rpe: "8"),
                GeneratedExercise(id: "seed-2", exerciseId: 2, name: "Overhead Press",
                                  pattern: "vertical-press", isCompound: true,
                                  sets: 3, reps: "8", restSeconds: 120, rpe: "8"),
                GeneratedExercise(id: "seed-3", exerciseId: 3, name: "Incline DB Press",
                                  pattern: "horizontal-press", isCompound: true,
                                  sets: 3, reps: "10", restSeconds: 90),
                GeneratedExercise(id: "seed-4", exerciseId: 4, name: "Lateral Raise",
                                  pattern: "lateral-raise", isCompound: false,
                                  sets: 3, reps: "15", restSeconds: 60),
                GeneratedExercise(id: "seed-5", exerciseId: 5, name: "Tricep Pushdown",
                                  pattern: "elbow-extension", isCompound: false,
                                  sets: 3, reps: "12", restSeconds: 60),
            ],
            estimatedMinutes: 50,
            provenance: "UITest seed · push/pull/legs day 1"
        )
        seedWeekPlan { date in
            DayPlan(date: date, kind: .lift, title: "Push day",
                    generatedWorkout: workout, generatedReason: "UITest seed")
        }
    }

    /// --seed-sport-demo: TODAY is a `.sport` day with a Sport attached, so
    /// TodayScreen renders the `today-log-sport` CTA. SportLogSheet defaults to
    /// 60 min / moderate, so the minimal log path is open + save (2 taps).
    private static func seedSportDemo() {
        guard let sport = Sport.catalog.first(where: { $0.slug == "climbing" })
                ?? Sport.catalog.first else { return }
        seedWeekPlan { date in
            DayPlan(date: date, kind: .sport, title: sport.name,
                    sport: sport, generatedReason: "UITest seed")
        }
    }

    private static func seedSnowSportDemo() {
        guard let sport = Sport.catalog.first(where: { $0.slug == "snowboarding" })
                ?? Sport.catalog.first else { return }
        seedWeekPlan { date in
            DayPlan(date: date, kind: .sport, title: sport.name,
                    sport: sport, generatedReason: "UITest seed")
        }
    }

    private static func seedRestDayDemo() {
        seedWeekPlan { date in
            DayPlan(date: date, kind: .rest, title: "Rest", generatedReason: "UITest seed")
        }
    }

    /// UITest-only: a ski-primary TrainingMemory (off-season), the base for the
    /// support seeds. Shared so the Profile-row gate (ski/snow primary) is met.
    private static func skiPrimaryMemory() -> TrainingMemory? {
        guard let ski = Sport.catalog.first(where: { $0.slug == "alpine-skiing" }) else { return nil }
        var m = TrainingMemory()
        m.sports = [ski]
        m.primarySport = ski
        m.seasonsBySport = [ski: .offSeason]
        m.defaultSeason = .offSeason
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        m.age = 33   // → redditFitness derived era, so the era step has a row
        return m
    }

    /// Write memory directly (key + encoder mirror MemoryStore), leaving
    /// `onboardedAt` nil so PlanStore's auto-regen stays gated off.
    private static func writeSeedMemory(_ m: TrainingMemory) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(m) {
            UserDefaults.standard.set(data, forKey: "pt_training_memory")
        }
    }

    /// --seed-ski-primary: ski-primary memory with NO support pattern, so the
    /// Profile "Support sport" row appears (gated to ski/snow) and its editor
    /// opens empty. Used by the editor UI test.
    private static func seedSkiPrimary() {
        guard let m = skiPrimaryMemory() else { return }
        writeSeedMemory(m)
    }

    /// --seed-support-demo: ski-primary + a climbing support pattern (Tue
    /// medium, Sat big) + a plan whose Tue/Sat are climbing `.sport` days, so
    /// the Week tab renders the SupportBadge.
    private static func seedSupportDemo() {
        guard var m = skiPrimaryMemory(),
              let climbing = Sport.catalog.first(where: { $0.slug == "climbing" }) else { return }
        m.supportPattern = SupportPattern(
            sportSlug: "climbing", variant: .tradAlpine,
            days: [SupportDay(weekday: .tuesday, magnitude: .medium),
                   SupportDay(weekday: .saturday, magnitude: .big)])
        writeSeedMemory(m)
        // Real off-season ski sessions from the actual season engine so the
        // lift days carry real exercises (not empty stubs) — the demo then
        // shows both the support badges AND tappable workouts.
        let athlete = AthleteState.from(m, variant: .backcountry)
        seedWeekPlan { date in
            switch Weekday.from(date: date, calendar: .current) {
            case .tuesday:
                return DayPlan(date: date, kind: .sport, title: climbing.name,
                               sport: climbing, generatedReason: "You climb on Tue (medium)")
            case .saturday:
                return DayPlan(date: date, kind: .sport, title: climbing.name,
                               sport: climbing, generatedReason: "You climb on Sat (big)")
            case .monday, .thursday:
                let idx = Weekday.from(date: date, calendar: .current) == .monday ? 0 : 1
                let w = SportSeasonGenerator.generateSession(athlete, sessionIndex: idx)
                return DayPlan(date: date, kind: .lift, title: w.title,
                               generatedWorkout: w, generatedReason: "Primary build")
            default:
                return DayPlan(date: date, kind: .rest, title: "Rest")
            }
        }
    }

    /// --seed-missed-consolidation-demo: a week with a PAST missed push day
    /// (no logged session) and 4 total lift days, so the missed-workout
    /// reshuffle drop-rule fires (≥4 lifts → no clean slot) and the banner
    /// offers "Consolidate" instead. The 3 future lift days carry a persisted
    /// `focus` so `consolidateWeek` can recover them and merge down to 2.
    private static func seedMissedConsolidationDemo() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func date(_ o: Int) -> Date { cal.date(byAdding: .day, value: o, to: today) ?? today }
        func lift(_ o: Int, _ focus: WorkoutFocus) -> DayPlan {
            DayPlan(date: date(o), kind: .lift, title: focus.title,
                    generatedWorkout: GeneratedWorkout(
                        title: focus.title, summary: "", exercises: [],
                        estimatedMinutes: 60, provenance: "seed", focus: focus),
                    generatedReason: "seed")
        }
        func rest(_ o: Int) -> DayPlan {
            DayPlan(date: date(o), kind: .rest, title: "Rest")
        }
        // 4 lift days (week-full) incl a past missed push; 3 future lifts w/ focus.
        let days = [lift(-2, .push), rest(-1), lift(0, .pull), rest(1),
                    lift(2, .legs), lift(3, .upper), rest(4)]
        let plan = WeekPlan(days: days, generatedAt: Date(), inputsHash: "ui-test-seed")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(plan) {
            UserDefaults.standard.set(data, forKey: "pt_week_plan")
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(session)
                .environmentObject(memory)
                .environmentObject(plan)
                .environmentObject(custom)
                .environmentObject(recentPicks)
                .environmentObject(tabSelection)
                .environmentObject(conv)
                .environmentObject(sportLog)
                .environmentObject(subscriptions)
                .environmentObject(activityDetection)
                .task {
                    // Sync products + entitlement state once on launch.
                    // Cheap and safe to call on every cold start.
                    await subscriptions.refresh()
                }
                .task {
                    // Ski/climb narrowing: route users on an unsupported / no
                    // sport back through onboarding to pick a supported one.
                    memory.migrateToSupportedSportGate()
                }
                #if DEBUG
                .task {
                    // UITest hook (DEBUG-only): deterministically present the
                    // weekly check-in on launch so the tap-budget suite can
                    // measure that flow.
                    if ProcessInfo.processInfo.arguments.contains("--ui-test-open-weekly-checkin") {
                        tabSelection.showWeeklyCheckIn = true
                    }
                }
                #endif
                .preferredColorScheme(.dark)
                .fullScreenCover(isPresented: .constant(!memory.isOnboarded && !uiTestSkipsOnboarding)) {
                    OnboardingFlow()
                        .environmentObject(memory)
                        .environmentObject(plan)
                        .preferredColorScheme(.dark)
                }
                .sheet(isPresented: $tabSelection.showWeeklyCheckIn) {
                    WeeklyCheckInFlow(onDismiss: { tabSelection.showWeeklyCheckIn = false })
                        .environmentObject(memory)
                        .environmentObject(plan)
                        .environmentObject(sportLog)
                        .presentationBackground(Color.bg)
                }
                #if DEBUG
                .sheet(isPresented: $autoRegenerateChips) {
                    MuscleChipGeneratorView(autoRunOnAppear: true)
                        .preferredColorScheme(.dark)
                }
                #endif
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            // Entitlement mirror first: runIfDue's pro gate
                            // reads the proKey default that refresh() writes,
                            // so a stale mirror would race the launch .task
                            // refresh. Latent while CoachEntitlement
                            // .proRequired is false; real once it flips.
                            await subscriptions.refresh()
                            InsightGenerator.runIfDue(
                                memoryStore: memory,
                                planStore: plan,
                                sessionStore: session,
                                consentGranted: coachConsentGranted
                            )
                        }
                        // On-open Health activity check ("looks like you
                        // went skiing yesterday" → Today banner). Covers
                        // cold launch too: scenePhase transitions to
                        // .active on first render. Silent when Health read
                        // access was never granted. Its own Task — the
                        // banner must not wait behind the StoreKit refresh
                        // above, which can take seconds on a bad connection.
                        if memory.isOnboarded {
                            Task {
                                await activityDetection.scan(sportLogs: sportLog.entries)
                            }
                        }
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "phasetraining" else { return }
                    switch url.host {
                    case "today":     tabSelection.selected = .today
                    case "week":      tabSelection.selected = .week
                    case "progress":  tabSelection.selected = .progress
                    case "profile":   tabSelection.selected = .profile
                    case "plan-week":
                        // Notification deep link: jump to Today and pop the
                        // interactive planning flow on top.
                        tabSelection.selected = .today
                        tabSelection.showWeeklyCheckIn = true
                    case "set-lift-days":
                        // D1 — Sunday-push day-count quick action. Set the
                        // weekly lift-day count (PlanStore auto-regenerates off
                        // the memory change) and show the result on the Week tab.
                        if let n = WeeklyReminderScheduler.liftDays(fromDeepLink: url) {
                            // Floor is 1, not liftDaysRange's 0, on purpose: a
                            // day-count quick action ("2 days"…"4 days") always
                            // implies at least one lift day — "no lifting this
                            // week" goes through "Open to edit" instead.
                            let clamped = max(1, min(TrainingConstraints.liftDaysRange.upperBound, n))
                            memory.update { $0.liftDaysPerWeek = clamped }
                            tabSelection.selected = .week
                        }
                    default: break
                    }
                }
        }
    }
}
