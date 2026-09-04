// CoachPolishedExplanationSheet.swift — coach-polished transparency sheet.
//
// Pure extraction from TodayScreen.swift (architecture item 12); previously a
// file-private nested struct, now internal so TodayScreen's sheet builder can
// construct it cross-file.
//
// Read-only explanation for the "personalized by coach" pill on Today (and
// reusable on any surface that wants to expose the build-98 background
// refinement). Deliberately not a diff card: refinement is the visible
// default for consented users (per the build-98 design in
// `PlanStore+LLMRefinement.swift`), not a proposal awaiting Apply. The audit
// flagged a lack of transparency, not a missing consent gate — this is the
// transparency answer without re-introducing a friction prompt.

import SwiftUI

struct CoachPolishedExplanationSheet: View {
    let refinedAt: Date?
    let provenance: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accent)
                Text("Personalized by your coach")
                    .font(.system(size: 18, weight: .bold))
            }

            Text("Your coach reshaped today's workout based on recent sessions, soreness, and goals. The shape of your week (push / pull / legs and rest days) is unchanged. Only this day's exercise picks, sets, RPE, or weights are different from the deterministic default.")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if let provenance, !provenance.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REASON")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    Text(provenance)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink)
                }
            }

            if let refinedAt {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UPDATED")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    Text(refinedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink)
                }
            }

            Text("To opt out of background polishing, turn the coach off in Profile.")
                .font(.system(size: 12))
                .foregroundStyle(Color.ink3)
                .padding(.top, 4)

            Spacer(minLength: 8)

            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accent)
                    .foregroundStyle(Color.accentInk)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach-polished-explanation-done")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg.ignoresSafeArea())
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
