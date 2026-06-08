// CheckInFeedbackScreen.swift — step 3: how did last week feel?

import SwiftUI

struct CheckInFeedbackScreen: View {
    @Binding var draft: WeeklyCheckInDraft
    let onNext: () -> Void
    let onBack: () -> Void

    private static let ratings: [(String, String)] = [
        ("too_easy", String(localized: "Too easy", comment: "Last-week difficulty rating")),
        ("right",    String(localized: "Right", comment: "Last-week difficulty rating")),
        ("too_hard", String(localized: "Too hard", comment: "Last-week difficulty rating")),
    ]

    var body: some View {
        CheckInScaffold(
            step: .feedback,
            title: "Last week.",
            subtitle: "Used to bias the regenerated plan.",
            nextLabel: "Generate plan",
            nextEnabled: draft.lastWeekRating != nil,
            onNext: onNext,
            onBack: onBack,
            onClose: nil
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ratingRow
                freeText(
                    title: "WHAT WORKED?",
                    placeholder: "Bench felt strong, recovery was solid…",
                    text: $draft.worked
                )
                freeText(
                    title: "WHAT DIDN'T?",
                    placeholder: "Knee flared on day 3, too tired on Fri…",
                    text: $draft.didntWork
                )
            }
        }
    }

    private var ratingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OVERALL")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 5) {
                ForEach(Self.ratings, id: \.0) { value, label in
                    OnboardingChip(
                        label: label,
                        selected: draft.lastWeekRating == value,
                        action: { draft.lastWeekRating = draft.lastWeekRating == value ? nil : value },
                        a11yId: "checkin-rating-\(value)"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func freeText(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surface)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5)
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(Color.ink3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 80)
        }
    }
}
