# Part: AI Coach Subsystem

Scope: `PhaseTraining/Coach/*`, `Screens/CoachRequestScreen.swift`, `Components/PlanDiffSheet.swift`, `Components/InsightCard.swift`, plus the diff/apply seams in `Data/WorkoutDiff.swift`, `Data/PlanEdit.swift`, `Data/PlanStore.swift`, `Data/PlanStore+LLMRefinement.swift`, `Data/SessionStore.swift`.

Headline: the chat-driven proposal path (plan/workout/memory diffs) is genuinely preview-gated and well built. But a **second, parallel apply path — `PlanStore+LLMRefinement` — silently rewrites every lift day's workout from LLM output with no preview**, contradicting the stated "NEVER silent mutation" intent. Plus a real chat bug: `build_workout` is advertised to the chat model but its tool call is silently dropped in the drawer.

## Per-file findings (axis scores + evidence)

### CoachClient.swift
- **Correctness 4/5.** SSE decode is defensive: malformed event lines `continue` (`CoachClient.swift:200`), unknown event types fall through `default` (224). Tool-input JSON is accumulated per `content_block.index` (189–222) — correct for parallel blocks. Non-2xx path drains the body for the error (177–186). One gap: `bytes.lines` strips a possible CRLF but a `data:` line split across network chunks is handled by `.lines` so OK. Tool-use blocks with empty accumulated JSON still yield a `.toolCall` with empty `input` (220) — downstream `decode*` returns nil, so no crash, but the user sees a silent no-op turn.
- **Cost 4/5.** `max_tokens` 1024 (`CoachConfig.swift:40`); `build_workout` output (arrays of overrides) can plausibly truncate mid-JSON on a large prescription set → `decodeBuildWorkout` returns nil → falls back to starter strategy. Acceptable degrade, but no telemetry that it happened.
- **Security 4/5.** No `x-api-key` ever sent (by design — BYOK at gateway). Gateway token in `cf-aig-authorization` header only.

### CoachConfig.swift
- **Cost / model choice 4/5.** `defaultModel = "claude-sonnet-4-6"`, `fallbackModel = "claude-haiku-4-5"` (`CoachConfig.swift:21,25`) — both current 4.x IDs, not retired 3.x. No flag. **Dead code:** `fallbackModel` is defined but never referenced anywhere (no `CoachConfig.fallbackModel` call site); the "fallback on slow primary" behavior the comment promises doesn't exist. `softTurnCap`/`hardTurnCap` (33,37) are likewise **never enforced** — grep shows no reader. Cost-control story is aspirational comments, not code.

### CoachSecrets.swift (Generated/)
- **Security 3/5.** Gateway token `cfut_...` is in source (`CoachSecrets.swift:12`) but the dir IS gitignored (`PhaseTraining/Generated/` in `.gitignore:23`) and not git-tracked — so NOT leaked to the repo. The real exposure: the token is compiled into the shipped IPA as a plaintext string and is trivially `strings`-extractable from any TestFlight/App Store build. A static-aliased CF gateway token = anyone who pulls the binary can spend against the gateway's BYOK Anthropic key until rotated. The gateway's per-key rate limits are the only backstop. Mitigation would be device-attestation / short-lived tokens, out of scope for now but worth a P1 note.

### CoachConsent.swift / consent gating
- **Correctness (gating) 3/5.** Modal is an `.alert` (`CoachConsent.swift:38`) — Apple 5.1.2(i) disclosure copy is present and names the provider. Gating is enforced at the *entry points* (CoachBubble `shouldShow` requires `consentGranted` `CoachBubble.swift:32`; CoachRequestScreen guards before LLM `CoachRequestScreen.swift:395`; InsightGenerator guards `InsightGenerator.swift:32`; LLMRefinement guards `PlanStore+LLMRefinement.swift:37`). **But `CoachDrawer.send()` itself never checks consent** (grep: no `consent` in CoachDrawer.swift). It relies entirely on the bubble being the only door. If any future surface presents the drawer (deep link, InsightCard `conv.present`), data leaves the device with no gate. Defense-in-depth is missing at the actual network seam.

### CoachSystemPrompt.swift
- **Correctness 4/5.** Strong tool discipline in prose: "exactly ONE tool per turn", "user accepts or rejects … NOT applied automatically" (`CoachSystemPrompt.swift:46,49`). Versioned cache key (15). Good.
- **Cost 5/5.** `cachedHeader` correctly marked `cache_control: ephemeral` (`CoachClient.swift:161`); per-turn context sent uncached (162). Two-block split is exactly right for prompt-cache hit rate.

