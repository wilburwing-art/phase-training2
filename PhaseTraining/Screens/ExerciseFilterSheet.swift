// ExerciseFilterSheet.swift — secondary filter modal.
//
// The primary muscle bucket lives in the chip strip on the picker / library
// screen. Everything else (movement category, modality, difficulty,
// environment, compound/isolation) lives here so the main surface stays
// uncluttered. The user opens this via the "All filters" button.
//
// Operates on a binding to ExerciseFilters. Apply = dismiss with the
// current state; Reset = clear secondaries (leaving the primary bucket
// alone since that's set outside this sheet).

import SwiftUI

struct ExerciseFilterSheet: View {
    @Binding var filters: ExerciseFilters
    @Environment(\.dismiss) private var dismiss

    private let modalities: [(slug: String, label: String)] = [
        ("strength", "Strength"),
        ("endurance", "Endurance"),
        ("power", "Power"),
        ("plyometric", "Plyometric"),
        ("agility", "Agility"),
    ]
    private let difficulties: [(slug: String, label: String)] = [
        ("beginner", "Beginner"),
        ("intermediate", "Intermediate"),
        ("advanced", "Advanced"),
        ("elite", "Elite"),
    ]
    private let environments: [(slug: String, label: String)] = [
        ("home", "Home"),
        ("gym", "Gym"),
        ("outdoor", "Outdoor"),
        ("anywhere", "Anywhere"),
        ("sport_facility", "Sport facility"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        section(title: "Movement") {
                            chipGrid(
                                items: MovementCategory.allCases.map { ($0.rawValue, $0.label) },
                                selected: filters.category?.rawValue,
                                onSelect: { slug in
                                    if filters.category?.rawValue == slug {
                                        filters.category = nil
                                    } else {
                                        filters.category = slug.flatMap(MovementCategory.init(rawValue:))
                                    }
                                }
                            )
                        }
                        section(title: "Style") {
                            chipGrid(
                                items: modalities.map { ($0.slug, $0.label) },
                                selected: filters.modality,
                                onSelect: { slug in
                                    filters.modality = (filters.modality == slug) ? nil : slug
                                }
                            )
                        }
                        section(title: "Difficulty") {
                            chipGrid(
                                items: difficulties.map { ($0.slug, $0.label) },
                                selected: filters.difficulty,
                                onSelect: { slug in
                                    filters.difficulty = (filters.difficulty == slug) ? nil : slug
                                }
                            )
                        }
                        section(title: "Where") {
                            chipGrid(
                                items: environments.map { ($0.slug, $0.label) },
                                selected: filters.environment,
                                onSelect: { slug in
                                    filters.environment = (filters.environment == slug) ? nil : slug
                                }
                            )
                        }
                        section(title: "Type") {
                            chipGrid(
                                items: [("compound", "Compound"), ("isolation", "Isolation")],
                                selected: filters.compoundOnly.map { $0 ? "compound" : "isolation" },
                                onSelect: { slug in
                                    let next: Bool? = slug == "compound" ? true : false
                                    let current = filters.compoundOnly
                                    filters.compoundOnly = (current == next) ? nil : next
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        filters.clearSecondary()
                    }
                    .foregroundStyle(Color.ink2)
                    .disabled(filters.secondaryCount == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func section<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .tracking(1)
            content()
        }
    }

    private func chipGrid(
        items: [(slug: String, label: String)],
        selected: String?,
        onSelect: @escaping (String?) -> Void
    ) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.slug) { item in
                Button {
                    onSelect(item.slug)
                } label: {
                    Text(item.label)
                        .styled(.micro)
                        .foregroundStyle(selected == item.slug ? Color.accentInk : Color.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selected == item.slug ? Color.accent : Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == item.slug ? Color.clear : Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - FlowLayout

/// Simple wrapping flow layout for the chip grids. SwiftUI's built-in
/// `HStack`s don't wrap; `LazyVGrid` requires fixed columns. This wraps
/// chips of varying width across multiple lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                totalHeight += lineHeight + spacing
                totalWidth = max(totalWidth, lineWidth - spacing)
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        totalWidth = max(totalWidth, lineWidth - spacing)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
