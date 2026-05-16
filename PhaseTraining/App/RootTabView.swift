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
    case today, week, progress, profile
}

final class TabSelectionStore: ObservableObject {
    @Published var selected: AppTab = .today
}

struct RootTabView: View {
    @EnvironmentObject private var tabSelection: TabSelectionStore

    var body: some View {
        TabView(selection: $tabSelection.selected) {
            TodayTab()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
                .tag(AppTab.today)

            WeekScreen()
                .tabItem { Label("Week", systemImage: "calendar") }
                .tag(AppTab.week)

            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)

            ProfileScreen()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Color.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview("Cold launch") {
    RootTabView()
        .environmentObject(SessionStore(defaults: UserDefaults(suiteName: "RootTabView.preview")!))
        .environmentObject(MemoryStore(defaults: UserDefaults(suiteName: "RootTabView.preview.mem")!))
        .environmentObject(PlanStore(defaults: UserDefaults(suiteName: "RootTabView.preview.plan")!))
        .environmentObject(TabSelectionStore())
}
