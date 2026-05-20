# Phase 13 — AI Coach (chat layer + LLM wiring)

Successor to PLAN-coach-prereqs.md. Builds the chat surface and tool-calling layer that sits on top of the Phase 8-12 substrate. The coach proposes changes the user can preview and apply; it never silently mutates state.

## Problem

The Phase 8-12 work gave the planner the *substrate* a coach needs — typed plan model, training memory, structured feedback, weekly check-in loop, drift-aware regen. None of it talks. A user with a freshly-shifted goal, a recurring "knee hurt" pattern, or a question like "why did you put squats Thursday?" still has nowhere to direct that.

The coach must:
- Answer plain-English questions about *this user's* plan, recent sessions, and feedback patterns
- Propose plan changes (move/swap/protect/shorten days, swap exercises within a workout) with rationale, gated by a preview the user applies
- Surface insights on Today / Week / post-workout proactively, not just reactively
- Stay cheap (≤ ~$0.05/user/month at expected usage) and fast (first token < 2s)

## Definition of done

After Phase 13e lands, the user can:
1. Tap "ASK COACH" on Today and chat with a streaming Claude response that has full read access to their plan, memory, and recent feedback.
2. Ask the coach to change something ("move Thursday to Friday", "swap squats for goblet squats", "make this week easier"); the coach proposes via the existing PlanDiff / WorkoutDiff preview; the user applies.
3. See coach-written InsightCards on Today and Week explaining *why* something looks the way it does, with a tap-through into the conversation that produced them.
4. Toggle the coach off in Settings; the app keeps working exactly as it does post-Phase 12.

## Out of scope

- Multi-user / shared-team coaching. Solo athlete only.
- Voice input / TTS output. Keyboard chat only. (Tracked in `ROADMAP.md` → "Voice coach check-ins".)
- Cross-device sync of conversations. Local-only history.
- Long-term memory beyond TrainingMemory's existing fields. No separate "facts the coach learned" store this phase — if it learns something durable, it proposes a memory update the user accepts.
- Image input (photos of food, form videos, etc.).
- Anthropic-specific model features beyond text + tool calls (no extended thinking, no MCP, no Files API).

## Locked decisions (defaults — flip in this section before building)

| Decision | Default | Why this default |
|---|---|---|
| **LLM provider** | Anthropic Claude (Sonnet 4.6 default; Haiku 4.5 fallback for short questions) | Best at tool calling + structured edits; coding agent users have keys already. |
| **Key flow** | **Cloudflare AI Gateway proxy** → Anthropic. No keys in app bundle. | Free under ~100k req/day; caching cuts cost; centralized observability; doesn't lock to a single vendor. Alt: AIProxy iOS SDK if review pushes back. |
| **SDK** | `jamesrochabrun/SwiftAnthropic` with custom `basePath` pointed at the CF gateway URL | Already supports prompt caching, web-search tool, AIProxy integration if we pivot. |
| **Chat surface** | **Persistent floating chat bubble** bottom-right of Today, Week, Progress. Tap → slide-up drawer. Also reachable via tap on any InsightCard. Hidden during Log, Complete, Onboarding, WeeklyCheckIn, sheets, and the active-workout flow. | Coach should feel always-on, not behind a CTA. Bubble carries page context (whatever tab is active becomes part of the system prompt). Cheaper to discover than a Settings-style affordance. Hidden on focus screens (Log, Complete) so it doesn't steal CTA real estate. |
| **Tool calls** | 4 typed tools: `propose_plan_edits`, `propose_workout_changes`, `propose_memory_update`, `read_recent_feedback`. **All "propose" — user accepts.** | Mirrors PlanEdit/PlanDiff pattern. No silent mutation. |
| **Memory edits** | Append-only, user-confirmed. Coach can `propose_memory_update` adding a dislike/constraint; user taps Apply. Never edits existing fields. | Hidden memory edits would be spooky and untrustable. |
| **Conversation persistence** | Per-day, scoped to date. Tomorrow's chat starts fresh; yesterday's stays browsable. | Coach should feel like a daily journal, not an ever-growing thread. |
| **Consent** | First-launch modal AFTER user toggles "AI Coach: ON" in Settings (default OFF post-update for existing users; ON for new installs after onboarding). Names "Anthropic via our Cloudflare proxy" explicitly. | Apple Guideline 5.1.2(i) (Nov 2025) — explicit third-party AI disclosure before first transmission. |
| **Privacy manifest** | `NSPrivacyCollectedDataTypeOtherUserContent` for prompts; `NSPrivacyTrackingDomains` only if we add analytics (none planned). | Required for App Store review. |
| **Streaming** | `URLSession.bytes(for:).lines` → AsyncStream → SwiftUI Text rebuild throttled to 33ms (30fps) | Standard; per the May-2026 indie playbook this is the only way to keep Text reflow tolerable. |
| **Prompt cache** | Always-on for system prompt + memory blob (≥ 1024 tokens). Per-message context appended fresh. | Anthropic billing — system prompt is large enough to hit cache. Cut cost ~80% on repeat queries. |
| **Model fallback** | On 5xx or > 5s TTFB: retry once via Haiku 4.5 with shortened context. Surface "Coach is slow today — quick answer" banner. | Avoids spinner-of-death; Haiku-only fallback is still useful. |
| **Cost cap** | Per-user soft cap: 50 chat turns / day. Hard cap: 100. Above cap → "Pause until tomorrow" with an explanation. | Prevents runaway. Realistic users hit < 5/day. |
| **Dev mode** | Settings → "Debug" → toggle that shows last request/response JSON + cache hit rate per turn. | Required for me + cofounder to debug prompt regressions. |

