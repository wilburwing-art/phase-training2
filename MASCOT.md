# The Repelican — PhaseTraining mascot

A workout pelican. A riff on Simon Willison's
[pedalican](https://simonwillison.net/2026/Jul/14/pedalican/) — but where the
pedalican *rides*, the Repelican *lifts*. It carries the pelican lineage of the
`phase-training` family while making it unmistakably a **training** app.

Pose: front-facing double-biceps flex. Compact and readable — one silhouette at
a tab-bar 44 px, personality at hero size.

## The `bulk` parameter

The whole mascot is **one character driven by a single `bulk` value, 0.0 … 1.0**.
Bulk drives torso width, arm thickness, and the flex bump (Swole adds a pec
split and lime energy ticks). Three named builds are the reference points:

| Build     | `bulk` | Reads as                                  |
| --------- | ------ | ----------------------------------------- |
| Lean      | 0.00   | Marathoner / endurance build              |
| Athletic  | 0.55   | Balanced default — the canonical mascot   |
| Swole     | 1.00   | Full flex, pec split, energy ticks        |

Because `bulk` is one scalar, the physique can **morph** (Lean → Swole
animates for free) and can be **bound to data** — see "Physique tracks your
phase" below.

## Palette — brand tokens only

The identity colors are `Theme.swift` tokens, never new hexes. In-app rendering
must reference the tokens so the mascot can't drift from the theme.

| Part                    | Token          | Hex       |
| ----------------------- | -------------- | --------- |
| Feathers (body, head)   | `Color.ink`    | `#F5F5F0` |
| Bill + webbed feet      | `Color.danger` | `#FF6B4A` |
| Headband + wristbands   | `Color.accent` | `#D4FF3D` |
| Ground                  | `Color.bg`     | `#0A0B0D` |

Derived shades used for depth (`#DEDED6`, `#C7C7BD` feather shading; `#E24A2C`
bill outline; `#FF8A6E` pouch) are tints of the tokens above, not brand colors
in their own right. Authored for a dark ground — the mascot is dark-theme only,
matching the app.

## Physique tracks your phase

Because the app is literally *Phase*Training, the mascot's build reflects the
user's current `SeasonPhase` — the physique *is* the training block. Mapping
lives in `RepelicanPhysique.bulk(phase:weekInPhase:primaryIsEndurance:)`:

- **Off-season** ("build the engine") ramps up over the weeks in the phase.
- **Pre-season** / **maintenance** sit at the balanced Athletic build.
- **In-season** and **event prep** trend leaner (protect performance / peak).
- **Endurance-primary** athletes stay leaner throughout — a marathoner peaks
  *lean*, so "swole = winning" would be wrong for them. Bulk is scaled down
  when the primary sport is an endurance discipline.

No new persistence: it reads `TrainingMemory.seasonForPlanner`,
`weeksInCurrentPhase`, and `primarySport`.

## Usage rules

- **Minimum 64 pt** on live surfaces. Live vector rendering at tiny sizes was
  blurry and CPU-hot for the muscle chips (see `MuscleChipGeneratorView`); the
  mascot follows the same rule. Never place it in scrolling list rows. If a
  tiny raster is ever needed, pre-render via `ImageRenderer` like the chips.
- Decorative placements get `.accessibilityHidden(true)`; a meaningful one
  (the phase card) carries a descriptive label.
- Respect Reduce Motion — don't animate the bulk morph when it's on.

## Files

- `PhaseTraining/Components/RepelicanView.swift` — the shipped native SwiftUI
  mascot (Canvas, `Animatable`), the `RepelicanBuild` presets, and the
  `RepelicanPhysique` phase→bulk mapping.
- `handoff/mascot/generate.mjs` — the parametric SVG **source of truth**. Run
  `node handoff/mascot/generate.mjs` to regenerate the frozen exports.
- `handoff/mascot/repelican{,-lean,-athletic,-swole}.svg` — frozen exports.

## Naming

**Repelican** (reps + pelican) is the chosen name. Also considered: Swolican,
Deltican, Pumpican.
