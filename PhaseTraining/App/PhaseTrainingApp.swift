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

    /// UI tests pass `--ui-test-reset` to start from a clean slate (wipes
    /// session + memory + plan + overrides UserDefaults keys on launch).
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset") {
            for key in ["pt_active_session", "pt_sessions",
                        "pt_training_memory",
                        "pt_week_plan", "pt_week_overrides",
                        "pt_weekly_reminder_enabled",
                        "pt_custom_routines",
                        "pt_recent_exercise_picks",
                        "pt_sport_logs"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        // Debug-only screenshot seed: drop a 5-exercise active session with two
        // supersets (A1/A2, B1/B2) plus a solo so the live LogScreen shows the
        // band + label rendering at runtime. Launched via:
        //   `--seed-supersets-demo`
        // Demo data is written to a separate UserDefaults suite so it never
        // pollutes the user's real state.
        if ProcessInfo.processInfo.arguments.contains("--seed-supersets-demo") {
            Self.seedSupersetsDemo()
        }
        // UITest seed: drop a deterministic WeekPlan whose TODAY is a lift day
        // carrying a 5-exercise `generatedWorkout`, so TodayScreen resolves the
        // planned-user branch instead of the upper-1 no-plan fallback. Lets the
        // tap-budget suite measure the start→log→save path for a real plan.
        // Launched via `--seed-plan-demo`; pair with `--ui-test-onboarded` +
        // `--ui-test-reset`.
        if ProcessInfo.processInfo.arguments.contains("--seed-plan-demo") {
            Self.seedPlanDemo()
        }
        // UITest seed: a WeekPlan whose TODAY is a SPORT day, so TodayScreen
        // shows the `today-log-sport` CTA (instead of a lift's start button).
        // Lets the tap-budget suite measure the log-a-sport-session path.
        // Launched via `--seed-sport-demo`; pair with `--ui-test-onboarded` +
        // `--ui-test-reset`. Same auto-regen safety as seedPlanDemo.
        if ProcessInfo.processInfo.arguments.contains("--seed-sport-demo") {
            Self.seedSportDemo()
        }
        // Upsize URLCache so coach.db image bytes survive across app launches.
        // The catalog serves ~555 images from raw.githubusercontent.com; the
        // default 4 MB memory + 20 MB disk evicts them almost immediately.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        WeeklyReminderScheduler.registerDelegate()
    }

    /// Debug-only: write a 5-exercise supersetted ActiveSession into
    /// UserDefaults so the live LogScreen shows the band + A1/A2/B1/B2
    /// labels. Mirrors the encoder config in SessionStore so the on-disk
    /// shape matches. Pair with `--ui-test-onboarded` to skip the welcome
    /// gate so the active-session bar surfaces immediately on launch.
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

    /// UITest-only: write a deterministic WeekPlan into UserDefaults whose
    /// TODAY (startOfDay) is a lift day carrying a 5-exercise `generatedWorkout`.
    /// TodayScreen's `template` then resolves the `todayPlan?.generatedWorkout`
    /// branch — the path a *planned* user takes — rather than the upper-1
    /// fallback that only fires when `planStore.plan == nil`. Mirrors the
    /// secondsSince1970 encoding PlanStore decodes with.
    ///
    /// Safe against clobber: PlanStore's auto-regen subscription is gated on
    /// `memory.onboardedAt != nil`, which is nil under `--ui-test-reset`, so
    /// the seeded plan is never regenerated on launch. `--ui-test-reset` clears
    /// `pt_week_plan` in `init()` before this runs, so the seed lands last.
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

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let days: [DayPlan] = (0..<7).map { i in
            DayPlan(
                date: cal.date(byAdding: .day, value: i, to: start) ?? start,
                kind: i == 0 ? .lift : .rest,
                title: i == 0 ? "Push day" : "Rest",
                generatedWorkout: i == 0 ? workout : nil,
                generatedReason: "UITest seed"
            )
        }
        let plan = WeekPlan(days: days, generatedAt: Date(), inputsHash: "ui-test-seed")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(plan) {
            UserDefaults.standard.set(data, forKey: "pt_week_plan")
        }
    }

    /// UITest-only: write a WeekPlan whose TODAY is a `.sport` day with a Sport
    /// attached, so TodayScreen renders the `today-log-sport` CTA. Mirrors
    /// seedPlanDemo's encoding + auto-regen safety. SportLogSheet defaults to
    /// 60 min / moderate, so the minimal log path is open + save (2 taps).
    private static func seedSportDemo() {
        guard let sport = Sport.catalog.first(where: { $0.slug == "climbing" })
                ?? Sport.catalog.first else { return }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let days: [DayPlan] = (0..<7).map { i in
            DayPlan(
                date: cal.date(byAdding: .day, value: i, to: start) ?? start,
                kind: i == 0 ? .sport : .rest,
                title: i == 0 ? sport.name : "Rest",
                sport: i == 0 ? sport : nil,
                generatedReason: "UITest seed"
            )
        }
        let plan = WeekPlan(days: days, generatedAt: Date(), inputsHash: "ui-test-seed")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(plan) {
            UserDefaults.standard.set(data, forKey: "pt_week_plan")
        }
    }

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
                .task {
                    // Sync products + entitlement state once on launch.
                    // Cheap and safe to call on every cold start.
                    await subscriptions.refresh()
                }
                .task {
                    // UITest hook: deterministically present the weekly check-in
                    // on launch so the tap-budget suite can measure that flow.
                    if ProcessInfo.processInfo.arguments.contains("--ui-test-open-weekly-checkin") {
                        tabSelection.showWeeklyCheckIn = true
                    }
                }
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
                        InsightGenerator.runIfDue(
                            memoryStore: memory,
                            planStore: plan,
                            sessionStore: session,
                            consentGranted: coachConsentGranted
                        )
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
                    default: break
                    }
                }
        }
    }
}