## Phases

Each = one TestFlight-worthy increment. No regressions to the Phase 12 substrate; coach is purely additive and gated by a Settings toggle.

### Phase 13a — LLM client + consent + observability (no UI)

**Goal:** A working `CoachClient` that can send one round-trip request to Anthropic via Cloudflare Gateway and return text. No chat UI yet; a debug-menu "Test ping" button proves the path end-to-end. Settings toggle gates the feature.

**New files:**
- `PhaseTraining/Data/CoachClient.swift` — thin `URLSession` + SSE wrapper. Reads `CoachConfig.baseURL` and `CoachConfig.apiKey` (compile-time const for gateway; the gateway holds the real key).
- `PhaseTraining/Data/CoachConfig.swift` — base URL, default model, fallback model, cost cap constants.
- `PhaseTraining/Data/CoachConsent.swift` — `@AppStorage`-backed flag plus the consent modal payload (provider name, what's sent, link to docs/privacy.md).
- `PhaseTraining/Screens/Settings/CoachSettingsRow.swift` — Profile tab row: "AI Coach: OFF". Tapping ON presents the consent modal.

**Modified:**
- `docs/privacy.md` — add the AI Coach section (provider, data sent, retention, opt-out).
- `PhaseTraining/Info.plist` (via Project.yml `info.properties`) — add `NSPrivacyTrackingDomains` if needed, set `NSPrivacyCollectedDataTypeOtherUserContent`.

**Acceptance:** Toggle AI Coach on, complete consent, tap "Test ping" in dev menu, see "OK: response token count, latency" log.

---

### Phase 13b — Read-only chat drawer ("ASK COACH" on Today)

**Goal:** Persistent slide-up drawer with streaming responses. Coach has read access to plan + memory + recent feedback via system prompt. **No tool calls yet.** First version is "smart Q&A about your plan."

**New files:**
- `PhaseTraining/Coach/CoachBubble.swift` — floating chat bubble (56pt circle, accent fill, sf-symbol `message.fill`). Positioned via ZStack overlay at the RootTabView level so it sits above the tab bar and the safe-area inset. Tap opens `CoachDrawer`. Visibility computed from current `AppTab` + sheet state.
- `PhaseTraining/Coach/CoachDrawer.swift` — SwiftUI sheet, message bubbles, input field, streaming text rendering.
- `PhaseTraining/Coach/CoachConversationStore.swift` — per-day conversation persistence (UserDefaults key `pt_coach_today`).
- `PhaseTraining/Coach/CoachContext.swift` — builder that serializes the current `WeekPlan`, last 5 feedback entries, today's `DayPlan`, **and the active tab** into a compact text block for the system prompt.
- `PhaseTraining/Coach/CoachSystemPrompt.swift` — versioned system-prompt template; cached portion declared via Anthropic `cache_control`.

**Modified:**
- `PhaseTraining/App/RootTabView.swift` — wrap `TabView` in a `ZStack` with `CoachBubble` overlay. Bubble reads `tabSelection.selected`; hides on `.profile` and when any sheet/cover is active.
- `PhaseTraining/Screens/LogScreen.swift` / `CompleteScreen.swift` — set a `coachBubbleHidden` env value (or check active-session presence at the RootTabView level) so the bubble disappears during workouts.
- `PhaseTraining/Components/InsightCard.swift` — tap → opens drawer with the card's body pre-loaded as a follow-up prompt.

**Acceptance:** Ask "why did you put squats Thursday?" → drawer streams a sensible answer that references actual `generatedReason` from the day. Ask "how's my recent feedback?" → answer cites real entries from the last 7 days.

---

### Phase 13c — Plan-edit tool calls

**Goal:** Coach can propose `PlanEdit` ops via tool calls. Drawer renders an inline mini-PlanDiff card. User taps Apply → goes through the existing `PlanStore.apply(_:)` seam. Reject = no-op.

**New files:**
- `PhaseTraining/Coach/CoachTools.swift` — Anthropic tool definitions matching `PlanEdit` cases. JSON schemas validated at decode time.
- `PhaseTraining/Coach/CoachToolResult.swift` — wrapper that turns tool calls into `PlanDiff` candidates surfaced to UI.

**Modified:**
- `PhaseTraining/Coach/CoachDrawer.swift` — when a tool-call message arrives, render `MiniPlanDiffCard` inline above the next assistant turn.

**Acceptance:** "Move Thursday's lift to Friday" → coach proposes the move → inline diff shows before/after rows → Apply → Week tab reflects it. "Make this week easier" → proposes shortening + swapping a lift to mobility → preview → Apply.

---

### Phase 13d — Workout-edit tool calls (exercise-level)

**Goal:** Within today's generated workout, coach can propose `swap_exercise` and `adjust_set_target` operations. Builds on the build-36 generator. Each proposal renders an inline workout-diff card.

**New files:**
- `PhaseTraining/Data/WorkoutDiff.swift` — analogous to PlanDiff but at the exercise/set level. Pure; UI applies via the generated-workout's mutating accessors.
- `PhaseTraining/Coach/MiniWorkoutDiffCard.swift` — compact "Bench → Goblet Squat (you flagged knee pain last week)" pattern.

**Modified:**
- `PhaseTraining/Coach/CoachTools.swift` — add `propose_workout_changes` tool with `swap_exercise(exerciseId, toExerciseId)` and `adjust_set_target(exerciseId, sets, reps)` operations.
- `PhaseTraining/Screens/TodayScreen.swift` — when a workout-diff is applied, the live `template` rebuilds without losing logged sets.

**Acceptance:** "My knee's been sore — swap squats for something easier" → coach picks a knee-friendly alternative from coach.db, shows mini-diff, Apply → Today's exercise list updates with logged-set state preserved.

---

### Phase 13e — Coach-written insights + day-recap

**Goal:** Coach can write InsightCards proactively on Today / Week. Cards have a "REVIEW IN COACH" CTA that opens the drawer with the conversation that produced them. Also: a daily "Yesterday's session" recap card that appears on Today the morning after a logged workout.

**New files:**
- `PhaseTraining/Data/CoachInsight.swift` — `Codable` insight record (id, date, body, surfaces: [today/week/post], sourceConversationId).
- `PhaseTraining/Coach/InsightGenerator.swift` — triggered on app-foreground when conditions are met (e.g., last-week feedback present, no insight written today).

**Modified:**
- `PhaseTraining/Components/InsightCard.swift` — render the CTA when sourced from a CoachInsight.
- `PhaseTraining/Screens/TodayScreen.swift` — pull dynamic insight copy when consent is granted.

**Acceptance:** Log a session with "too hard" + "knee hurt" → next morning, Today shows a coach-written insight ("Your knee flared in 3 of 4 squat days — I trimmed today's session and dropped front squats. Tap to see."). Tap → drawer opens to that conversation. Insight persists in `memory.coachInsights` for 30 days.

---

## Files at a glance

### New (Swift)

```
PhaseTraining/Data/CoachClient.swift
PhaseTraining/Data/CoachConfig.swift
PhaseTraining/Data/CoachConsent.swift
PhaseTraining/Data/CoachInsight.swift
PhaseTraining/Data/WorkoutDiff.swift
PhaseTraining/Coach/CoachBubble.swift
PhaseTraining/Coach/CoachDrawer.swift
PhaseTraining/Coach/CoachContext.swift
PhaseTraining/Coach/CoachConversationStore.swift
PhaseTraining/Coach/CoachSystemPrompt.swift
PhaseTraining/Coach/CoachTools.swift
PhaseTraining/Coach/CoachToolResult.swift
PhaseTraining/Coach/InsightGenerator.swift
PhaseTraining/Coach/MiniPlanDiffCard.swift
PhaseTraining/Coach/MiniWorkoutDiffCard.swift
PhaseTraining/Screens/Settings/CoachSettingsRow.swift
PhaseTrainingTests/CoachContextSerializationTests.swift
PhaseTrainingTests/CoachToolDecodeTests.swift
```

### Modified

```
PhaseTraining/Screens/TodayScreen.swift          (ASK COACH pill + drawer wiring)
PhaseTraining/Screens/ProfileScreen.swift        (AI Coach settings row)
PhaseTraining/Components/InsightCard.swift       (tap-through + CTA)
docs/privacy.md                                  (AI section)
Project.yml                                      (privacy manifest entries)
```

## Verification

```bash
# Run the new coach unit tests in isolation
xcodebuild test \
  -scheme PhaseTraining \
  -destination 'platform=iOS Simulator,id=<udid>' \
  -only-testing:PhaseTrainingTests/CoachContextSerializationTests \
  -only-testing:PhaseTrainingTests/CoachToolDecodeTests

# Manual smoke: foreground app, toggle AI Coach off → confirm zero network
# requests to the gateway domain.
```

## Risk register

| Risk | Mitigation |
|---|---|
| App Store review rejects on 5.1.2(i) (third-party AI disclosure) | Consent modal names Anthropic explicitly, links to docs/privacy.md, ships before first network call. Tested with a fresh App Store Connect TestFlight build. |
| Coach hallucinates a plan edit that doesn't match what it claimed in chat | Tool-call schema is strict; UI renders the actual `PlanDiff` from `applyEdit`, not the model's prose. If they disagree, the diff wins. |
| Streaming costs spiral on a chatty user | Soft cap 50 turns/day with banner; hard cap 100. Prompt cache cuts ~80%. Sonnet-then-Haiku fallback on slow responses. |
| Cloudflare AI Gateway goes down | `CoachClient` falls back to direct Anthropic with a stub key embedded only in TestFlight builds; production stays gateway-only. |
| Model can't introspect why the planner did what it did | `DayPlan.generatedReason` already exists (build 23+); CoachContext serializes it. Add a `WorkoutGenerator.explain(exerciseId:)` accessor if needed in 13d. |
| Per-day conversation gets lost on app reinstall | Acceptable for v1 — conversations are scoped to "today" anyway. iCloud sync deferred. |
| Coach proposes a memory update the user accidentally rejects, then asks again later and the coach can't remember it | `memory.coachInsights` records the rejection; system prompt mentions "the user previously declined: X". Pattern only after Phase 13e. |

## Resolved decisions (2026-05-17)

1. **Cloudflare AI Gateway endpoint** — resolved.
   - Account: `192ffcc4f56e84386ddc0875eab97826` (Wilburwing@gmail.com)
   - Gateway slug: `phasetraining`
   - `CoachConfig.baseURL` = `https://gateway.ai.cloudflare.com/v1/192ffcc4f56e84386ddc0875eab97826/phasetraining/anthropic`
   - Authenticated Gateway: ON. App sends `cf-aig-authorization: Bearer <token>` header.
   - **Per-env tokens** (chosen over shared key for ops hygiene): `phasetraining-dev` + `phasetraining-prod` minted in CF dashboard. Token values stored at `~/.config/phase-training/cf-aigateway-tokens.env` (chmod 600, outside repo). Wire into Xcode via xcconfig per Configuration (Debug → dev, Release → prod).
   - **BYOK**: Anthropic key uploaded into CF AI Gateway's stored provider keys for the `phasetraining` gateway, alias `phasetraining-anthropic`. Client sends `cf-aig-byok-alias: phasetraining-anthropic` and omits any `x-api-key` header — CF appends the real upstream key. Smoke-tested 2026-05-17: gateway returned 200 from Sonnet 4.6 in 1.7s with no key in the request.
2. **Default model** — **Sonnet 4.6** (`claude-sonnet-4-6`). Plenty for tool-calling + structured edits; ~5x cheaper, ~2x faster TTFB than Opus 4.7. Opus reserved for deep multi-step reasoning the coach mostly isn't doing.
3. **Apple Intelligence on-device fallback** — deferred (post-Phase 13). Foundation Models could absorb ~5% of queries but doubles the prompt surface.

