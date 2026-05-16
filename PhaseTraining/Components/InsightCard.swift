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

    struct CTA {
        let label: String
        let action: () -> Void
    }

    init(body: String?, cta: CTA? = nil) {
        self.message = body
        self.cta = cta
    }

    var body: some View {
        if let text = self.message {
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
    }
}

#Preview {
    VStack(spacing: 12) {
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
}