### CoachTools.swift
- **Correctness 4/5.** Decoders are robust: every `decode*` uses `try?` and returns nil on malformed input (`CoachTools.swift:353,359,368,410`) — a garbage LLM payload can't crash. `decodeBuildWorkout` clamps duration 15–180 (374), filters weights to (0,1000] (377), and unknown `focus` falls to `.auto` (369 comment). `planEdits(for:in:)` resolves dates against the plan and **skips unmatched ops** (`continue` at 433–470) — no UUID corruption.
- **Bug.** `CoachTools.all` includes `buildWorkout` (207) and the drawer sends `tools: CoachTools.all` (`CoachDrawer.swift:327`). But the drawer's `toolCall` switch has cases only for `propose_plan_edits` / `propose_workout_changes` / `propose_memory_update` — `build_workout` hits `default: continue` (`CoachDrawer.swift:356`) and is **silently dropped**. So if a chat user says "build me a push day", the model calls `build_workout`, the drawer eats it, and the user gets an empty/placeholder assistant bubble with no workout and no error. (The tool only works from CoachRequestScreen + LLMRefinement, which pass `tools: [CoachTools.buildWorkout]` and handle the call.) Fix: either drop `buildWorkout` from `.all` or wire a card for it in the drawer.

### CoachDrawer.swift
- **UX 3/5.** Empty-state copy says "It can't change anything yet — that's coming" (`CoachDrawer.swift:100`) — **stale**: the coach demonstrably proposes plan/workout/memory edits. Misleads the user into not trying edit requests.
- **Correctness 4/5.** Streaming, cancel (41, 280), status-note continuity (248–262) all sound. `flush()` once at end-of-stream, not per delta (369) — good for the watchdog history noted in comments.
- **Cost.** Sends `tools: CoachTools.all` (4 tool schemas incl. the large `build_workout` pattern enum) on *every* chat turn even though 1 of the 4 is unhandled — wasted input tokens per turn.

