// ExerciseSearchVocabulary.swift — the gap between what lifters type and what
// the catalog is named.
//
// coach.db names a movement one way ("Dumbbell Overhead Press"); people search
// for it another ("dumbbell shoulder press", "db shoulder press", "ohp"). None
// of that is a typo, so neither separator-stripping nor edit-distance fuzzing
// rescues it — "shoulder" is 6 edits from "overhead". This file holds the two
// vocabulary layers that do:
//
//  1. `rewrite` — whole-token substitutions applied to the query BEFORE the
//     substring match: gym abbreviations (db, bb, kb, ohp, rdl) and the
//     plurals regular suffix-stripping gets wrong ("calves" → "calf", not
//     "calve"). These run up front because a query like "rdl" otherwise
//     substring-matches junk ("Campus Board LaDdeR"), and a junk hit is still
//     a hit — it would block the smarter fallbacks behind it.
//
//  2. `aliases` — interchangeable words, used only by the zero-result fuzzy
//     fallback. Bidirectional: "shoulder press" finds the overhead presses and
//     "overhead press" finds Shoulder Press (Machine). Kept out of the primary
//     query on purpose, so a search that literally matches something is never
//     diluted by synonyms.
//
// Both lists are deliberately short and catalog-grounded: every entry rescues a
// query that returns nothing today. Adding a synonym that matches no catalog
// row is dead weight; adding one that is merely *related* ("tricep extension"
// for "Tricep Pushdown" — different movements) makes the picker lie.

import Foundation

enum ExerciseSearchVocabulary {

    /// Whole-token substitutions. Keys are matched against lowercased query
    /// tokens in full — "db" rewrites, "dbell" does not — and values may be
    /// multi-word ("ohp" → "overhead press").
    static let wordRewrites: [String: String] = [
        // Equipment shorthand. Universal gym usage, no catalog collisions.
        "db": "dumbbell",
        "bb": "barbell",
        "kb": "kettlebell",
        "bw": "bodyweight",
        // Lift shorthand.
        "ohp": "overhead press",
        "rdl": "romanian deadlift",
        "sldl": "stiff leg deadlift",
        // Irregular plurals. CoachDatabase.singularStem handles the regular
        // "-s"/"-es" cases; these are the ones a suffix rule gets wrong
        // ("calves" → "calve", "flies" → "flie" — neither is in any name).
        "calves": "calf",
        "flies": "fly",
        "flyes": "fly",
    ]

    /// Interchangeable words, as equivalence classes — membership is symmetric,
    /// so each class works in both directions.
    static let equivalents: [Set<String>] = [
        // "Shoulder Press", "Overhead Press" and "Military Press" name the
        // same movement; the catalog uses all three across variants.
        ["shoulder", "overhead", "military"],
        // "side raise" / "lateral raise".
        ["lateral", "side"],
        // "rear delt fly" / "Bent-Over Reverse Fly".
        ["rear", "reverse"],
        // "farmers walk" / "Farmer's Carry".
        ["walk", "carry"],
    ]

    /// token → every word interchangeable with it, including itself.
    private static let aliasIndex: [String: Set<String>] = {
        var index: [String: Set<String>] = [:]
        for group in equivalents {
            for word in group { index[word, default: []].formUnion(group) }
        }
        return index
    }()

    /// Words to try in place of `token` when fuzzy-matching. Always contains
    /// `token` itself, so callers can loop over this set unconditionally.
    static func aliases(for token: String) -> Set<String> {
        let lower = token.lowercased()
        guard let group = aliasIndex[lower] else { return [lower] }
        return group
    }

    /// Apply `wordRewrites` to each whole token of `query`, leaving anything
    /// unlisted alone. Tokenizing collapses the separators the search strips
    /// anyway, so the rejoined string is equivalent for matching.
    static func rewrite(_ query: String) -> String {
        let tokens = CoachDatabase.searchTokens(query)
        guard !tokens.isEmpty else { return query }
        let rewritten = tokens.map { wordRewrites[$0] ?? $0 }
        return rewritten.joined(separator: " ")
    }
}
