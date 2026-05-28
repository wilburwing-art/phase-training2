# Roadmap — phase-training2

Forward-looking items beyond the current phase plans (`PLAN.md`, `PLAN-routines.md`, `PLAN-coach-prereqs.md`, `PLAN-coach.md`). Entries here are not yet specced; they're load-bearing context for future plan files.

---

## Voice coach check-ins (AirPods, walking into the gym)

**Context.** Pre-workout window — leaving the car, walking through the parking lot, AirPods in. Hands occupied, phone in pocket. The user wants to talk to the coach instead of unlocking and tapping into the app.

**Shape.**
- Initiated by the user (Siri / lock-screen / "Hey Coach" — TBD), not auto-triggered on Bluetooth connect.
- Short conversational check-in: "How's the body? Anything bothering you? Want to shift today's session?"
- Coach has full context (today's `DayPlan`, recent feedback, `TrainingMemory.recentSoreness`, the same `CoachContext` the chat coach uses).
- Output is spoken (TTS); input is voice (STT). Conversation logs land in the same per-day thread as keyboard chat so the user can scroll back later.
- If the coach proposes a plan change mid-walk, it stages a `PlanDiff` the user previews/applies *after* the workout — never silent mutation, especially not while audio-only.

**Why now-ish (not yet).** Phase 13 lands keyboard chat, tool-calling, and the coach's read access to plan + memory. Voice is the same coach with two new I/O channels — the model layer, prompt cache, gateway, and tool-call schema are reusable. The build cost is on the iOS side (audio session, STT, TTS, lock-screen surface), not the AI side.

**Open questions to resolve before writing a phase plan.**
- Activation: Siri Shortcut vs. App Intent vs. always-listening hot-phrase. (Battery + privacy implications differ a lot.)
- STT: Apple's `SFSpeechRecognizer` (on-device, free) vs. Whisper-via-gateway (better, costs $).
- TTS: AVSpeechSynthesizer (free, robotic) vs. ElevenLabs/OpenAI TTS via gateway (warm, costs $, latency).
- Diff staging UX: how does a user "preview" an edit they were told about via audio when they're 30 seconds from the squat rack?
- Does the lock-screen Now Playing surface make sense as the "I'm in a coach call" affordance, or is that abuse of the API?

**Dependency on Phase 13.** Don't start before PLAN-coach 13a–13c land. The tool-call schema and `CoachContext` serialization need to be stable.
