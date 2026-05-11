# Handoff: PhaseTraining — Daily Training Log (Thin Vertical Slice)

## Overview

A workout logging app for strength training. This handoff covers the **thin vertical slice** — the minimum daily loop a user needs to log workouts, see previous data, and track progress over time.

The slice is 4 screens: **Start → Log → Complete → History**. Everything else (coach, progress charts, onboarding, settings) is iteration after this loop is validated.

## About the Design Files

The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, not production code to copy directly. The task is to **recreate these designs in the target codebase's existing environment** (Swift/SwiftUI for iOS, Kotlin/Jetpack Compose for Android, React Native, etc.) using its established patterns and libraries — or, if no environment exists yet, to choose the most appropriate framework and implement the designs there.

The working prototype (`Prototype.html` + `proto/` folder) is a fully functional reference that demonstrates real interactions — inputs, timers, state persistence, navigation. Use it to understand *behavior*, not as a code template.

## Fidelity

**High-fidelity.** These are pixel-accurate mockups with final colors, typography, spacing, and interactions. The developer should recreate the UI faithfully using the target platform's native components.

---

## Screens / Views

### 1. Session Start

**Purpose:** Show today's planned workout. User confirms and begins.

**Layout:**
- Full-screen, dark background (`#0A0B0D`)
- Top bar: date (left), duration/exercise/set count (right)
- Divider line below top bar
- Hero title: workout name, large display font, 2 lines
- Subtitle: category + week number
- Last session card: rounded card (`border-radius: 12px`) with previous session summary (days ago, duration, sets, avg RPE)
- Exercise list: numbered rows (01–06), each with exercise name, type in parentheses, set/weight/rep summary
- Bottom: full-width primary CTA button "Start workout" with chevron icon, positioned 46px from bottom

