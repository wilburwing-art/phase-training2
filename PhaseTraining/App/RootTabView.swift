// RootTabView.swift — Phase 11 nav shell.
// 4 tabs: Today (live workout flow), Week (per-week planning + edits),
// Progress (Phase 12), Profile. The routine library lives behind sheets
// reachable from Today + Week — no longer a primary tab.
//
// Tab selection is held in TabSelectionStore (injected as an env object) so
// external triggers — currently the weekly reminder deep link via
// PhaseTrainingApp's .onOpenURL — can switch tabs.

import SwiftUI

enum AppTab: Hashable {
    case today, week, library, progress, profile
}

final class TabSelectionStore: ObservableObject {
    @Published var selected: AppTab = .today
    /// Drives the weekly check-in cover. Lives here (not on TodayScreen) so
    /// the notification deep link `phasetraining://plan-week` can open the
    /// flow regardless of which tab is active.
    @Published var showWeeklyCheckIn: Bool = false
}

struct RootTabView: View {
    @EnvironmentObject private var tabSelection: TabSelectionStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var memoryStore: MemoryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var recentPicks: RecentPicksStore
    @EnvironmentObject private var conv: CoachConversationStore
    @EnvironmentObject private var sportLogStore: SportLogStore
    @EnvironmentObject private var customStore: CustomRoutineStore

    /// Dismissed-for-this-launch flag for the storage warning, so an unopenable
    /// database doesn't re-alert on every tab switch.
    @State private var storageAlertDismissed = false

    /// The store either never opened / failed to migrate, or a finished workout
    /// didn't reach disk. Both mean "what you do here won't be there tomorrow".
    private var storageFailure: String? {
        if sessionStore.persistenceFailed {
            return "Your last workout couldn't be written to storage. It's still on screen, but it won't be here after you close the app."
        }
        if let reason = UserDatabase.shared.unavailableReason {
            return reason + " Your workouts and history can't be saved until this is fixed. Reinstalling the app usually clears it — restore a backup from Profile first if you have one."
        }
        return nil
    }

    private var showStorageAlert: Binding<Bool> {
        Binding(
            get: { storageFailure != nil && !storageAlertDismissed },
            set: { if !$0 { storageAlertDismissed = true } }
        )
    }

    private var storageAlertMessage: String { storageFailure ?? "" }

    var body: some View {
        TabView(selection: $tabSelection.selected) {
            TodayTab()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
                .tag(AppTab.today)

            WeekScreen()
                .tabItem { Label("Week", systemImage: "calendar") }
                .tag(AppTab.week)

            LibraryScreen()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)

            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)

            ProfileScreen()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Color.accent)
        .preferredColorScheme(.dark)
        // A dead database used to be completely silent: reads returned empty and
        // writes no-opped, so the app showed "no history" and still accepted
        // saves that never landed. Warn once, at the shell, before the user
        // trains on top of it.
        .alert("Your data isn't being saved",
               isPresented: showStorageAlert) {
            Button("OK", role: .cancel) { sessionStore.persistenceFailed = false }
        } message: {
            Text(storageAlertMessage)
        }
        .overlay(alignment: .bottomTrailing) {
            CoachBubble()
                .padding(.bottom, 56)  // clear the tab bar
                .allowsHitTesting(true)
                .animation(.easeInOut(duration: 0.2), value: tabSelection.selected)
        }
        .sheet(isPresented: $conv.presented) {
            CoachDrawer()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color.bg)
        }
        .task {
            // Wire variety memory + session history + memory feed into
            // PlanStore (kept off the init so the store stays one-arg
            // constructible for tests + previews).
            //
            // sessionStore drives the GeneratorContext (runtime-history).
            // memoryStore drives the auto-regen subscription — any profile
            // change that drifts planInputsHash silently rebuilds the week.
            planStore.recentPicks = recentPicks
            planStore.sessionStore = sessionStore
            planStore.memoryStore = memoryStore
            planStore.sportLogStore = sportLogStore
            planStore.customStore = customStore
            // These injected stores feed derived view state — e.g. the Today
            // missed-workout banner reads `sessionStore` via
            // `pendingMissedWorkouts()` — but none is individually @Published, so
            // wiring them here (in `.task`, AFTER first render) doesn't refresh
            // observers. Without this nudge the cold-launch missed banner never
            // appears until some unrelated @Published change forces a re-render
            // (caught by ConsolidateFlowTests). Notify once, deps now wired.
            planStore.objectWillChange.send()
            // One-shot migration for users whose saved plan was composed by
            // the pre-build-36 routine picker. Detects the stale schema and
            // regenerates so they stop seeing bundled sport-themed routines
            // (Basketball, Wakeboard, etc.) that have nothing to do with
            // their actual selections.
            guard memoryStore.isOnboarded else { return }
            planStore.migrateIfStale(memory: memoryStore.memory)
        }
    }
}

#Preview("Cold launch") {
    let defaults = UserDefaults(suiteName: "RootTabView.preview")!
    return RootTabView()
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(CustomRoutineStore(defaults: defaults))
        .environmentObject(RecentPicksStore(defaults: defaults))
        .environmentObject(TabSelectionStore())
        .environmentObject(CoachConversationStore(defaults: defaults))
        // Both are declared on RootTabView and read in the .task, so omitting
        // them made this preview trap with "No ObservableObject of type
        // SportLogStore found" the moment it rendered.
        .environmentObject(SportLogStore(defaults: defaults))
        .environmentObject(SubscriptionStore())
        // TodayScreen (rendered inside TodayTab) declares the detection
        // store, so the preview traps without it — same reason as the
        // SportLogStore line above.
        .environmentObject(ActivityDetectionStore(defaults: defaults))
}
