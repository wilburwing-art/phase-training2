// InsightCard.swift — reusable "Because X → I changed Y → so that Z" surface.
//
// Used on TodayScreen (above hero), WeekScreen (above plan), and the post-
// workout screen in Phase 12. Static copy this phase; Phase 13 coach pipes
// in dynamic reasoning + a CTA. nil body = card collapses (caller decides
// whether to render at all).

import SwiftUI

struct InsightCard: View {
    let message: String?
    let cta: CTA?
    /// When set, tapping the card opens the coach drawer with this text
    /// pre-loaded as a follow-up prompt. Wired through CoachConversationStore.
    let coachFollowUp: String?

    @EnvironmentObject private var conv: CoachConversationStore
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false

    struct CTA {
        let label: String
        let action: () -> Void
    }

    init(body: String?, cta: CTA? = nil, coachFollowUp: String? = nil) {
        self.message = body
        self.cta = cta
        self.coachFollowUp = coachFollowUp
    }

    var body: some View {
        if let text = self.message {
            let canOpenCoach = consentGranted && (coachFollowUp != nil)
            let inner = cardContent(text: text, hint: canOpenCoach ? "TAP TO ASK COACH" : nil)
            if canOpenCoach {
                Button(action: openCoach) {
                    inner
                }
                .buttonStyle(.plain)
            } else {
                inner
            }
        }
    }

    private func cardContent(text: String, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accent)
                    .padding(.top, 2)
                Text(text)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let cta = cta {
                Button(action: cta.action) {
                    HStack(spacing: 4) {
                        Text(cta.label)
                            .styled(.micro)
                            .foregroundStyle(Color.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    }
                }
                .buttonStyle(.plain)
            } else if let hint {
                HStack(spacing: 4) {
                    Text(hint)
                        .styled(.micro)
                        .foregroundStyle(Color.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func openCoach() {
        guard let prefill = coachFollowUp else { return }
        conv.present(withPrefill: prefill)
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "InsightCard.preview")!
    return VStack(spacing: 12) {
        InsightCard(body: "Because you slept poorly last night, I trimmed today's session by 15 minutes.")
        InsightCard(
            body: "Your knees flagged last week. I swapped front squats for goblet squats.",
            cta: InsightCard.CTA(label: "REVIEW EDIT", action: {})
        )
        InsightCard(body: nil)
    }
    .padding()
    .background(Color.bg)
    .preferredColorScheme(.dark)
    .environmentObject(CoachConversationStore(defaults: defaults))
}
