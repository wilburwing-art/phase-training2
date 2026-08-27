---
name: phase-training-localize-label-coach-prompt-coupling
description: >
  Localizing phase-training / phase-training2: the String-typed enum `.label`
  vars you'd wrap in String(localized:) are the SAME vars CoachContext feeds
  into the LLM prompt, so wrapping them makes the coach prompt
  translation-sensitive. Wrap prompt-free UI labels now; gate the
  Coach-consumed ones behind a prompt-decouple. Also the headless String
  Catalog extraction recipe under XcodeGen. Trigger when adding localization /
  String Catalog / .xcstrings / "make it translatable" to a phase-training-family
  iOS app, or wrapping enum `.label` in String(localized:). Skip for non-l10n work.
---

# Localizing phase-training: labels are coupled to the Coach prompt

Verified on phase-training2 (2026-06-08, commits `f018fc2`→`9b8ef54`).

## The trap
The ~108 enum `.label` computed vars (`DayKind`, `Focus`, `Experience`,
`Gender`, `Equipment`, `StartingState`, `SeasonPhase`, `EventIntensity`,
`StrengthTier`, `BigLift`, `Screen`) are String-typed, so `Text(x.label)` does
NOT auto-extract — you must wrap them. **But `CoachContext` (and its
`+ProfileBlocks`/`+MovementBlocks` split files) consumes those same `.label`
vars to build the Claude prompt.** Wrap them in `String(localized:)` and the
prompt becomes language-dependent — violating "never localize LLM prompts".

English-only subtlety: with NO translations in the catalog, `String(localized:)`
returns the English base in every locale, so wrapping is harmless TODAY. The
breakage only lands when someone adds a non-English translation.

## The rule
- Before wrapping any `.label`, grep `PhaseTraining/Coach/` for `.label` consumers.
- **Prompt-free labels** (MuscleBucket/MuscleDivision/MovementPattern in
  ExerciseFilters, LibraryScreen.Segment, ExerciseDetailSheet.Difficulty,
  CoachRequestScreen.FocusPreset) + check-in tuple display halves (intentChips,
  ratings, soreness energy/severity) → wrap now. (`weeklyCheckIns`/`.intent` is
  NOT prompt-consumed — verify, then the tuples are safe.)
- **Coach-consumed labels** → DEFER. Gate: before localizing them OR shipping
  any translation, give the prompt a stable source (`.rawValue`, or a
  `promptLabel`). Wrap the display half of tuples only; never the slug.
- Never touch: `rawValue`/slug props (ExerciseFilters has a slug prop AND an SF
  Symbol prop next to `label` — don't wrap those), `pt_*` keys, accessibilityId,
  CoachSystemPrompt.swift, coach.db names.

## Headless String Catalog recipe (XcodeGen, no Xcode GUI)
- Seed `PhaseTraining/Resources/Localizable.xcstrings` = `{"sourceLanguage":"en","strings":{},"version":"1.0"}`.
  XcodeGen 2.44 auto-classifies `.xcstrings` as a resource (no `sources:` change);
  `.xcodeproj` is gitignored so Project.yml is the source of truth.
- Project.yml app-target `settings.base`: `SWIFT_EMIT_LOC_STRINGS: YES` +
  `LOCALIZATION_PREFERS_STRING_CATALOGS: YES` (app target only, not tests).
- `xcodegen generate`, then `xcodebuild -exportLocalizations -project … -localizationPath build/loc -exportLanguage en CODE_SIGNING_ALLOWED=NO`.
  This BOTH builds with extraction AND auto-syncs the source `.xcstrings`
  (populates it — commit the result). Count: `grep -c '<trans-unit' build/loc/en.xcloc/Localized\ Contents/en.xliff`.
  Gate: sentinels present, `pt_*` keys absent from the XLIFF.
- Bonus (same Project.yml pattern): scheme StoreKit config = `schemes.<S>.run.storeKitConfiguration: X.storekit`.
