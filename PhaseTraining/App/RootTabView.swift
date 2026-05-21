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
}
