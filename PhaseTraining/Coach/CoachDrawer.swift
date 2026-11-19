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
    @StateObject private var runner: CoachTurnRunner
    @FocusState private var inputFocused: Bool
    @State private var confirmingClear = false
    @State private var showingHistory = false

    init(conv: CoachConversationStore) {
        _runner = StateObject(wrappedValue: CoachTurnRunner(conv: conv))
    }

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
        .onDisappear { runner.cancel() }
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
                .scaledSystemFont(13, weight: .semibold)
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
                    .scaledSystemFont(13, weight: .semibold, within: 28)
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
                .font(.scaled("SpaceGrotesk-SemiBold", size: 22))
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
                    .scaledSystemFont(10, weight: .semibold)
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
                        .font(.scaled("Inter-Regular", size: 14))
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
                    .font(.scaled("Inter-Regular", size: 14))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineStrong, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: runner.sending ? "stop.fill" : "arrow.up")
                        .scaledSystemFont(16, weight: .bold, within: 38)
                        .foregroundStyle(canSend || runner.sending ? Color.accentInk : Color.ink3)
                        .frame(width: 38, height: 38)
                        .background(canSend || runner.sending ? Color.accent : Color.elevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(runner.sending ? "Stop" : "Send")
                .disabled(!canSend && !runner.sending)
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
                .scaledSystemFont(12, weight: .semibold)
                .foregroundStyle(hard ? Color.ink2 : Color.accent)
            Text(hard
                 ? "Daily coaching limit reached. Pick this up tomorrow. Your plan and history stay put."
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
        if runner.sending {
            runner.cancel()
            return
        }
        let context = CoachTurnRunner.chatContext(
            activeTab: tabSelection.selected,
            memoryStore: memoryStore,
            planStore: planStore,
            sessionStore: sessionStore,
            sportLogStore: sportLogStore
        )
        if runner.send(input, context: context) {
            input = ""
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withMotion(.easeOut(duration: 0.15), .movement) {
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
    return CoachDrawer(conv: conv)
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
                                .scaledSystemFont(11, weight: .semibold)
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
                            .font(.scaled("Inter-Regular", size: 14))
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
