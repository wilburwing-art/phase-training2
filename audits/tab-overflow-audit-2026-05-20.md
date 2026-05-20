# Tab Overflow Audit — 2026-05-20

Snapshot taken after `5d97d9d week: GeometryReader-fit 7 rows in viewport`. Looking for the same class of bug across the other three tabs:

- (a) Stacked `.safeAreaInset(.bottom, N)` inside a `TabView` child — the gotcha that bit WeekScreen (native tab-bar inset + manual inset = double padding eating ~60pt of viewport).
- (b) Hand-tuned vertical paddings/spacers that assume iPhone 14+ heights.
- (c) Multi-line row content where one line + truncation would do.

## Codebase-wide check first

`grep -rn "safeAreaInset" PhaseTraining/` returns **zero hits**. The WeekScreen fix removed the last occurrence in the project. Class (a) is currently absent across the app — no other tab is at risk of the double-inset bug today.

The remaining audit covers (b) and (c) per screen.

---

## TodayScreen.swift

**Severity: low.**

### (b) Hand-tuned paddings

- Line 212: `Spacer().frame(height: 160)` reserves vertical space at the bottom of the ScrollView so the floating CTA in the ZStack-overlay doesn't cover the last content row. 160pt is a magic number that adds up to roughly: `bottom CTA height (~48pt) + .padding(.bottom, 24) + tab bar (~83pt)` ≈ 155pt. On an iPhone SE (3rd gen, 4.7") the tab bar is shorter (~49pt), so 160 is over-reserved — content shows a too-large gap. On iPhone 14+ it lands right.
  - Recommended fix: replace the literal 160 with a computed value: read the safe-area bottom via a `GeometryReader` at the `body` level, or hoist the bottom CTA into the navigation layer so SwiftUI accounts for it automatically. Lower-effort: cut to 140 and accept the small dirty-window on Pro Max heights.
- Line 188: `.padding(.top, planEndingSoon ? 14 : 24)` — fine, two-value conditional.
- Line 225: `.padding(.bottom, 24)` on the bottom-CTA VStack is hand-tuned but small and intentional.

### (c) Multi-line content

- Line 115: `heroTitle` injects `\n` between word and "Day" to force a line break (`"Upper Body Day 1"` → `"Upper Body\nDay 1"`). This is a layout-by-string-mutation pattern that survives because `displayL` font is sized to fit. If `category` exceeds one short word the title will wrap unevenly. Low risk today; flag if a future category name ever exceeds ~14 chars.
- Line 461: exercise name `.lineLimit(2)` in the inline row. Two lines is justified for "Single-Arm Dumbbell Bench Press" etc.; not a candidate for tightening.
- Line 502 on heroCaptionView: `.fixedSize(horizontal: false, vertical: true)` lets the caption grow vertically. Acceptable — captions are short.

### Verdict

No urgent fixes. The Spacer(160) is the one item worth watching; only manifests as wasted whitespace on the smallest iPhones, not an overflow. **Not a Week-class bug.**

---

## ProgressScreen.swift

**Severity: low.**

### (a) Confirmed absent — no `safeAreaInset` use.

### (b) Hand-tuned paddings

- Line 81: `Spacer().frame(height: 60)` at the bottom of the content ScrollView — relies on the native TabView inset. 60pt is conservative; tab bar height is ~83pt with home-indicator safe area, so the bottom-most card (`recentSessionsCard`) clears the tab bar but not by much. On iPhone SE that 60pt is roughly tab-bar-height, which is fine.
- Line 84: `.padding(.top, 24)` — fine.
- Several cards stack at `spacing: 24` (line 70) — generous but not problematic; ScrollView absorbs it.

### (c) Multi-line content

- Line 502 (feedback rows): `.lineLimit(2)` on the feedback notes — justified. Single line would truncate the most useful field.
- Line 380, 429, 591: exercise-name / PR-name / session-name rows all `.lineLimit(1)`. Already tightened. Good.
- Stat strip (line 112): 4-cell HStack at `spacing: 8`. On iPhone SE width with 20pt horizontal padding × 2 = 40, available width is ~335pt. Each cell value is `SpaceGrotesk-SemiBold 26` (~16-22pt wide per digit). 4-digit values like "1234" in the TOTAL cell will fit, but the cells use `.frame(maxWidth: .infinity, alignment: .leading)` so single-digit values look airy. Cosmetic, not overflow.

### Verdict

No fixes needed. ProgressScreen is mostly cards in a ScrollView — content overflows by design, and there's no fixed-row geometry that can't shrink.

---

## ProfileScreen.swift

**Severity: low.**

### (a) Confirmed absent — no `safeAreaInset` use.

### (b) Hand-tuned paddings

- Line 141: `Spacer().frame(height: 40)` at the bottom — same pattern as ProgressScreen, relies on tab bar inset. 40pt is even tighter than Progress's 60pt; on iPhone 17 the home indicator + tab bar consume more than 40pt, but the native TabView already inserts its inset under the ScrollView, so the 40pt is on top of that. Safe.
- Line 76: `spacing: 28` on the outer VStack — generous, not problematic.
- Multiple `.padding(.vertical, 10)` and `.padding(.horizontal, 12)` on tuning rows (line 313–314) and `.padding(14)` on cards — consistent 10–14pt rhythm, no outliers.

### (c) Multi-line content

- Line 286: `tuningRow` rationale lines use `.fixedSize(horizontal: false, vertical: true)` — multi-line rationale is the point of the section. Acceptable.
- All row summaries (`sportsSummary`, `seasonsSummary`, etc., lines 340–425) return short strings designed to fit one line. No `.lineLimit` set on `SettingsRow` value cells — if a summary were ever to overflow it would wrap. Worth verifying the `SettingsRow` view file (not opened in this audit) clamps to one line. **Action item: spot-check `PhaseTraining/Components/SettingsRow.swift` for a value `.lineLimit(1)` constraint.**
- `tuningRow.actualHint` (line 304): rendered as `.styled(.micro)`, uppercase — single-line by content shape, not enforced. Safe in practice.

### Verdict

One follow-up: confirm `SettingsRow` clamps its value cell to one line. Otherwise no fixes.

---

## Cross-cutting recommendations

1. **No Week-class overflow bug elsewhere.** The audit found zero stacked `safeAreaInset` calls. The WeekScreen fix removed the last instance and nothing else is at risk of that class.
2. **The "bottom-spacer" idiom is consistent.** Today uses 160 (because of its floating CTA overlay), Progress uses 60, Profile uses 40 — each tuned to that screen's bottom-CTA situation. Today's 160 is the only over-reserved one and only wastes whitespace on SE/mini.
3. **Single follow-up worth doing:** verify `SettingsRow.swift` enforces `.lineLimit(1)` on its value cell. If not, a long-tailed summary string could push a row to two lines and add cumulative drift on Profile.

## Verification

This audit was research-only; no Swift files were modified. To verify findings, build + visual-inspect each tab on an iPhone SE simulator alongside an iPhone 17 simulator — the difference in bottom-spacer behavior is the only delta likely to surface.
