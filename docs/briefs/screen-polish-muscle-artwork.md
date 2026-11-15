# Brief: screen polish follow-up, the muscle artwork shows no muscle

Backlog item: `docs/PLAN-gap-backlog-2026-11b.md`, "Later, not scheduled": "Screen polish from `screens.md`: Week header stack, Library muscle icons, Profile 23-row list, Log tab bar under the music card." This is the one follow-up to `docs/briefs/screen-polish-profile-library.md`, Part 2. The Week, Log and Profile parts passed review and are not to be touched.

Agent: builder. Skills to load first: `phase-training2-gitignored-pbxproj`, `phase-training-xcodebuild-test-failed-grep-full-log`.

Slot A. Every `xcodebuild` call passes both:

```
-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'
-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A
```

No other agent is running. The working tree already holds the uncommitted screen-polish changes from the two earlier briefs; build on top of them and leave them as they are. `ROADMAP.md` is also modified and is unrelated: do not touch it.

## Problem

The Library tiles now draw `MuscleFigure` at 56pt, and every front-facing tile (Chest, Shoulders, Arms, Quads, Core) shows the same solid lime body. The two back-facing tiles (Back, Hams + Glutes) match each other too.

Cause, measured 2026-11-14: the bundled images under `PhaseTraining/Resources/Assets.xcassets/MuscleChips/` carry no highlight. `chest-front@3x.png`, `shoulders-front@3x.png`, `biceps-front@3x.png`, `quads-front@3x.png` and `core-front@3x.png` have the same alpha histogram (58,969 pixels at alpha 255, 82.9% of the drawn pixels opaque). `MuscleChipGeneratorView` renders `BodyAnatomyView` with the highlight tinted black, and MuscleMap fills the rest of the body with an opaque grey (`BodyViewStyle.defaultFillColor`, `headColor`, `hairColor`). The imagesets are template images, so only alpha survives and the grey body comes out as solid as the highlighted muscle. The same images sit on Today's 28pt `MuscleChipBadge`, where the fault was too small to see.

## Design

**`BodyAnatomyView`.** Add `var baseOpacity: Double? = nil`. When it is set and `tint` is set, `buildBodyView` applies `.bodyStyle(BodyViewStyle(defaultFillColor:headColor:hairColor:))` with all three set to `tint.opacity(baseOpacity)`, leaving the other style fields at their defaults. When it is nil nothing changes, so the recovery views and `ExerciseTile` render as they do today. MuscleMap 1.6.4 source is at `build/DerivedData/SourcePackages/checkouts/MuscleMap/Sources/MuscleMap/Views/` (`BodyView.swift:456` for `bodyStyle`, `BodyViewStyle.swift` for the fields); read it to confirm modifier order does not matter.

**One constant.** `MuscleFigure.baseOpacity: Double = 0.3` in `MuscleChipBadge.swift`. The generator's `chipArtwork` and the `MuscleFigure` fallback branch both pass it, so a missing imageset and a bundled one look the same.

**Regenerate the 22 imagesets.** Build and install on slot A, launch with `--ui-test-onboarded --regenerate-muscle-chips`, wait for 66 PNGs in the app's `Documents/MuscleChips`, then run `SIM_UDID=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2 scripts/install_muscle_chips.sh`. The script deletes and rebuilds the catalog folder; the folder is tracked in git, so `git status` afterwards should show the 66 PNGs modified and nothing added or deleted. Rebuild the app after installing.

**Look at the result at both sizes.** The Library tiles at 56pt and a Today row's badge at 28pt. The highlighted muscle must be the first thing the eye lands on and the rest of the body must still read as a body. If 0.3 fails either test, try values between 0.2 and 0.4, regenerate, and report the value you kept and why.

**Comments.** The header comment of `MuscleChipBadge.swift` already describes the intended artwork (primary muscle opaque, body at partial alpha); make sure it and the generator's header match what the code now does.

## Tests

In `LibraryTileInvariantTests`:

- `test_tileFiguresAreDistinct`: the seven tiles' bundled images, as `pngData()`, are pairwise different.
- `test_tileFigureHighlightIsAMinorityOfTheBody`: for each tile's image, among pixels with alpha above 0, fewer than half have alpha 250 or higher. (Today's images sit at 83%.) Read the alpha channel from the `CGImage`; keep the helper private to the test file.

Both must fail against the images in git today. Confirm that by running the class once before regenerating, and say so in the report.

Run, one class at a time: `PhaseTrainingTests/LibraryTileInvariantTests`, `PhaseTrainingUITests/ImageSlotScalingUITests`, `PhaseTrainingUITests/StoreScreenshotUITests/test_planScreens` (it attaches Today and Library; an earlier run of it failed once at line 31 waiting for "Ab Wheel Rollout" and passed on the next run, so if it fails the same way run it once more and report both results).

## Out of scope

The tile layout, `LibraryTile.figureBucket`, the recovery body, `ExerciseTile`, new buckets, any change to which muscle a bucket highlights (`MuscleBucket.primarySlug`), the Week, Log and Profile changes.

## Done

- App target builds on slot A with the regenerated assets.
- The three test targets above pass; the two new tests failed before the regeneration.
- Screenshots after the change, saved under `/private/tmp/claude-501/-Users-wilburpyn-repos-phase-training2/3a4c6a4e-36d9-496c-acc6-7b0d7bb1a0dd/scratchpad/muscle-artwork/` with full paths in the report: the Library tab, and Today with at least one row badge visible.
- The report states the `baseOpacity` kept and the opaque-pixel share of `chest-front@3x.png` after regeneration.

Do not commit, push or bump the build. Return one final report and send no interim messages: files changed, test classes run with pass and fail counts, decisions made on anything this brief left open, and anything you noticed outside its scope. If something here is ambiguous, take the conservative option, record it, and keep going.
