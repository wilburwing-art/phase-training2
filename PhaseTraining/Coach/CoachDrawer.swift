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

    private let client = CoachClient()

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
            if !conv.messages.isEmpty {
                Button {
                    conv.clearToday()
                } label: {
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
            Text("The coach can read your week, recent sessions, and feedback. It can't change anything yet — that's coming. Try:")
                .styled(.body)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                suggestionChip("Why is Thursday a lift day?")
                suggestionChip("What patterns do you see in my feedback?")
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
            recentSportLogs: Array(recentSportLogs)
        )

        inflightTask = Task {
            do {
                let stream = client.stream(
                    cachedSystem: CoachSystemPrompt.cachedHeader,
                    perTurnContext: CoachSystemPrompt.contextBlock(snapshot: snapshot),
                    history: Array(history.dropLast()),
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
                        switch name {
                        case "propose_plan_edits":
                            if let proposal = CoachToolDecoder.decodeProposal(from: inputData) {
                                await MainActor.run { conv.setProposal(on: assistantMsg.id, proposal) }
                            }
                        case "propose_workout_changes":
                            // Build 99: pass today as the FALLBACK, not as
                            // an override. If the model supplied a `date`
                            // in the tool input it wins — chat can now
                            // edit any day in the current plan, not just
                            // today.
                            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
                            let today = df.string(from: Date())
                            if let proposal = CoachToolDecoder.decodeWorkoutProposal(from: inputData, fallbackDate: today) {
                                await MainActor.run { conv.setWorkoutProposal(on: assistantMsg.id, proposal) }
                            }
                        case "propose_memory_update":
                            if let proposal = CoachToolDecoder.decodeMemoryProposal(from: inputData) {
                                await MainActor.run { conv.setMemoryProposal(on: assistantMsg.id, proposal) }
                            }
                        default:
                            continue
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

    private func finishError(_ error: Error) {
        if let id = streamingId,
           let idx = conv.messages.firstIndex(where: { $0.id == id }) {
            let prefix = conv.messages[idx].text.isEmpty ? "" : conv.messages[idx].text + "\n\n"
            conv.messages[idx].text = prefix + "⚠️ \(error.localizedDescription)"
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
