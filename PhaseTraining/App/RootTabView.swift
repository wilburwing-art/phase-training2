// RootTabView.swift — Phase 8 nav shell.
// 5 tabs: Today (live workout flow), Week (Phase 10), Train (routine library),
// Progress (Phase 12), Profile (Phase 9). Train signals "go to Today" via a
// closure when a workout starts, so the live session surfaces immediately.

import SwiftUI

enum AppTab: Hashable {
    case today, week, train, progress, profile
}

struct RootTabView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var selected: AppTab = .today

    var body: some View {
        TabView(selection: $selected) {
            TodayTab()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
                .tag(AppTab.today)

            WeekScreen()
                .tabItem { Label("Week", systemImage: "calendar") }
                .tag(AppTab.week)

            TrainTab(switchToToday: { selected = .today })
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.train)

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
