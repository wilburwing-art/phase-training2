# Phase 6 — Routine Library (bundled SQLite, 167 routines)

Successor to PLAN.md once Phases 0–5 land. Extends the thin vertical slice with read access to the `phase-training/adaptive-training-coach/coach.db` library: 167 routines, 711 exercises, 1200 routine-exercise mappings.

## Problem

The slice ships a single hardcoded `upper-1` template. The real catalog already exists in `coach.db` next door but has zero presence in the app. Browsing it requires (a) a way to read SQLite from Swift, (b) a list/filter/search UI, (c) a way to pick one as the active routine for the Log screen.

## Definition of done

- coach.db ships inside the app bundle (read-only resource), ~2.5MB.
- Tap "Browse routines" on Start → see all 167 routines, filtered/searched.
- Tap a routine → it becomes the active template; Start screen updates and Log screen logs against it.
- Filter chips honor `goal` and `environment`; search filters by `name`.
- Build green on `xcodegen generate && xcodebuild build`.

## Out of scope

- Exercise Picker / Exercise Detail / Swipe-to-replace from `index.html`. Tracked for Phase 7.
- Editing or creating routines. DB stays read-only.
- Sport-tag filtering, multi-select, A–Z rail, dense-list variation B from the design.
- Migrating UserDefaults-backed session storage to SQLite (sessions stay in UserDefaults).
- Hangboard / weighted-pull style TEXT rep formats inside the Log screen. Logged sets keep current UX; targetReps is just displayed.

## Locked decisions

| Decision | Value | Rationale |
|---|---|---|
| Database strategy | Bundle `coach.db` as a read-only resource | User chose option A in the trade-off. Lets us filter on full metadata (difficulty / phase / environment / sport tags) without re-deriving. |
| SQLite client | System libsqlite3 via `import SQLite3` | Zero dependencies. Query surface is small (2 queries); GRDB ergonomics aren't worth the SPM wiring. |
| coach.db location | `PhaseTraining/Resources/coach.db` | Bundled, not copied to Documents. Opened with `SQLITE_OPEN_READONLY`. |
| Schema mismatch (reps as TEXT) | Widen Swift to `String` | coach.db stores `"8-12"`, `"AMRAP"`, `"7-10 sec"`. Lossless to display; never coerced to Int. |
| Existing `WorkoutTemplate.upper1` | Keep as fallback | Phase 3 already wired against it. Routine→ActiveSession adapter bridges the new shape into the old one. |
| Active routine selection | Same `activeTemplateId` key in UserDefaults | Start screen reads it. Default stays `"upper-1"` until user picks a different one. |
| Picker UI | Variation A from `index.html` (big stat cards) | More scannable than variation B for a list of 167. |
| Sport filter | Deferred | Sport tags exist (`routine_sports` joins to `sport_categories`) but UI complexity isn't worth it for v1. |

## Schema mismatch resolution

| Field | coach.db type | Swift type before | Swift type after |
|---|---|---|---|
| `default_reps` | TEXT (e.g. `"8-12"`, `"AMRAP"`, `"7-10 sec"`) | n/a (new) | `String` |
| `default_sets` | INTEGER | n/a (new) | `Int?` |
| `default_rest` | TEXT (e.g. `"2-3 min"`, `"90 sec"`) | n/a (new) | `String?` |
| `ExerciseTemplate.targetReps` (existing upper-1 path) | n/a | `Int` | **unchanged** |

The new `Routine` / `RoutineExercise` types are independent of the existing `WorkoutTemplate` / `ExerciseTemplate`. They convert into the existing shape via an adapter (`Routine.toWorkoutTemplate()`) when the user activates a routine — Int reps map straight through, TEXT reps land in a new `targetRepsDisplay` field that the Log screen surfaces but doesn't parse.

## Files

### New

- `PhaseTraining/Resources/coach.db` — copied from `~/repos/phase-training/adaptive-training-coach/coach.db`.
- `PhaseTraining/Data/CoachDatabase.swift` — thin libsqlite3 wrapper. Singleton. Opens read-only on first access.
- `PhaseTraining/Data/Routine.swift` — `Routine`, `RoutineExercise` structs + the adapter to `WorkoutTemplate`.
- `PhaseTraining/Screens/RoutinePickerScreen.swift` — SwiftUI port of `routine-picker.jsx` variation A.

### Modified

- `Project.yml` — register `Resources/coach.db` as a copied resource.
- `PhaseTraining/App/ContentView.swift` — add `.routines` route case.
- `PhaseTraining/Screens/StartScreen.swift` — add "Browse routines" button + read active-routine id from `SessionStore`.
- `PhaseTraining/Data/SessionStore.swift` — add `activeTemplateId` published property + persistence.

## Implementation order

1. **Bundle coach.db** — copy file, register in `Project.yml`, regenerate.
2. **CoachDatabase + Routine** — wrapper + models + two queries (`listRoutines(filter:search:)` and `routineDetail(id:)`).
3. **RoutinePickerScreen** — variation A: header, search, filter chips (All / Strength / Power / Endurance / Mobility / Recovery), stat cards (EX / SETS / MIN). Defer sort-toggle, defer star/pin.
4. **Routing + Start hook** — `.routines` case, "Browse routines" entry, active routine id stored in `SessionStore`.
5. **Verify** — `xcodegen generate && xcodebuild build` green. Open `RoutinePickerScreen` in Xcode Preview, scroll the full list, tap one, observe Start updates.

## Verification

```bash
xcodegen generate
xcodebuild -scheme PhaseTraining \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug build | xcbeautify
```

Visual: open `RoutinePickerScreen.swift` `#Preview` in Xcode, confirm:
- 167 rows present (or filtered subset).
- Cards render with split color dot, title, tag line, EX/SETS/MIN tri-stat row.
- Filter chips reactive.
- Tap → returns to Start with the new active routine selected.

## Risks

| Risk | Mitigation |
|---|---|
| coach.db drifts (regenerated upstream) | This bundle is a point-in-time snapshot. Re-copy on demand; document the source path in `Resources/README.md`. |
| Bundle size bloat | 2.5MB is fine. Compressing as `.db.gz` saves ~1MB but adds decompression-on-launch complexity not worth it here. |
| TEXT reps confuse the Log screen | Routines pulled from coach.db with non-numeric reps display the string verbatim; Log screen `TextField` for reps stays editable. No coercion. |
| 711-exercise picker (Phase 7) is the real UX work | Out of scope here. Routines reference exercises by integer id; we fetch only the exercises in the chosen routine. |
