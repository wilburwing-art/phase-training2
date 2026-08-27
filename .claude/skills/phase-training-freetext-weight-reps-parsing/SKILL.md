---
name: phase-training-freetext-weight-reps-parsing
description: The phase-training-family iOS apps store LoggedSet.weight/reps as free-text Strings (TextField bindings), and naive Double(set.weight)/Int(set.reps) parsing has four traps that silently lose data, 10x-inflate metrics, or crash. Trigger when editing weight/reps parsing, volume/PR/1RM math, or the Coach's strength context in phase-training / phase-training2 / workout-plan, or when an audit flags "Double(set.weight) drops data" or "false PRs". Skip for apps that store weight/reps as numbers.
when-to-use: Touching LoggedSet weight/reps parsing, volume/PR/strength math, or fixing an audit finding about dropped sets or false PRs in a phase-training-family app.
---

# phase-training free-text weight/reps parsing traps

`LoggedSet.weight` and `.reps` are free-text `String` (raw TextField input). Four traps, all confirmed real here (ultrareview flagged 1–3 as regressions, 4 as a desync):

1. **`Double(set.weight)` / `Int(set.reps)` reject real inputs.** They return nil on `" 135"` (padding), `"135 "`, `"60kg"` (unit), `"1,250"` (comma), `"BW"`. Code using `?? 0` then drops the set from volume/trends or treats it as 0 weight. `Double("+25")` *does* parse — don't "fix" that. Fix: a tolerant `LoggedSet.weightValue: Double?` / `repsValue: Int?` (trim, strip leading `+`, take the leading numeric run). Apply at ALL sites — it was 7 here: ProgressScreen volume+sparkline, MuscleVolume, StrengthStandards, SessionStore PRs, GeneratorContext ×2.

2. **Blanket comma-strip 10×s EU decimals.** iOS `.decimalPad` on de_DE/fr_FR keypads emits `,` as the decimal separator, so `"60,5"` = 60.5. Stripping all commas → `605`. Fix: lone comma → decimal (`replace "," with "."`); both `,` and `.` present → `,` is thousands (strip it). The US-thousands case (`"1,250"`) is paste/import-only and rare; the EU-decimal case is an entire continent's normal logging.

3. **`repsValue` via trapping `Int(Double)` crashes.** A stuck key / paste / bad CSV makes a 20+digit reps string → `~1e22` → `Int(Double)` *traps* inside the getter (the `?? 0` can't save it), and it persists → crash loop on every read path. Fix: `Int(exactly: $0.rounded())` → nil out of range.

4. **Permissive Swift parser desyncs from the strict SQL PR baseline → false PRs.** `personalRecords(in:)` parses the live session with `weightValue`/`repsValue`, but compares against `UserDatabase.bestWeightsByExerciseAndReps()` which uses `CAST(weight AS REAL)` + `reps GLOB '[0-9]*' AND NOT GLOB '*[^0-9]*'`. A historical `"1,250"` or `"8-10"` parses differently on each side → spurious PR every save. Fix: align the SQL to the parser — `CAST(REPLACE(ss.weight, ',', '.') AS REAL)` and drop the `NOT GLOB` clause (leading-digit only, so `"8-10"`→8 matches). Do it in BOTH `qualifyingSetsForPRs` and `bestWeightsByExerciseAndReps` so the Complete-screen and Progress PR surfaces agree.

Verify: unit-test the parser (`" 135"`, `"60,5"`, `"1,250.5"`, 23-digit reps → nil) and re-run SessionStorePRTests + MuscleVolume/StrengthStandards/GeneratorContext. Related: [[catalog-messy-diagnose-before-cleanup]], [[ios-audit-finding-false-positives]].
