---
name: phase-training-mascot-geometry-three-copies
description: The Repelican's geometry exists in three places that can drift (handoff/mascot/generate.mjs, the frozen repelican*.svg exports, RepelicanView.swift's Canvas paint). Writing a fourth copy, or changing any one of them, needs a string diff against the frozen exports at bulk 0 / 0.55 / 1, because every error in mirrored geometry still renders a plausible flexing bird. Trigger before editing generate.mjs, RepelicanView.swift, KettleView.swift, or before re-deriving the parametric formulas for a mockup, an avatar crop, or an export.
---

# Mascot geometry lives in three copies

`MASCOT.md` names `handoff/mascot/generate.mjs` the source of truth. Two other
copies mirror it and neither is generated from it:

- `handoff/mascot/repelican{,-lean,-athletic,-swole}.svg` (frozen exports)
- `PhaseTraining/Components/RepelicanView.swift` (`Canvas`, hand-ported)

`MASCOT2.md` / `KettleView.swift` have the same shape.

## Verify a fourth copy by string diff, never by eye

Re-deriving the formulas from the three frozen SVGs produced four wrong ones in
one session. All four rendered a bird that looked right at every size. Three
were sign errors on the side multiplier `s`, which mirrors cleanly and so
survives inspection.

Regenerate and compare to the frozen exports as strings, at all three builds:

```js
m.inner(0.55).includes('cx="54.32" cy="155.52" r="17.35"')   // athletic bicep bump
m.inner(1).includes('M 25.5 143 q 12.5 -10 25 5')            // swole bicep shading
```

Watch for float formatting (`17.350` vs `17.35`) before concluding a mismatch.

## The formulas the SVGs actually encode

`generate.mjs` gives most of these directly. These four are the ones that are
easy to get backwards, with `s = -1` left / `+1` right and `b` the bulk scalar:

| thing | value |
|---|---|
| bicep bump centre | `el.x - s*0.3*limb`, `el.y - 0.2*limb`, r = `bicep`. **Inboard** of the elbow on both sides |
| bicep shading arc | starts `el.x + s*0.5*bicep`, `el.y - 0.6*bicep` (**outboard**), then `q -s*0.5*bicep, -0.4*bicep, -s*bicep, +0.2*bicep` |
| pec arcs (b > 0) | from `cx ∓ bodyRX*0.5` at y176, `q ±bodyRX*0.5, 10+10b, 0, 26+10b` |
| swole energy ticks | `gx = cx + s*(bodyRX+limb+30)`; line 1 `gx → gx+s*10` at y126; line 2 `gx-s*2 → gx+s*12` at y140 (line 2 does **not** follow `s` the same way) |

## The head does not vary with bulk

The head circle, headband, eyes and bill are byte-identical in all three frozen
exports. Only arms, fists (`r = 10+8b`) and wristbands (`r = limb+1`) respond.
Any avatar crop tighter than the fists shows zero phase signal, so binding it to
`RepelicanPhysique.bulk(phase:...)` would be dead wiring.

## Kettle: the frozen still is the PEAK frame, not the rest frame

`handoff/mascot2/kettle-flex.svg` is `drawFlex` evaluated at `flex = 1`, so
diffing a re-derivation against it means generating `flex(1)`, not a rest pose.
Tells that confirm it: energy-tick `opacity="1.00"`, `translate(0 -2.5)`,
elbow dots `r="14"` (`8 + 6f`), bell `rx="44.896" ry="47.84"` (`46*(1-0.024f)`,
`46*(1+0.04f)`), and the open mouth path, which only draws past `flex > 0.62`.

The loop is `flex = 0.5 - 0.5*cos(2π * t/1.1)`. Everything else is linear in it:

| part | at flex = f |
|---|---|
| whole figure | `translate(0, -2.5f)` |
| elbows | `(26, 98-3f)` and `(134, 98-3f)`, dot r = `8+6f` |
| fists | `(50-2f, 80-6f)` and `(110+2f, 80-6f)` |
| energy ticks | `(34-3f,74)→(27-5f,69)` mirrored, opacity `0.25+0.75f` |
| bell | rx `46*(1-0.024f)`, ry `46*(1+0.04f)` |
| mouth | open past `f > 0.62` |

Shoulders `(40,110)`/`(120,110)`, legs `(66,152)→(60,176)` mirrored, arm stroke
8, fist r7 are all fixed.

## Kettle has no bulk axis

`RepelicanPhysique.bulk(phase:...)` has no Kettle equivalent: Kettle's variation
is `KettlePose` (five loops), so anything that binds a Repelican surface to
training phase does not port. `KettlePose.forSport(_:)` is the analogous
binding and keys off sport, changing on a day boundary rather than a phase one.

## PR 53 is closed but Kettle is on main

`KettleView.swift` shipped and renders in `TodayScreen` (147, 156) and
`CompleteScreen` (123). Check the file before trusting the PR state.

## Read the usage rules, not only the geometry

`MASCOT.md` and `MASCOT2.md` both set a **64pt floor on live surfaces** and ban
the mascot from scrolling list rows. Those rules live only in the markdown; the
geometry sources say nothing about size, so anyone working from `generate.mjs`
or the Swift view will miss them. Three rounds of coach-button mockups were
drawn at 52pt before anyone noticed they were all out of spec.

Pose silhouette widths, scanned off the frozen `kettle-*.svg` coordinates
(units in the 160-wide viewBox): flex 116, stretch 80, snowboard 130, climb 80,
bike 135. A container normalises that 1.7x spread; without one, swapping pose
changes the rendered footprint by up to 70% in the same slot. Relevant to any
surface that binds `KettlePose.forSport(_:)` and does not draw a frame.
