//
//  BodyAnatomyView.swift
//  PhaseTraining
//
//  Reusable anatomy component: takes a slug→intensity dictionary keyed on
//  muscle_groups.slug (see db/source/_schema.sql) and renders a front- or
//  back-view human body with the matching regions colored in.
//
//  This is a thin wrapper over the MIT-licensed MuscleMap SwiftUI package
//  (https://github.com/melihcolpan/MuscleMap). MuscleMap's `Muscle` enum
//  exposes ~36 muscle groups; our schema has ~80 (Latissimus Dorsi vs.
//  Pectoralis Major Clavicular vs. Vastus Medialis, etc.). We bubble the
//  granular slugs up to the nearest renderable parent — see
//  `Self.muscleForSlug` for the full mapping.
//

import SwiftUI
import MuscleMap

/// Renders a stylized human body silhouette with selected muscle groups
/// shaded by intensity. Other screens (recovery body, exercise muscle preview)
/// consume this component by passing a slug-keyed dictionary.
///
/// ```swift
/// BodyAnatomyView(
///     highlights: ["chest": .primary, "triceps": .secondary],
///     side: .front
/// )
/// .frame(width: 200, height: 400)
/// ```
struct BodyAnatomyView: View {

    // MARK: - Types

    /// How strongly a muscle is highlighted. Maps to the three-tier red /
    /// orange / yellow gradient used across the app.
    enum HighlightIntensity {
        case primary
        case secondary
        case tertiary
        case none

        var color: Color? {
            switch self {
            case .primary:   return Color(red: 0.91, green: 0.30, blue: 0.24)   // #E74C3C
            case .secondary: return Color(red: 0.95, green: 0.61, blue: 0.07)   // #F39C12
            case .tertiary:  return Color(red: 0.95, green: 0.77, blue: 0.06)   // #F1C40F
            case .none:      return nil
            }
        }
    }

    enum AnatomySide {
        case front
        case back

        fileprivate var muscleMapSide: BodySide {
            switch self {
            case .front: return .front
            case .back:  return .back
            }
        }
    }

    // MARK: - Inputs

    /// muscle_groups.slug → highlight intensity. Slugs not understood by the
    /// underlying renderer are silently ignored (e.g. `diaphragm`,
    /// `pelvic-floor`, container slugs like `upper-body`).
    let highlights: [String: HighlightIntensity]
    let side: AnatomySide
    /// Silhouette to draw. Defaults to `.male` so existing call sites are
    /// unchanged, but the recovery views pass the user's actual
    /// `TrainingMemory.gender` — this was hardcoded `.male` for every caller,
    /// including the 320pt recovery hero, while the same screen already read
    /// gender for StrengthStandards.
    var bodyGender: Gender = .male
    /// Optional override color. When set, every highlighted muscle renders in
    /// this color regardless of its `HighlightIntensity` — the badge-on-tile
    /// case wants accent-on-elevated, not the red/orange/yellow recovery
    /// palette. Unset = use each intensity's natural color.
    var tint: Color? = nil

    // MARK: - Body

    var body: some View {
        // MuscleMap requires sub-groups enabled to render upperChest,
        // frontDeltoid, etc. separately from their parents. We turn that
        // on so callers can target sub-regions when they have the data,
        // and so parent-only highlights (`chest`) still cover the whole
        // chest because we explicitly expand them in `mappedHighlights`.
        buildBodyView()
            .accessibilityLabel(accessibilityLabel)
    }

    /// MuscleMap ships two silhouettes, so `.nonbinary` / `.preferNotToSay`
    /// have to land on one. Kept on `.male` — the prior behavior for every
    /// user — rather than silently reassigning people who declined to say.
    private var muscleMapGender: BodyGender {
        bodyGender == .female ? .female : .male
    }

    private func buildBodyView() -> BodyView {
        var view = BodyView(gender: muscleMapGender, side: side.muscleMapSide)
            .showSubGroups()
        for (muscle, color) in mappedHighlights {
            view = view.highlight(muscle, color: color)
        }
        return view
    }

    /// Collapse the slug → intensity dict into a `Muscle` → `Color` dict
    /// the MuscleMap renderer understands. Multiple slugs can map to the
    /// same `Muscle`; the highest intensity wins.
    private var mappedHighlights: [Muscle: Color] {
        var result: [Muscle: HighlightIntensity] = [:]
        for (slug, intensity) in highlights {
            guard intensity != HighlightIntensity.none else { continue }
            let muscles = Self.musclesForSlug(slug)
            for muscle in muscles {
                let existing = result[muscle] ?? .none
                if intensity.priority > existing.priority {
                    result[muscle] = intensity
                }
            }
        }
        return result.compactMapValues { intensity in
            tint ?? intensity.color
        }
    }

    private var accessibilityLabel: String {
        let sideLabel = side == .front ? "front" : "back"
        let highlighted = highlights
            .filter { $0.value != .none }
            .map { $0.key }
            .sorted()
        if highlighted.isEmpty {
            return "Anatomy diagram, \(sideLabel) view, no muscles highlighted."
        }
        return "Anatomy diagram, \(sideLabel) view, highlighting \(highlighted.joined(separator: ", "))."
    }

    // MARK: - Slug → MuscleMap mapping

