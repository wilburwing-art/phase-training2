// RootTabView.swift — Phase 11 nav shell.
// 4 tabs: Today (live workout flow), Week (per-week planning + edits),
// Progress (Phase 12), Profile. The routine library lives behind sheets
// reachable from Today + Week — no longer a primary tab.

import SwiftUI

enum AppTab: Hashable {
    case today, week, progress, profile
}

struct RootTabView: View {
    @State private var selected: AppTab = .today

    var body: some View {
        TabView(selection: $selected) {
            TodayTab()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
                .tag(AppTab.today)

            WeekScreen()
                .tabItem { Label("Week", systemImage: "calendar") }
                .tag(AppTab.week)

            ProgressTabPlaceholder()
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
}
