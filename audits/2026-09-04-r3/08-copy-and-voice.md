# R3 · 08 Copy and voice

Six user-visible strings entered the app in this range. Register reference is
T3-5's closed decision: Kettle is decoration, the terse coach voice is the
app's voice.

## F1 (medium) — "unlock" is paywall language on a screen that is not a paywall

`WorkoutGenerator.swift:94-95`:

> No Mountain Biking routine fits your equipment and injuries yet. Add gear in
> Profile to unlock the authored sessions.

Three problems, in order of how much they cost the user:

1. **"unlock" appears nowhere else in the app** (grep across
   `PhaseTraining/**/*.swift` returns this line only). In an app that ships a
   paywall, "unlock" is the word a user reads as "pay". The thing actually
   gating them is a checkbox they already own.
2. **"gear" is not what the control is called.** The Profile row is
   `SettingsRow(label: "Equipment")` (`ProfileScreen.swift:164`) opening a sheet
   titled "Equipment" (`EquipmentEditorSheet.swift:77`). Copy that sends someone
   to a named control should use its name.
3. **Two sentences where the register is a fragment.** The neighbouring summary
   strings read "5 movements · ~20 min · bodyweight" (`Planner.swift:551`).

Suggested: `No Mountain Biking session fits your equipment and injuries yet ·
update Equipment in Profile`. Keeps the honest refusal R2-05 chose, drops the
purchase implication, names the real control.

## F2 (info) — the swap note is in register and reads correctly

`Swapped in for Barbell Back Squat (no barbell, squat rack)` composes with the
existing load hint through the same " · " join, so a swapped row with a prior
best reads `Swapped in for X (no barbell) · target 135 lb`. Terse, factual,
and it answers the question a user would actually ask, which is why the session
does not match the program name. No change wanted.

## F3 (low) — "Off-season sample" carries no sport

The wheel option's title is `"\(season.label) sample"` with the sport in the
subtitle. On a wheel that otherwise lists the user's own saved workouts, three
entries reading "Off-season sample", "Pre-season sample", "In-season sample"
are only distinguishable by subtitle. Fine while a single primary sport drives
the list; revisit if samples ever span sports.

## F4 (pass) — house style

No em or en dash entered any new string this range (grep over the added `+`
lines for `—`/`–` inside quotes returns nothing). No "X, not Y" apposition, no
"silently".
