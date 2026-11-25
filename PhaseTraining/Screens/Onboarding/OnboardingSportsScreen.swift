// OnboardingSportsScreen.swift — step 2 of the onboarding flow.
// Multi-select sports + designate one as primary. The primary drives the
// season-aware generator. The catalog is gated to the sports the engine
// supports (ski / climb) — a supported sport is required to proceed.

import SwiftUI

struct OnboardingSportsScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var searchText = ""

    var body: some View {
        OnboardingScaffold(
            step: .sports,
            title: "What do you do?",
            subtitle: "Pick anything you train for. We'll plan around it.",
            nextEnabled: !draft.sports.isEmpty,
            onNext: {
                // If the user picked sports but didn't designate a primary, default to the first.
                if draft.primarySport == nil, let first = draft.sports.first {
                    draft.primarySport = first
                }
                onNext()
            },
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 16) {
                SportSearchField(text: $searchText)
                let sections = SportPickerCatalog.sections(matching: searchText)
                if sections.isEmpty {
                    SportPickerEmptyLine()
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        OnboardingSectionLabel(text: section.root.name)
                            .accessibilityAddTraits(.isHeader)
                        WrappingFlow(spacing: 8) {
                            ForEach(section.sports) { sport in
                                OnboardingChip(
                                    label: sport.name,
                                    selected: draft.sports.contains(sport),
                                    action: { toggle(sport) },
                                    a11yId: "onboarding-sport-\(sport.slug)"
                                )
                            }
                        }
                    }
                }

                if draft.sports.count > 1 {
                    Divider().background(Color.lineSoft).padding(.vertical, 4)
                    OnboardingSectionLabel(text: "Which is primary?")
                    Text("This is the one we plan around first.")
                        .styled(.body)
                        .foregroundStyle(Color.ink3)
                    VStack(spacing: 10) {
                        ForEach(draft.sports) { sport in
                            OnboardingPickRow(
                                title: sport.name,
                                subtitle: nil,
                                selected: draft.primarySport == sport,
                                action: { draft.primarySport = sport }
                            )
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ sport: Sport) {
        if let idx = draft.sports.firstIndex(of: sport) {
            draft.sports.remove(at: idx)
            if draft.primarySport == sport {
                draft.primarySport = draft.sports.first
            }
        } else {
            draft.sports.append(sport)
            if draft.primarySport == nil { draft.primarySport = sport }
        }
    }
}

// MARK: - Search field and empty line (shared with SportsEditorSheet)

struct SportSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .scaledSystemFont(14, within: 42)
                .foregroundStyle(Color.ink3)
            TextField("", text: $text,
                      prompt: Text("Search sports").foregroundColor(Color.ink3))
                .styled(.body)
                .foregroundStyle(Color.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("sport-search")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineStrong, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SportPickerEmptyLine: View {
    var body: some View {
        Text("No sport matches. More are added as programs land.")
            .styled(.body)
            .foregroundStyle(Color.ink3)
    }
}

// MARK: - Wrapping flow layout (chip cloud)

/// Minimal flow layout: lays children left-to-right, wraps to next row on overflow.
/// SwiftUI ships `Layout` in iOS 16+; we're on 17 so this is safe.
struct WrappingFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        var x: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                rows.append(0); rowHeights.append(0); x = 0
            }
            x += s.width + spacing
            rowHeights[rowHeights.count - 1] = max(rowHeights.last!, s.height)
            rows[rows.count - 1] = max(rows.last!, x)
        }
        let totalHeight = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingSportsScreen(draft: $draft, onNext: {}, onBack: {})
}