### MiniPlanDiffCard / MiniWorkoutDiffCard / MiniMemoryDiffCard
- **Correctness (preview→apply) 5/5.** All three resolve a diff and route Apply through the *same* PlanStore/MemoryStore seams as manual edits (`MiniPlanDiffCard.swift:185` → `planStore.apply`; `MiniWorkoutDiffCard.swift:188`; `MiniMemoryDiffCard.swift:144`). Apply is disabled on no-op (`canApply`), status persists so cards don't re-prompt after relaunch. MemoryDiff de-dupes case-insensitively and trims (149–160). This is the model citizen of the subsystem.
- **Accessibility 1/5.** Zero accessibility annotations on any of the three cards (grep found none). Apply/Reject are bare `Text` in `.plain` buttons — VoiceOver reads "Apply"/"Reject" with no context (what's being applied), the before/after diff rows aren't grouped, strikethrough "removed" state conveys meaning by visual style only. The single most consequential action in the app (mutating the plan) is the least accessible.
- **Consistency 3/5.** MiniWorkoutDiffCard resolves on `.onAppear` with no `guard resolvedDiff == nil` re-entrancy guard (`MiniWorkoutDiffCard.swift:61,170`), unlike MiniPlanDiffCard which explicitly added that guard for the build-60 watchdog (`MiniPlanDiffCard.swift:170`). Inconsistent — workout card can re-resolve on every layout pass.

### CoachContext.swift (826 lines)
- **Data-richness vs UI-surface 3/5.** Extremely rich serialization: strength velocity, muscle balance, pattern frequency, week adherence, per-set last-session detail, structured injuries + filters + prehab. Most is *readable* signal (good for Q&A). **Gaps both directions:**
  - *Serializes data the coach can't act on:* `INJURY FILTERS`, `PREHAB CANDIDATES`, `MUSCLE BALANCE`, `PATTERN FREQUENCY` are all read-only context — none of the 3 chat tools can add/remove an injury or directly schedule a prehab exercise (memory tool only edits free-text dislikes/constraints; structured injuries have no tool). The coach can *describe* an imbalance but the only lever it has is `propose_workout_changes` on today. Large token spend on signal the coach can only narrate.
  - *Omits data it could use:* comment at `CoachContext.swift:357` notes `mechanism` / `typical_recovery` columns exist in coach.db but aren't projected — the coach gives injury advice without recovery-timeline data that's sitting in the DB.
  - `recentSportLogs` defaulted to `[]` (27) — CoachRequestScreen + InsightGenerator callers omit it (`CoachRequestScreen.swift:416`, `InsightGenerator.swift:36`), so the build-workout path and the daily insight are blind to climbing/running load that the chat path sees. Inconsistent context across surfaces.
- **Privacy 3/5.** Sends body metrics (height/weight/gender/age `bodySection` 400–416), full injury detail with user notes (360), free-text constraints, every recent session's loads. Consent copy says "No identity information is sent" (`CoachConsent.swift:26`) — defensible (no name/email/DOB), but gender + age + body comp + injury history is sensitive health data going off-device. The disclosure undersells what's transmitted.

### CoachRequestScreen.swift
- **Correctness 4/5.** Graceful degrade: no consent → pure deterministic path, no token spend (`CoachRequestScreen.swift:395`); LLM error/cancel/no-tool-call → starter strategy (437,447,452). Merge logic preserves chip focus/duration when LLM omits (456–458). Output is previewed before save — fine.

### InsightGenerator.swift
- **Correctness 4/5.** Idempotent guards (one/day, signal check) `InsightGenerator.swift:32–34`. `sanitize` strips throat-clearing + caps length (113–124). Failures swallowed silently by design (60–67) — acceptable for a background nicety. Insight is display-only; tapping opens the drawer with a prefill — no mutation. Clean.

## Safety review: can the coach ever mutate a plan without explicit user preview?

**Chat path (CoachDrawer): NO — correctly preview-gated.** Trace: stream → `.toolCall` → `decode*` → `conv.setProposal/…` attaches a `.pending` proposal to the assistant message → MiniXDiffCard renders → user taps **Apply** → `planStore.apply(diff)` / `memoryStore.update`. Nothing mutates state before the Apply button. Reject just records status. This matches the design intent.

**Refinement path (PlanStore+LLMRefinement): NO — this IS silent mutation.** Trace: `PlanStore.generate(from:)` → `kickOffLLMRefinementIfConsented` (`PlanStore+LLMRefinement.swift:32`) → background `TaskGroup`, one LLM `build_workout` call per lift day → `decodeBuildWorkout` → re-run generator → `applyRefinedWorkout` writes straight into `self.plan` and `savePlan()` (`PlanStore+LLMRefinement.swift:225–235`). **No diff, no card, no Apply button.** The user's plan is rewritten by LLM-shaped strategy the moment they generate a plan (and again after *every* accepted plan/workout edit — `PlanStore.apply` re-fires it at `:362`, and `applyWorkoutDiff` at `:420`). It's gated on *consent*, but consent ≠ per-change preview. The system prompt promises "Only the user (via the Apply button) commits" (`CoachSystemPrompt.swift:49`) — this path violates that promise for the single largest surface (the whole week's workouts). It is bounded (focus is forced to match the deterministic day at `:170` so the LLM can't turn push into pull; failures stay deterministic), so it can't *corrupt* the plan shape — but it absolutely mutates exercise selection / sets / RPE without preview. This is the #1 finding.

## Cross-cutting issues
1. **Two contradictory mutation philosophies.** Chat = preview-then-apply; refinement = silent. A user who carefully Rejects a chat workout change still has every other day silently LLM-rewritten in the background. No UI even tells them refinement happened (only a `refinedByLLMAt` stamp + a changed `generatedReason`).
2. **`build_workout` half-wired.** Advertised to chat, handled only outside chat. Dead `fallbackModel` + unenforced turn caps round out a "config promises behavior the code doesn't deliver" theme.
3. **Consent enforced at doors, not at the network seam.** `CoachDrawer.send()` has no consent guard.
4. **Context↔tools mismatch.** ~40% of the serialized context (injury filters, prehab, balance, pattern freq) maps to no coach tool; meanwhile structured injuries (rich, actionable) have no edit tool at all.
5. **Diff cards are inaccessible.** The app's most consequential action has zero VoiceOver support.
6. **Stale empty-state copy** tells users the coach can't change anything.

## Tiered backlog

### P0
- Decide refinement's contract: either surface LLM refinement as a reviewable diff, or explicitly document+disclose it as auto-personalization in consent copy + an in-UI "coach polished N days" indicator. Today it silently contradicts the stated no-silent-mutation rule. — **M** — `PlanStore+LLMRefinement.swift`
- Wire or remove `build_workout` in the chat drawer; right now "build me a workout" in chat silently no-ops. — **S** — `CoachDrawer.swift:356` / `CoachTools.swift:207`

### P1
- Add a consent guard inside `CoachDrawer.send()` (defense-in-depth at the network seam). — **S** — `CoachDrawer.swift:275`
- Accessibility pass on the 3 Mini*DiffCards: label Apply/Reject with the change summary, group diff rows, convey add/remove non-visually. — **M** — `MiniPlanDiffCard.swift` / `MiniWorkoutDiffCard.swift` / `MiniMemoryDiffCard.swift`
- Fix stale empty-state copy ("can't change anything yet"). — **S** — `CoachDrawer.swift:100`
- Pass `recentSportLogs` from CoachRequestScreen + InsightGenerator so all coach surfaces share one context. — **S** — `CoachRequestScreen.swift:416`, `InsightGenerator.swift:36`
- Tighten consent disclosure to name body metrics + injury history as transmitted health data. — **S** — `CoachConsent.swift:26`

### P2
- Remove dead `fallbackModel` + unenforced `softTurnCap`/`hardTurnCap`, or implement them (real cost control). — **S** — `CoachConfig.swift:25,33,37`
- Don't send `build_workout`'s large schema on chat turns once it's removed from `.all` (token saving). — **S** — `CoachDrawer.swift:327`
- Add the build-60 re-entrancy guard to MiniWorkoutDiffCard.resolve() for consistency with MiniPlanDiffCard. — **S** — `MiniWorkoutDiffCard.swift:170`
- Trim read-only-only context blocks the coach can't act on, or add tools to act on them (structured-injury edit tool; prehab scheduling). — **M/L** — `CoachContext.swift`
- Project `mechanism`/`typical_recovery` into STRUCTURED INJURIES so injury advice has recovery timelines. — **S** — `CoachContext.swift:357`