    /// Translates a phase-training muscle_groups.slug into the set of
    /// MuscleMap `Muscle` cases that should be lit up. Returns an empty
    /// array for slugs the renderer can't visualize (deep core, container
    /// rollups). Granular sub-muscles bubble up to their nearest visible
    /// parent.
    ///
    /// **Coverage status:** see PR body for the full slug-by-slug table.
    /// Anything not listed here is intentionally unmapped.
    private static func musclesForSlug(_ slug: String) -> [Muscle] {
        switch slug {
        // Chest
        case "chest":              return [.chest, .upperChest, .lowerChest]
        case "pec-major-clav":     return [.upperChest]
        case "pec-major-sternal":  return [.lowerChest]
        case "pec-minor":          return [.chest]
        case "serratus-anterior":  return [.serratus]

        // Shoulders
        case "shoulders":          return [.deltoids, .frontDeltoid, .rearDeltoid]
        case "delt-anterior":      return [.frontDeltoid]
        case "delt-lateral":       return [.deltoids]
        case "delt-posterior":     return [.rearDeltoid]

        // Rotator cuff (all 4 heads collapse to the cuff region)
        case "rotator-cuff",
             "supraspinatus",
             "infraspinatus",
             "teres-minor",
             "subscapularis":      return [.rotatorCuff]

        // Back
        case "back":               return [.upperBack, .lowerBack]
        case "lats":               return [.upperBack]
        case "traps":              return [.trapezius, .upperTrapezius, .lowerTrapezius]
        case "upper-traps":        return [.upperTrapezius]
        case "mid-traps",
             "lower-traps":        return [.lowerTrapezius]
        case "rhomboids":          return [.rhomboids]
        case "teres-major":        return [.upperBack]
        case "erector-thoracic":   return [.upperBack]
        case "erector-lumbar",
             "multifidus",
             "quadratus-lumborum": return [.lowerBack]

        // Arms
        case "arms":               return [.biceps, .triceps, .forearm]
        case "biceps":             return [.biceps]
        case "brachialis":         return [.biceps]
        case "brachioradialis":    return [.forearm]
        case "triceps":            return [.triceps]
        case "forearm-flexors",
             "forearm-extensors",
             "finger-flexors",
             "finger-extensors":   return [.forearm]
        case "grip-crush",
             "grip-pinch",
             "grip-support":       return [.hands]

        // Core
        case "rectus-abdominis":   return [.abs, .upperAbs, .lowerAbs]
        case "external-obliques",
             "internal-obliques",
             "transverse-abdominis": return [.obliques]
        // Deep stabilizers (diaphragm, pelvic-floor) and hip rotators have
        // no visible surface anatomy; fall through to default (no render).
        case "piriformis":         return [.gluteal]
        case "hip-rotators":       return [.gluteal]

        // Quads / hip flexors
        case "quadriceps":         return [.quadriceps, .innerQuad, .outerQuad]
        case "rectus-femoris":     return [.quadriceps]
        case "vastus-lateralis":   return [.outerQuad]
        case "vastus-medialis":    return [.innerQuad]
        case "vastus-intermedius": return [.quadriceps]
        case "hip-flexors",
             "iliopsoas",
             "sartorius",
             "tfl":                return [.hipFlexors]

        // Hamstrings / glutes / adductors
        case "hamstrings",
             "biceps-femoris",
             "semitendinosus",
             "semimembranosus":    return [.hamstring]
        case "glutes",
             "glute-max",
             "glute-med",
             "glute-min":          return [.gluteal]
        case "adductors":          return [.adductors]

        // Calves & feet
        case "calves",
             "gastrocnemius",
             "soleus":             return [.calves]
        case "tib-anterior":       return [.tibialis]
        case "peroneals":          return [.calves]   // approximate
        case "intrinsic-foot":     return [.feet]

        // Neck
        case "neck",
             "scm",
             "deep-neck-flexors",
             "cervical-extensors",
             "scalenes",
             "levator-scapulae":   return [.neck]

        // Unmapped: container slugs (full-body, upper-body, lower-body, core),
        // deep-only muscles (diaphragm, pelvic-floor), and anything new the
        // schema gains after this file was written. Silently render nothing.
        default:                   return []
        }
    }
}

// MARK: - Intensity ordering

private extension BodyAnatomyView.HighlightIntensity {
    /// Higher = takes precedence when multiple slugs map to the same muscle.
    var priority: Int {
        switch self {
        case .primary:   return 3
        case .secondary: return 2
        case .tertiary:  return 1
        case .none:      return 0
        }
    }
}

// MARK: - Preview

#Preview("Front & Back") {
    HStack(spacing: 16) {
        BodyAnatomyView(
            highlights: [
                "chest":     .primary,
                "triceps":   .secondary,
                "shoulders": .tertiary
            ],
            side: .front
        )
        .frame(width: 160, height: 360)

        BodyAnatomyView(
            highlights: [
                "lats":   .primary,
                "traps":  .secondary,
                "glutes": .tertiary
            ],
            side: .back
        )
        .frame(width: 160, height: 360)
    }
    .padding()
    .background(Color(red: 0x0A / 255, green: 0x0B / 255, blue: 0x0D / 255))
}

#Preview("Empty (gray silhouette)") {
    BodyAnatomyView(highlights: [:], side: .front)
        .frame(width: 200, height: 400)
        .padding()
        .background(Color(red: 0x0A / 255, green: 0x0B / 255, blue: 0x0D / 255))
}

#Preview("Tinted vs untinted") {
    HStack(spacing: 16) {
        VStack(spacing: 8) {
            Text("untinted").font(.caption).foregroundStyle(.secondary)
            BodyAnatomyView(
                highlights: ["chest": .primary, "triceps": .secondary, "shoulders": .tertiary],
                side: .front
            )
            .frame(width: 160, height: 360)
        }
        VStack(spacing: 8) {
            Text("tint: .accent").font(.caption).foregroundStyle(.secondary)
            BodyAnatomyView(
                highlights: ["chest": .primary, "triceps": .secondary, "shoulders": .tertiary],
                side: .front,
                tint: Color.accent
            )
            .frame(width: 160, height: 360)
        }
    }
    .padding()
    .background(Color(red: 0x0A / 255, green: 0x0B / 255, blue: 0x0D / 255))
}
