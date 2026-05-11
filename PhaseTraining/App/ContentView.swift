import SwiftUI

enum Route {
    case start
    case log
    case complete(ActiveSession)
    case history
}

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var route: Route = .start
    @State private var bootstrapped = false

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            switch route {
            case .start:
                StartScreen(
                    onStart: {
                        if store.active == nil {
                            store.saveActive(store.createSession(templateId: "upper-1"))
                        }
                        withAnimation(.easeInOut(duration: 0.18)) { route = .log }
                    },
                    onHistory: {
                        withAnimation(.easeInOut(duration: 0.18)) { route = .history }
                    }
                )
            case .log:
                LogScreen(onFinish: {
                    if let active = store.active {
                        withAnimation(.easeInOut(duration: 0.18)) { route = .complete(active) }
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { route = .start }
                    }
                })
            case .complete(let session):
                CompleteScreen(session: session, onSave: {
                    withAnimation(.easeInOut(duration: 0.18)) { route = .start }
                })
            case .history:
                HistoryScreen(onBack: {
                    withAnimation(.easeInOut(duration: 0.18)) { route = .start }
                })
            }
        }
        .onAppear {
            guard !bootstrapped else { return }
            bootstrapped = true
            if store.active != nil {
                route = .log
            }
        }
    }
}

#Preview("Cold launch, no active") {
    ContentView()
        .environmentObject(SessionStore(defaults: UserDefaults(suiteName: "preview-cold")!))
}
