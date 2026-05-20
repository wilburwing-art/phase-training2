// TodayTab.swift — Phase 8 split: owns the existing Start → Log → Complete → History flow.
// Cold-launch bootstrap (resume an in-progress session) lives here.

import SwiftUI

struct TodayTab: View {
    @EnvironmentObject private var store: SessionStore
    @State private var route: TodayRoute = .start
    @State private var bootstrapped = false

    enum TodayRoute: Equatable {
        case start
        case log
        case complete(ActiveSession)
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            content
        }
        .onAppear {
            guard !bootstrapped else { return }
            bootstrapped = true
            if store.active != nil { route = .log }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .start:
            // TodayScreen owns its own session-create logic so it can build
            // from today's coach.db routine instead of always upper-1.
            TodayScreen(
                onStart: { transition(.log) }
            )

        case .log:
            LogScreen(
                onFinish: {
                    if let active = store.active {
                        transition(.complete(active))
                    } else {
                        transition(.start)
                    }
                },
                onCancel: {
                    store.clearActive()
                    transition(.start)
                }
            )

        case .complete(let session):
            CompleteScreen(
                session: session,
                onSave: { transition(.start) },
                onDiscard: {
                    store.clearActive()
                    transition(.start)
                }
            )
        }
    }

    private func transition(_ next: TodayRoute) {
        withAnimation(.easeInOut(duration: 0.18)) { route = next }
    }
}
