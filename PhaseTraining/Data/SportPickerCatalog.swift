// SportPickerCatalog.swift — the sports the onboarding and Profile pickers
// offer, grouped under their coach.db depth-0 root. Every row of
// `sport_categories` that `SportCatalog.isPlannable` accepts appears, so a
// sport that gains routines shows up without a hand edit to `Sport.catalog`.

import Foundation

struct SportPickerSection: Identifiable {
    let root: Sport
    let sports: [Sport]
    var id: String { root.slug }
}

enum SportPickerCatalog {
    /// Computed once: coach.db is read-only.
    static let sections: [SportPickerSection] = build()

    private static let sportsBySlug: [String: Sport] = {
        var out: [String: Sport] = [:]
        for section in sections {
            for sport in section.sports { out[sport.slug] = sport }
        }
        return out
    }()

    static func sport(slug: String) -> Sport? { sportsBySlug[slug] }

    static func sections(matching query: String) -> [SportPickerSection] {
        let q = fold(query)
        guard !q.isEmpty else { return sections }
        return sections.compactMap { section in
            if fold(section.root.name).contains(q) { return section }
            let hits = section.sports.filter {
                fold($0.name).contains(q) || fold($0.slug).contains(q)
            }
            return hits.isEmpty ? nil : SportPickerSection(root: section.root, sports: hits)
        }
    }

    private static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func displayName(slug: String, fallback: String) -> String {
        Sport.catalog.first(where: { $0.slug == slug })?.name ?? fallback
    }

    private static func build() -> [SportPickerSection] {
        let rows = CoachDatabase.shared.sportCategoryRows()
        var bySlug: [String: (slug: String, name: String, parentSlug: String?, sortOrder: Int)] = [:]
        for row in rows { bySlug[row.slug] = row }

        func rootSlug(of slug: String) -> String {
            var current = slug
            var hops = 0
            while let parent = bySlug[current]?.parentSlug, bySlug[parent] != nil, hops < 16 {
                current = parent
                hops += 1
            }
            return current
        }

        var membersByRoot: [String: [Sport]] = [:]
        // rows arrive ordered by sort_order, then name
        for row in rows where SportCatalog.isPlannable(row.slug) {
            let sport = Sport(slug: row.slug, name: displayName(slug: row.slug, fallback: row.name))
            membersByRoot[rootSlug(of: row.slug), default: []].append(sport)
        }

        let roots = rows.filter { $0.parentSlug == nil && membersByRoot[$0.slug] != nil }
        return roots.map { root in
            var sports = membersByRoot[root.slug] ?? []
            if let idx = sports.firstIndex(where: { $0.slug == root.slug }), idx != 0 {
                sports.insert(sports.remove(at: idx), at: 0)
            }
            return SportPickerSection(
                root: Sport(slug: root.slug, name: displayName(slug: root.slug, fallback: root.name)),
                sports: sports)
        }
    }
}
