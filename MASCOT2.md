# Kettle — PhaseTraining mascot #2

An anthropomorphized **kettlebell**, sibling to [the Repelican](MASCOT.md). Same
cream-lime-coral family so the two read as one universe: the cast-iron bell is
the body, the iconic handle is the signature, and it wears a friendly
face-on-a-belly.

Chosen over a dumbbell and a shaker bottle — the kettlebell has the strongest
silhouette and the friendliest read at small sizes.

## The five loops

Unlike the Repelican (one `bulk` scalar), Kettle's variation axis is **motion**.
It has five seamless animation loops — each a periodic function of time, so
there's no seam at the wrap:

| Loop        | Cycle | Motion                                                        | Home |
| ----------- | ----- | ------------------------------------------------------------ | ---- |
| Flex        | 1.1s  | Bicep pulse + rise, energy ticks flare on the squeeze        | Session-complete / PR celebration |
| Stretch     | 3.0s  | Overhead reach, slow side-to-side sway, breathing rise       | Rest-day & mobility |
| Snowboard   | 1.7s  | Carves edge to edge, board rocking, snow spray off the tail  | Seasonal flourish |
| Climb       | 2.4s  | Reaches for the next hold and pulls up, chalk puff at the top | Sport day (climbing) |
| Bike        | 1.0s  | Legs pedal the crank, wheels spin, speed lines pulse         | Sport day (cycling) |

`KettlePose.forSport(_:)` maps a `Sport.slug` to a loop (climbing → climb,
cycling → bike, else the flex idle), so a sport-day card can show the loop that
matches the user's actual sport.

## Palette — shared with the Repelican

Identity colors are `Theme.swift` tokens; in-app rendering references them so
the mascot can't drift from the theme.

| Part                    | Token          | Hex       |
| ----------------------- | -------------- | --------- |
| Cast bell body + limbs  | `Color.ink`    | `#F5F5F0` |
| Handle                  | `Color.accent` | `#D4FF3D` |
| Feet (shoes)            | `Color.danger` | `#FF6B4A` |
| Ground                  | `Color.bg`     | `#0A0B0D` |

Derived shades (`#DEDED6`, `#C7C7BD`, `#E24A2C`) are tints for depth, not brand
colors. Dark-ground only.

## Rendering

Native SwiftUI, no raster: a `Canvas` drives the drawing and a
`TimelineView(.animation)` advances a clock so the loops animate with zero image
weight (same philosophy as `RepelicanView`). Reduce Motion falls back to a
static rest frame.

## Usage rules

- **≥ 64 pt** on live surfaces; never in scrolling list rows (the muscle-chip
  lesson — see `MuscleChipGeneratorView`).
- Decorative placements get `.accessibilityHidden(true)`; a meaningful one
  carries a descriptive label.
- Honor Reduce Motion (the view already does).

## Where it ships

- **The coach button** (`CoachBubble`) is Kettle's first live surface: the flex
  pose at 64pt with NO container, bottom-right above the tab bar. Framed by
  `KettleBust`, which crops the 160x200 design space to a 156-unit square at
  (2, 32). Do not tighten that window: anything smaller cuts the shoes off flat
  at the frame edge, which a disc used to hide and a container-less control
  does not. `KettleBustTests` pins it against the pose extremes.
- The Today card and the complete screen use `KettleView` directly.

**Known and accepted (2026-08-29):** on Today the button floats over the
full-width lime "Start workout" CTA, and the lime handle washes out against it.
A dark halo behind the art was offered and declined; the decision is to leave
it. Do not "fix" this without asking.

**Open:** whether the button's pose binds to `KettlePose.forSport(_:)`. The five
loops span 80 to 135 units wide, a 1.7x spread that a disc would have hidden,
so binding it makes the button change size. Current call is to keep flex on the
button permanently and spend the other loops on the cards.

## Files

- `PhaseTraining/Components/KettleView.swift` — the shipped native mascot
  (`KettleView`, `KettlePose` + `forSport`, the `Canvas`/`TimelineView` loops).
- `PhaseTraining/Components/KettleBust.swift` — the square crop used by the
  coach button, plus `peakFlex` (the loop time where the squeeze is at 1).
- `handoff/mascot2/generate.mjs` — the parametric SVG **source of truth**. Run
  `node handoff/mascot2/generate.mjs` to regenerate the frozen stills.
- `handoff/mascot2/kettle*.svg` — one representative still per pose (reference;
  the motion lives in `KettleView`).

## Naming

**Kettle** is the chosen name. Also considered: Bell, Ringo, Swings.
