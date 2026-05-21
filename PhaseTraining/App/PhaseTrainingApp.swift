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

    /// UI tests pass `--ui-test-onboarded` to skip the first-launch onboarding cover
    /// without persisting state to UserDefaults.
    private let uiTestSkipsOnboarding = ProcessInfo.processInfo.arguments.contains("--ui-test-onboarded")

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
