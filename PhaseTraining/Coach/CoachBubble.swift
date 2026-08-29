// CoachBubble.swift — floating chat affordance.
//
// The Kettle mascot at 64pt with NO container, anchored bottom-right and
// sitting above the tab bar via safe-area-inset padding. A kettlebell is
// already a closed round shape, so a disc was drawing a circle around a
// circle; dropping it also lets the art hit MASCOT2.md's 64pt floor, which
// the old 52pt disc did not. The frame is the tap target.
//
// Hidden conditions (any one short-circuits):
//   - user hasn't granted AI Coach consent
//   - current tab is .profile (it's the off-switch; the button there is weird)
//   - an active workout session is running (LogScreen takes the screen)
//   - any sheet/full-screen cover is presented (this is enforced by where
//     we place the overlay — at TabView level, sheets cover it)
//
// There is no "thinking" state: while the coach streams, the drawer is up and
// covering this view, so it would never be seen.

import SwiftUI

struct CoachBubble: View {
    @EnvironmentObject private var conv: CoachConversationStore
    @EnvironmentObject private var tabSelection: TabSelectionStore
    @EnvironmentObject private var sessionStore: SessionStore
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false
    @AppStorage(CoachEntitlement.proKey) private var proEntitled: Bool = false

    /// Art size. MASCOT2.md sets a 64pt floor on live surfaces.
    private static let art: CGFloat = 64
    /// Unread dot, and its centre in the art frame.
    private static let dot: CGFloat = 14
    private static let dotCentre = CGPoint(x: 44, y: 8)

    var body: some View {
        if shouldShow {
            HStack {
                Spacer()
                button
            }
            .padding(.trailing, 16)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private var shouldShow: Bool {
        Self.shouldShow(consent: consentGranted,
                        pro: proEntitled,
                        onProfileTab: tabSelection.selected == .profile,
                        sessionActive: sessionStore.active != nil)
    }

    /// Pure form of the hidden conditions so tests can exercise the consent
    /// x pro matrix (including the lapsed state) without a view hierarchy.
    /// requirePro is parameterized like CoachEntitlement.unlocked so both
    /// sides of the monetization switch stay testable.
    static func shouldShow(consent: Bool, pro: Bool, onProfileTab: Bool, sessionActive: Bool,
                           requirePro: Bool = CoachEntitlement.proRequired) -> Bool {
        CoachEntitlement.unlocked(consent: consent, pro: pro, requirePro: requirePro)
            && !onProfileTab
            && !sessionActive
    }

    private var button: some View {
        Button {
            conv.present()
        } label: {
            EmptyView()
        }
        .buttonStyle(CoachAvatarStyle(art: Self.art,
                                      dot: Self.dot,
                                      dotCentre: Self.dotCentre,
                                      pending: conv.hasPendingProposal))
        .accessibilityLabel(conv.hasPendingProposal
                            ? "Ask the coach, a suggestion is waiting"
                            : "Ask the coach")
    }
}

/// Draws the whole control, because pressed has to change the ART: with no
/// disc there is no fill to dim, so the mascot snapping to the peak of its
/// flex squeeze is what carries the feedback. A ButtonStyle is the only place
/// `isPressed` is available to the thing being drawn.
private struct CoachAvatarStyle: ButtonStyle {
    let art: CGFloat
    let dot: CGFloat
    let dotCentre: CGPoint
    let pending: Bool

    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: .topLeading) {
            KettleBust(frozenAt: configuration.isPressed ? KettleBust.peakFlex : 0,
                       size: art)
                .shadow(color: Color.black.opacity(0.55), radius: 2, x: 0, y: 2)
            if pending {
                // Pinned to the handle's top-right shoulder. With no disc
                // there is no rim to hang it on, and the handle is the only
                // real edge left.
                Circle()
                    .fill(Color.danger)
                    .frame(width: dot, height: dot)
                    .overlay(Circle().strokeBorder(Color.bg, lineWidth: 2.5))
                    .offset(x: dotCentre.x - dot / 2, y: dotCentre.y - dot / 2)
            }
        }
        .frame(width: art, height: art)
        .contentShape(Rectangle())
        .scaleEffect(configuration.isPressed ? 0.92 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7),
                   value: configuration.isPressed)
    }
}
