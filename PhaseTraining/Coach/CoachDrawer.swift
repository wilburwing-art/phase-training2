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
        HStack(alignment: .top) {
            if message.isUser { Spacer(minLength: 32) }
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
            if !message.isUser { Spacer(minLength: 32) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.lineSoft)
            HStack(spacing: 10) {
                TextField("Ask the coach…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
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

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

        let userMsg = CoachMessage(role: "user", text: text)
        let assistantMsg = CoachMessage(role: "assistant", text: "")
        conv.append(userMsg)
        conv.append(assistantMsg)
        streamingId = assistantMsg.id
        input = ""
        sending = true

        let history = conv.wireHistory().dropLast()  // exclude the new user msg itself
        let snapshot = CoachContext.snapshot(
            activeTab: tabSelection.selected,
            memory: memoryStore.memory,
            plan: planStore.plan,
            recentSessions: sessionStore.savedSessions,
            recentFeedback: memoryStore.memory.feedback,
            recentSoreness: memoryStore.memory.soreness
        )

        inflightTask = Task {
            do {
                let stream = client.stream(
                    cachedSystem: CoachSystemPrompt.cachedHeader,
                    perTurnContext: CoachSystemPrompt.contextBlock(snapshot: snapshot),
                    history: Array(history.dropLast()),
                    userMessage: text
                )
                for try await delta in stream {
                    await MainActor.run {
                        conv.appendDelta(to: assistantMsg.id, delta)
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
}