**Components:**
- **Top bar:** `MICRO` label style on both sides
- **Hero title:** Space Grotesk 34px/600/−0.03em tracking, line-height 1.0
- **Subtitle:** Inter 13px, `ink2` color (#B5B7BD)
- **Last session card:** `surface` bg (#14161A), 0.5px `line` border (#2A2E35), 12px border-radius
- **Exercise rows:** 13px padding vertical, 0.5px soft divider between rows. Row number in JetBrains Mono 11px right-aligned, exercise name in Space Grotesk 15px/600, type label in 11px `ink3`, detail in JetBrains Mono 11px `ink3`
- **CTA button:** `accent` bg (#D4FF3D), `accentInk` text (#0A0B0D), Inter 15px/700, 16px padding, 14px border-radius, full width

**Behavior:**
- Tapping "Start workout" creates a new session from the template, saves to localStorage, navigates to Log screen
- "History" button (top right) navigates to History screen
- If an active session exists in localStorage, skip this screen and go directly to Log

---

### 2. Training Log (Core Screen)

**Purpose:** Log all exercises and sets for the current workout on one scrollable page. This is the screen users spend 95% of their time on.

**Layout:**
- Sticky header: close button (X), elapsed timer (running), "Finish" button, progress bar
- Scrollable body: workout title, then exercise blocks stacked vertically with dividers between
- Each exercise block: header → column headers → set rows → "+ Add Set"
- Bottom padding for safe area

**Sticky Header:**
- Height: ~60px including progress bar
- Left: X icon (18px) + elapsed timer in JetBrains Mono 17px/500, tabular-nums
- Right: "Finish" button — accent bg, 8px 20px padding, 10px border-radius, Inter 13px/700
- Progress bar: 3px tall, `lineSoft` bg (#1F2229), accent fill, width = (done sets / total sets) × 100%. Segment dividers (1px `bg` colored) at each exercise boundary.
- Timer updates every second: `H:MM:SS` format

**Workout Title:**
- Space Grotesk 24px/600, −0.03em tracking
- Below: Inter 12px `ink3` with exercise count + sets logged

**Exercise Block:**
- **Header row:** Exercise name (Space Grotesk 16px/600, −0.02em), type in parentheses (11px `ink3`), flex spacer, ••• menu button (14px icon, 0.5px border, 8px border-radius)
- **Completed exercise:** green check circle (18px, `rgba(107,232,154,0.15)` bg) before name, name color dimmed to `ink2`
- **Column headers:** Grid `22px 58px 1fr 1fr 34px 24px`, gap 4px. Labels: SET, PREV, [UNIT], REPS, RPE. All in `MICRO` style (JetBrains Mono 9px uppercase, `ink3`)
- **Set rows:** Same grid. 6px vertical padding.
  - Set number: JetBrains Mono 11px, center
  - Previous: JetBrains Mono 10.5px `ink3`, format "135×5" or "—"
  - Weight/Reps/RPE inputs: JetBrains Mono 13.5px/500, tabular-nums. Undone: `elevated` bg (#1C1F24), 0.5px `line` border, 7px border-radius. Done: flat text, no bg/border, `ink2` color
  - Check circle: 22px diameter. Undone: 1.5px `line` border. Done: `ok` fill (#6BE89A), dark checkmark
- **Active set** (first undone): 2px accent left border extending past padding. Input borders use `accentBorder` (rgba(212,255,61,0.30)), input bg uses subtle accent wash
- **Rest dividers** between completed sets: centered time label (JetBrains Mono 10px `accentDim` #8FA82A) with 0.5px `lineSoft` lines extending left and right
- **Active rest timer card:** Appears between last completed set and next pending set. `accentWash` bg, `accentBorder` border, 12px border-radius. Contains: pulsing dot (7px, accent, 1.6s ease-in-out infinite opacity animation), "REST" micro label in accent, timer readout (JetBrains Mono 22px/600 accent), +15 and skip chip buttons
- **+ Add Set:** centered text, 12px Inter `ink3`, 8px padding, shows rest time in parens

**Behavior:**
- Weight/reps/RPE are text inputs with `inputMode="decimal"` for mobile number pad
- Tapping check circle marks set as done. If not last set, starts rest timer counting down from exercise rest time
- Rest timer counts down every second. +15 adds 15 seconds. Skip clears it. Timer auto-clears at 0.
- "+ Add Set" appends a new set row, copying weight/reps from last set
- All changes auto-save to localStorage (`pt_active_session` key)
- "Finish" navigates to Complete screen
- Elapsed timer: `Date.now() - session.startTime`, updated every second

---

### 3. Session Complete

**Purpose:** Post-workout summary. User reviews, rates feel, saves.

**Layout:**
- Top bar: "SESSION COMPLETE" micro label (left), date (right), full accent progress bar
- "Done." hero title (Space Grotesk 34px/600)
- Session name subtitle
- 3-column stat grid: Duration, Sets, Avg RPE
- PR ribbon (if any PRs detected): accent wash card with spark icon, PR chips
- Exercise summary list: name, set details, RPE range
- "How did it feel?" — 5 selectable chips: Too easy / Easy / Right / Hard / Too much
- Optional note textarea
- "Save session" primary CTA at bottom

**PR Detection:**
- Compare max weight per exercise to previous session's max weight
- If current > previous, it's a PR. Show in accent chip: "BENCH +20 LB TOP SET"

**Stat Grid:**
- 3 columns, 8px gap, each: `surface` bg, `line` border, 12px radius
- Label: MICRO 9px, value: Space Grotesk 26px/600

**Feel Chips:**
- 5 equal-flex items, 10px vertical padding, selectable (one active at a time)
- Active: accent bg/ink. Inactive: elevated bg, ink2 text

**Behavior:**
- "Save session" serializes session data (exercises with done sets: weight, reps, rpe), timestamp, duration, feel, note → pushes to `pt_sessions` localStorage array, clears `pt_active_session`, navigates to Start

---

### 4. History

**Purpose:** View past sessions. This makes the "Previous" column in the Log screen meaningful.

**Layout:**
- Top bar: back arrow + "HISTORY" label, session count
- "Past sessions" title
- 3-column summary strip: Sessions count, Total sets, Avg RPE
- Session list: each row expandable with chevron

**Session Row (collapsed):**
- Name: Space Grotesk 16px/600
- Meta: date · duration · sets · rpe (JetBrains Mono 11px `ink3`)
- Chevron rotates on expand

**Session Row (expanded):**
- Detail card: `surface` bg, `line` border, 10px radius
- Each exercise: name (13px/500) + RPE range right-aligned, set data below (JetBrains Mono 11px `ink2` "135×5 · 145×5 · 155×5")

**Behavior:**
- Reads from `pt_sessions` localStorage
- One session expanded at a time (accordion)
- Back arrow returns to Start screen
- Empty state: history icon + "No sessions yet" + helpful text

---

## Data Model

### Workout Template
```
{
  id: string,
  name: string,
  category: string,
  exercises: [{
    id: string,
    name: string,
    type: string | null,       // "Barbell", "Dumbbell", "Cable", null
    unit: string,              // "lbs", "+lbs"
    targetSets: number,
    targetReps: number,
    rest: number,              // seconds
  }]
}
```

### Active Session (in-progress)
```
{
  templateId: string,
  name: string,
  category: string,
  startTime: number,           // Date.now()
  endTime: number | null,
  exercises: [{
    ...template exercise fields,
    sets: [{
      num: number,
      weight: string,
      reps: string,
      rpe: string,
      done: boolean,
    }],
    prevSets: [{               // from last completed session
      weight: number,
      reps: number,
      rpe: number,
    }],
  }]
}
```

### Saved Session (history)
```
{
  templateId: string,
  name: string,
  timestamp: number,
  duration: string,            // "0:42:08"
  feel: string | null,         // "Too easy" | "Easy" | "Right" | "Hard" | "Too much"
  note: string,
  stats: { totalSets, doneSets, avgRpe },
  exercises: [{
    id: string,
    name: string,
    sets: [{ weight: number, reps: number, rpe: number }],
  }]
}
```

### localStorage Keys
- `pt_active_session` — current in-progress session (cleared on save)
- `pt_sessions` — array of completed sessions, newest first

---

## Design Tokens

### Colors
| Token | Hex | Usage |
|-------|-----|-------|
| `bg` | `#0A0B0D` | App background |
| `surface` | `#14161A` | Card/input backgrounds |
| `elevated` | `#1C1F24` | Elevated cards, input fields |
| `line` | `#2A2E35` | Borders, dividers |
| `lineSoft` | `#1F2229` | Subtle dividers |
| `ink` | `#F5F5F0` | Primary text |
| `ink2` | `#B5B7BD` | Secondary text |
| `ink3` | `#7A7D85` | Tertiary text, labels |
| `accent` | `#D4FF3D` | Primary accent (electric lime) |
| `accentInk` | `#0A0B0D` | Text on accent backgrounds |
| `accentDim` | `#8FA82A` | Dimmed accent (rest time labels) |
| `accentWash` | `rgba(212,255,61,0.04)` | Subtle accent background |
| `accentBorder` | `rgba(212,255,61,0.30)` | Accent border |
| `ok` | `#6BE89A` | Success, done state |
| `danger` | `#FF6B4A` | Error, danger |

### Typography
| Style | Font | Size | Weight | Tracking | Usage |
|-------|------|------|--------|----------|-------|
| Display L | Space Grotesk | 34px | 600 | −0.03em | Hero titles |
| Display M | Space Grotesk | 26px | 600 | −0.03em | Section titles |
| Display S | Space Grotesk | 16px | 600 | −0.02em | Exercise names |
| Body | Inter | 13px | 400 | — | Body text |
| Mono L | JetBrains Mono | 22px | 600 | −0.02em | Timer readouts |
| Mono M | JetBrains Mono | 17px | 500 | — | Elapsed timer |
| Mono S | JetBrains Mono | 13.5px | 500 | — | Set values, inputs |
| Mono XS | JetBrains Mono | 11px | 400 | — | Previous data, metadata |
| Micro | JetBrains Mono | 10px | 500 | 0.14em | Uppercase labels |

### Spacing
- Page padding: 20px horizontal
- Section gap: 16–20px
- Card padding: 12–14px
- Set row padding: 6px vertical
- Grid gap (set columns): 4px
- Border radius: 7px (inputs), 8px (icon buttons), 10–12px (cards), 14px (buttons, large cards), 44px (device frame)

### Borders
- Standard: `0.5px solid #2A2E35`
- Soft: `0.5px solid #1F2229`
- Accent: `0.5px solid rgba(212,255,61,0.30)`
- Dashed: `0.5px dashed #2A2E35` (add exercise)

---

## Interactions & Behavior

### Navigation Flow
```
Start → [Start Workout] → Log → [Finish] → Complete → [Save] → Start
Start → [History] → History → [Back] → Start
```

### Session Persistence
- Active session saves to localStorage on every change (set value edit, set completion, add set)
- On app launch, check for active session. If exists, go directly to Log screen and resume
- On "Save session," write to history array, clear active session

### Rest Timer
- Triggered when a set is marked done (not on last set of exercise)
- Counts down from exercise's `rest` value (in seconds)
- +15 button adds 15 seconds to remaining
- Skip button clears timer immediately
- Timer auto-clears when it reaches 0
- Visual: pulsing dot animation (opacity 1→0.35→1, 1.6s ease-in-out infinite)

### Set Completion
- Tap check circle to toggle done/undone
- On marking done: rest timer starts (if not last set), set values lock (display as flat text)
- On marking undone: values become editable again

### Input Fields
- `inputMode="decimal"` on mobile for numeric keypad
- No validation on input — user types freely. Values saved as strings.
- Pre-filled with previous session data when available (weight from matching set number)

### Progress Bar
- Width = (completed sets / total sets) × 100%
- Segment dividers at each exercise boundary (evenly spaced for N exercises)
- Smooth transition on width change (0.3s ease)

---

## Files

### Design References (static mockups)
- `Vertical Slice.html` — All 4 screens side-by-side with tab navigation
- `Training Log.html` — Standalone training log mockup in phone frame
- `hd-training-log.jsx` — Training log component (static)
- `hd-session-start.jsx` — Start screen (static)
- `hd-session-complete.jsx` — Complete screen (static)
- `hd-history.jsx` — History screen (static)
- `hd-style.jsx` — Design system tokens and shared components

### Working Prototype
- `Prototype.html` — Entry point
- `proto/data.jsx` — Data layer, localStorage, session management
- `proto/ui.jsx` — Shared UI components (icons, inputs, buttons, chips)
- `proto/start.jsx` — Start screen
- `proto/log.jsx` — Training log (core screen)
- `proto/complete.jsx` — Complete screen
- `proto/history.jsx` — History screen
- `proto/app.jsx` — App shell with navigation
