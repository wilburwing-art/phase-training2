// CoachDrawer.swift — Phase 13b chat surface.
//
// Slide-up sheet with conversation bubbles, sticky input, and live-streaming
// assistant responses. Reads context from the env-stored stores (memory,
// plan, sessions, feedback, soreness) and builds a fresh per-turn snapshot
// at send time.

import SwiftUI

struct CoachDrawer: View {
    @EnvironmentObject private var conv: CoachConversationStore
    @EnvironmentObject private var memoryStore: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var tabSelection: TabSelectionStore
    @EnvironmentObject private var sportLogStore: SportLogStore

    @State private var input: String = ""
    @State private var sending: Bool = false
    @State private var streamingId: UUID? = nil
    @State private var inflightTask: Task<Void, Never>? = nil
    @FocusState private var inputFocused: Bool
    @State private var confirmingClear = false
    @State private var showingHistory = false

    private let client = CoachClient()

    /// Cached — allocating a DateFormatter per tool call is needless churn.
    private static let isoDayFormatter: DateFormatter = DayKeyFormatter.iso

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            Divider().background(Color.lineSoft)
            if conv.messages.isEmpty {
                emptyState
            } else {
                conversationList
            }
            if conv.atSoftCap { capBanner }
            inputBar
        }
        .background(Color.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear(perform: handleAppear)
        .onDisappear { inflightTask?.cancel() }
        .alert("Clear today's chat?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { conv.clearToday() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This removes today's messages. Past days stay in History.")
        }
        .sheet(isPresented: $showingHistory) {
            CoachHistorySheet()
                .environmentObject(conv)
        }
    }

    // MARK: - Pieces

    private var handle: some View {
        Capsule()
            .fill(Color.line)
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text("COACH")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Spacer()
            // T2-4: past days' transcripts were archived and unreachable.
            if !conv.archivedDays().isEmpty {
                Button { showingHistory = true } label: {
                    Text("HISTORY")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
            }
            if !conv.messages.isEmpty {
                // One tap, no confirmation, no undo — and it was the only
                // affordance next to a transcript the user may want.
                Button { confirmingClear = true } label: {
                    Text("CLEAR")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
            }
            Button {
                inputFocused = false
                conv.presented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 28, height: 28)
                    .background(Color.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.line, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close coach")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer().frame(height: 12)
            Text("Ask about today's plan.")
                .font(.custom("SpaceGrotesk-SemiBold", size: 22))
                .tracking(-0.025 * 22)
                .foregroundStyle(Color.ink)
            Text("The coach reads your week, recent sessions, and feedback, and can edit your plan or put a session on a day. You approve every change. Try:")
                .styled(.body)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                suggestionChip("Why is Thursday a lift day?")
                suggestionChip("Put an MTB ride on today.")
                suggestionChip("Suggest a swap for today's squats.")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            input = text
            inputFocused = true
        } label: {
            HStack(spacing: 6) {
                Text(text)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink2)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(conv.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conv.messages.last?.id) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: conv.messages.last?.text) { _, _ in
                scrollToBottom(proxy)
            }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private func bubble(_ message: CoachMessage) -> some View {
        let hasAnyProposal = message.proposal != nil || message.workoutProposal != nil || message.memoryProposal != nil
        let suppressPlaceholder = message.text.isEmpty && !message.isUser && hasAnyProposal
        return VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .top) {
                if message.isUser { Spacer(minLength: 32) }
                if !suppressPlaceholder {
                    Text(message.text.isEmpty && !message.isUser ? "…" : message.text)
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(message.isUser ? Color.accentInk : Color.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(message.isUser ? Color.accent : Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(message.isUser ? Color.clear : Color.line, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !message.isUser { Spacer(minLength: 32) }
            }
            if let proposal = message.proposal, !message.isUser {
                MiniPlanDiffCard(messageId: message.id, proposal: proposal)
                    .padding(.trailing, 32)
            }
            if let workoutProposal = message.workoutProposal, !message.isUser {
                MiniWorkoutDiffCard(messageId: message.id, proposal: workoutProposal)
                    .padding(.trailing, 32)
            }
            if let memoryProposal = message.memoryProposal, !message.isUser {
                MiniMemoryDiffCard(messageId: message.id, proposal: memoryProposal)
                    .padding(.trailing, 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.lineSoft)
            HStack(spacing: 10) {
                // Single-line. The growing-vertical TextField (axis: .vertical
                // + lineLimit(1...4)) caused layout thrash inside the sheet's
                // detent transitions — opening/closing the keyboard and
                // dragging between medium/large detents could pin the main
                // thread long enough to crash the app.
                TextField("Ask the coach…", text: $input)
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: sending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend || sending ? Color.accentInk : Color.ink3)
                        .frame(width: 38, height: 38)
                        .background(canSend || sending ? Color.accent : Color.elevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !sending)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(Color.bg)
    }

    /// Shown above the input once the user crosses the soft daily turn cap.
    /// Soft cap: informational, sends still go through. Hard cap: input is
    /// also disabled via `canSend`.
    private var capBanner: some View {
        let hard = conv.atHardCap
        return HStack(spacing: 8) {
            Image(systemName: hard ? "moon.zzz.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hard ? Color.ink2 : Color.accent)
            Text(hard
                 ? "Daily coaching limit reached. Pick this up tomorrow — your plan and history stay put."
                 : "You've sent \(conv.turnsToday) messages today, nearing the daily limit of \(CoachConfig.hardTurnCap).")
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !conv.atHardCap
    }

    /// Build a "[STATUS NOTE: ...]" prefix when the previous assistant turn
    /// had a proposal the user has resolved. Returns "" otherwise. The model
    /// is told (in v4 system prompt) that these prefixes are system metadata,
    /// not the user's words.
    private func statusPrefix(for prior: CoachMessage?) -> String {
        guard let prior, !prior.isUser else { return "" }
        var notes: [String] = []
        if let p = prior.proposal, p.status != .pending {
            notes.append("plan-edit proposal was \(p.status.rawValue.uppercased())")
        }
        if let p = prior.workoutProposal, p.status != .pending {
            notes.append("workout-change proposal was \(p.status.rawValue.uppercased())")
        }
        if let p = prior.memoryProposal, p.status != .pending {
            notes.append("memory-update proposal was \(p.status.rawValue.uppercased())")
        }
        guard !notes.isEmpty else { return "" }
        return "[STATUS NOTE — system metadata, not user speech: your last \(notes.joined(separator: "; "))]\n\n"
    }

    // MARK: - Logic

    private func handleAppear() {
        conv.rolloverIfNeeded()
        if !conv.prefill.isEmpty {
            input = conv.prefill
            conv.prefill = ""
            inputFocused = true
        }
    }

    private func send() {
        if sending {
            // Cancel an in-flight turn.
            inflightTask?.cancel()
            return
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Hard daily cap: refuse to send. The input is already disabled via
        // canSend, but guard here too in case .onSubmit fires.
        guard !conv.atHardCap else { return }

        // Phase 13f: if the most recent assistant turn carried a proposal the
        // user has resolved, prepend a synthetic status note so the model
        // knows what happened to its tool call. v4 system prompt advertises
        // this convention so the prefix isn't treated as user voice. The
        // prefix goes ONLY to the wire — the displayed bubble shows what
        // the user actually typed.
        let wireText = statusPrefix(for: conv.messages.last) + text

        let userMsg = CoachMessage(role: "user", text: text)
        let assistantMsg = CoachMessage(role: "assistant", text: "")
        conv.append(userMsg)
        conv.append(assistantMsg)
        conv.recordTurn()
        streamingId = assistantMsg.id
        input = ""
        sending = true

        let history = conv.wireHistory().dropLast()  // exclude the new user msg itself
        // Sport logs window: last 21 days, capped to the most recent 30 to
        // keep the prompt bounded if the user is a high-frequency logger.
        // CoachContext re-trims to 5 for display; we just want the relevant
        // tail here rather than the full history.
        let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: Date()) ?? Date.distantPast
        let recentSportLogs = sportLogStore.entries
            .filter { $0.date >= cutoff }
            .suffix(30)

        let snapshot = CoachContext.snapshot(
            activeTab: tabSelection.selected,
            memory: memoryStore.memory,
            plan: planStore.plan,
            recentSessions: sessionStore.savedSessions,
            recentFeedback: memoryStore.memory.feedback,
            recentSoreness: memoryStore.memory.soreness,
            recentSportLogs: Array(recentSportLogs),
            // T2-3: these three blocks are fully implemented and unit-tested in
            // CoachContext, but NO production call site passed them — verified
            // by grep across the app. So the PAST WEEKS / PLAN ISSUES / MISSED
            // WORKOUTS sections the comments promise the coach can discuss never
            // reached the model, even though PlanStore publishes all three.
            //
            // Wired here (the chat surface) only. The insight and refinement
            // passes are one-shot and cost-sensitive; the drawer is where a user
            // actually asks "why did I miss Tuesday?".
            pastPlans: planStore.pastPlans,
            planIssues: planStore.currentValidationIssues(memory: memoryStore.memory),
            missedWorkouts: planStore.missedWorkouts
        )

        inflightTask = Task {
            do {
                let stream = client.stream(
                    cachedSystem: CoachSystemPrompt.cachedHeader,
                    perTurnContext: CoachSystemPrompt.contextBlock(snapshot: snapshot),
                    history: Array(history),
                    userMessage: wireText,
                    tools: CoachTools.chat
                )
                for try await part in stream {
                    switch part {
                    case .textDelta(let chunk):
                        await MainActor.run {
                            conv.appendDelta(to: assistantMsg.id, chunk)
                        }
                    case .toolCall(_, let name, let inputData):
                        // A failed decode used to fall through silently: the
                        // assistant said "I've proposed moving Thursday to
                        // Friday", no diff card rendered, and the user had no
                        // error and no way to retry. Truncation at max_tokens
                        // and malformed input_json_delta both land here.
                        var decoded = true
                        switch name {
                        case "propose_plan_edits":
                            if let proposal = CoachToolDecoder.decodeProposal(from: inputData) {
                                await MainActor.run { conv.setProposal(on: assistantMsg.id, proposal) }
                            } else {
                                decoded = false
                            }
                        case "propose_workout_changes":
                            // Build 99: pass today as the FALLBACK, not as
                            // an override. If the model supplied a `date`
                            // in the tool input it wins — chat can now
                            // edit any day in the current plan, not just
                            // today.
                            let today = Self.isoDayFormatter.string(from: Date())
                            if let proposal = CoachToolDecoder.decodeWorkoutProposal(from: inputData, fallbackDate: today) {
                                await MainActor.run { conv.setWorkoutProposal(on: assistantMsg.id, proposal) }
                            } else {
                                decoded = false
                            }
                        case "propose_memory_update":
                            if let proposal = CoachToolDecoder.decodeMemoryProposal(from: inputData) {
                                await MainActor.run { conv.setMemoryProposal(on: assistantMsg.id, proposal) }
                            } else {
                                decoded = false
                            }
                        default:
                            continue
                        }
                        if !decoded {
                            await MainActor.run { noteUndeliveredProposal() }
                        }

                    case .stopped(let reason):
                        // "max_tokens" means the model was cut off mid-thought.
                        if reason == "max_tokens" {
                            await MainActor.run { noteTruncatedReply() }
                        }
                    }
                }
                await MainActor.run { finishSuccess() }
            } catch {
                await MainActor.run { finishError(error) }
            }
        }
    }

    private func finishSuccess() {
        conv.flush()
        sending = false
        streamingId = nil
        inflightTask = nil
    }

    /// User-facing error taxonomy. `error.localizedDescription` was written
    /// straight into the assistant bubble, so the coach appeared to say things
    /// like "No Cloudflare AI Gateway token configured. Set
    /// PHASETRAINING_CF_AIG_DEV_TOKEN in ~/.config/phase-training/…" or up to
    /// 512 characters of raw gateway JSON. Three cases the user can act on;
    /// anything else is "try again".
    private static func userFacingMessage(for error: Error) -> String {
        if let coachError = error as? CoachClient.CoachError {
            switch coachError {
            case .dailyCeilingReached:
                return "That's the coach's limit for today — it'll pick back up tomorrow."
            case .missingGatewayToken:
                return "The coach isn't available in this build."
            case .http(let status, _):
                if status == 429 { return "The coach is rate-limited right now. Try again in a minute." }
                if (500...599).contains(status) { return "The coach is having trouble on its end. Try again shortly." }
                return "The coach couldn't complete that. Try again."
            case .transport:
                return "Couldn't reach the coach. Check your connection and try again."
            case .decode:
                return "The coach's reply came back garbled. Try again."
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach the coach. Check your connection and try again."
        }
        return "Something went wrong reaching the coach. Try again."
    }

    /// The model announced a change but its tool payload didn't decode, so no
    /// diff card can render. Say so inline instead of leaving the user staring
    /// at a claim with no card and no way to retry.
    private func noteUndeliveredProposal() {
        guard let id = streamingId,
              let idx = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        let note = "\n\n⚠️ That change didn't come through in a usable form — ask again and I'll re-propose it."
        if !conv.messages[idx].text.hasSuffix(note) {
            conv.messages[idx].text += note
        }
    }

    /// The reply hit maxOutputTokens. Without this the user just got a
    /// sentence that stopped mid-word, with nothing to distinguish it from a
    /// complete answer and no way to ask for the rest.
    private func noteTruncatedReply() {
        guard let id = streamingId,
              let idx = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        let note = "\n\n… (cut off — ask me to continue)"
        if !conv.messages[idx].text.hasSuffix(note) {
            conv.messages[idx].text += note
        }
    }

    private func finishError(_ error: Error) {
        if let id = streamingId,
           let idx = conv.messages.firstIndex(where: { $0.id == id }) {
            let prefix = conv.messages[idx].text.isEmpty ? "" : conv.messages[idx].text + "\n\n"
            conv.messages[idx].text = prefix + "⚠️ " + Self.userFacingMessage(for: error)
        }
        conv.flush()
        sending = false
        streamingId = nil
        inflightTask = nil
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "CoachDrawer.preview")!
    defaults.removePersistentDomain(forName: "CoachDrawer.preview")
    let conv = CoachConversationStore(defaults: defaults)
    conv.append(CoachMessage(role: "user", text: "Why is Thursday a lift day?"))
    conv.append(CoachMessage(role: "assistant", text: "You picked Tue/Thu/Sat as lift days during onboarding. Thursday is day 2 of the strength pattern — heavier focus before the weekend rest."))
    return CoachDrawer()
        .environmentObject(conv)
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(TabSelectionStore())
        .environmentObject(SportLogStore(defaults: defaults))
}

// MARK: - Archived conversations (T2-4)

/// Read-only browser for `pt_coach_archive_<day>` transcripts.
///
/// Lives in this file rather than its own because project.pbxproj is
/// hand-managed AND gitignored here — a new file wouldn't compile into the
/// target for anyone else. See the repo's pbxproj note.
struct CoachHistorySheet: View {
    @EnvironmentObject private var conv: CoachConversationStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                let days = conv.archivedDays()
                if days.isEmpty {
                    Text("No past conversations yet.")
                        .styled(.body)
                        .foregroundStyle(Color.ink3)
                } else if let day = selectedDay,
                          let messages = conv.archivedMessages(forDay: day) {
                    transcript(day: day, messages: messages)
                } else {
                    dayList(days)
                }
            }
            .navigationTitle(selectedDay ?? "Past chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedDay != nil {
                        Button("Back") { selectedDay = nil }
                            .foregroundStyle(Color.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    private func dayList(_ days: [String]) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    Button { selectedDay = day } label: {
                        HStack {
                            Text(day)
                                .styled(.body)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text("\(conv.archivedMessages(forDay: day)?.count ?? 0) messages")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.ink3)
                        }
                        .padding(12)
                        .background(Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func transcript(day: String, messages: [CoachMessage]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(messages) { m in
                    VStack(alignment: m.isUser ? .trailing : .leading, spacing: 2) {
                        Text(m.text)
                            .font(.custom("Inter-Regular", size: 14))
                            .foregroundStyle(m.isUser ? Color.accentInk : Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(m.isUser ? Color.accent : Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: m.isUser ? .trailing : .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}
