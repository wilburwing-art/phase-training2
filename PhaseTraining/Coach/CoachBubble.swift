// CoachBubble.swift — floating chat affordance.
//
// 56pt accent-fill circle anchored bottom-right. Sits above the tab bar via
// safe-area-inset padding. Hidden conditions (any one short-circuits):
//   - user hasn't granted AI Coach consent
//   - current tab is .profile (it's the off-switch; bubble there is weird)
//   - an active workout session is running (LogScreen takes the screen)
//   - any sheet/full-screen cover is presented (this is enforced by where
//     we place the overlay — at TabView level, sheets cover it)

import SwiftUI

struct CoachBubble: View {
    @EnvironmentObject private var conv: CoachConversationStore
    @EnvironmentObject private var tabSelection: TabSelectionStore
    @EnvironmentObject private var sessionStore: SessionStore
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false

    var body: some View {
        if shouldShow {
            HStack {
                Spacer()
                bubble
            }
            .padding(.trailing, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private var shouldShow: Bool {
        consentGranted
            && tabSelection.selected != .profile
            && sessionStore.active == nil
    }

    private var bubble: some View {
        Button {
            conv.present()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 52, height: 52)
                    .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                Image(systemName: "message.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentInk)
            }
            .accessibilityLabel("Ask the coach")
        }
        .buttonStyle(.plain)
    }
}
