---
name: phase-training-coach-chat-history-wiring
description: The contract for how CoachDrawer.send() builds the chat history it sends to the LLM in phase-training2 — wireHistory() filters empty messages, so exactly ONE dropLast() is correct, a second drops a real turn, and the result is an ArraySlice that must be wrapped in Array(). Trigger when editing the Coach chat send/stream path or history windowing in phase-training2/workout-plan, debugging "the coach forgot what I just said / dropped the last turn", or touching CoachDrawer.swift, CoachConversationStore.wireHistory, or client.stream(history:). Skip for coach.db (the bundled database — see the coachdb-* skills) and for non-chat Coach surfaces.
when-to-use: Editing or debugging the Coach chat history sent to the model in phase-training2 (CoachDrawer.send / wireHistory / client.stream history arg).
---

# Coach chat history wiring (phase-training2)

`CoachDrawer.send()` flow (PhaseTraining/Coach/CoachDrawer.swift):
1. Appends `userMsg` (the typed text) then an **empty** assistant placeholder, then builds the wire history.
2. `conv.wireHistory()` (CoachConversationStore.swift:141) **filters out empty-text messages** — so the empty assistant placeholder is already gone from the wire array.
3. Therefore `conv.wireHistory().dropLast()` removes the **new user message** (the last non-empty msg). That is CORRECT: the new turn is re-supplied separately as `userMessage:` to `client.stream`. The result = all PRIOR turns.

## The invariant (don't re-break it)
- The `history:` passed to `client.stream` must equal `wireHistory().dropLast()` — prior turns, new user msg excluded. The new turn goes ONLY via `userMessage:`.
- Do **NOT** `dropLast()` a second time at the `client.stream(history:)` call site. A second drop removes a real prior turn → the model gets one turn too few ("coach forgot what I just said"). Fixed 2026-06-05 (PR #39): deleted the extra `.dropLast()` at the stream call.
- `.dropLast()` returns `ArraySlice<CoachClient.Turn>`; the `history:` param wants `[CoachClient.Turn]`. Wrap it: `Array(history)`. Passing the slice fails to compile ("cannot convert ArraySlice to [Turn]").
- `wireText = statusPrefix(for: conv.messages.last) + text` prepends a synthetic status note to the WIRE user message only (when the last assistant turn carried a resolved proposal) — the displayed bubble still shows the raw typed text. Leave that intact.

## Verify-before-fixing note
This finding came in as an audit "double-dropLast bug". It was REAL, but only confirmed by reading `wireHistory()` — if that filter ever stops dropping empties, the dropLast accounting flips. Always re-read `wireHistory()` before trusting any dropLast claim here. No unit test covers send() (it's in the View); CoachConversationStoreTests covers wireHistory itself.
