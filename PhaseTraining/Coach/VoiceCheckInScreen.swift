// VoiceCheckInScreen.swift — talk to the coach with no keyboard (voice 3.2).
//
// Push-to-talk feeds `CoachTurnRunner`; the streamed reply is spoken a
// sentence at a time and lands in the same per-day thread the drawer shows.
// Tap the reply (or Stop) to stop speaking. Offered only where the coach can
// answer: `VoiceCheckInModel.isOffered` gates every entry point.

import SwiftUI

struct VoiceCheckInScreen: View {
    @EnvironmentObject private var conv: CoachConversationStore
    @EnvironmentObject private var memoryStore: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var tabSelection: TabSelectionStore
    @EnvironmentObject private var sportLogStore: SportLogStore

    var body: some View {
        VoiceCheckInContent(conv: conv) { [memoryStore, planStore, sessionStore, tabSelection, sportLogStore] in
            CoachTurnRunner.chatContext(
                activeTab: tabSelection.selected,
                memoryStore: memoryStore,
                planStore: planStore,
                sessionStore: sessionStore,
                sportLogStore: sportLogStore
            )
        }
    }
}

private struct VoiceCheckInContent: View {
    @ObservedObject var conv: CoachConversationStore
    @StateObject private var model: VoiceCheckInModel
    @State private var pressStart: Date?
    @State private var stopOnLift = false

    private static let holdSeconds: TimeInterval = 0.35

    init(conv: CoachConversationStore, context: @escaping @MainActor () -> String) {
        self.conv = conv
        let output = VoiceCuePlayer.shared.speechOutput
        (output as? SpeechOutput)?.voiceIdentifier = VoiceSettings.load(from: .standard).voiceId
        _model = StateObject(wrappedValue: VoiceCheckInModel(
            conv: conv,
            runner: CoachTurnRunner(conv: conv),
            output: output,
            context: context
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.lineSoft)
            transcript
            micArea
        }
        .background(Color.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onDisappear { model.cancel() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .scaledSystemFont(13, weight: .semibold)
                .foregroundStyle(Color.accent)
            Text("VOICE CHECK-IN")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Spacer()
            Button { conv.voicePresented = false } label: {
                Text("DONE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink2)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close voice check-in")
            .accessibilityIdentifier("voice-checkin-done")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if conv.messages.isEmpty, !isListening {
                        Text("Hold the mic and tell the coach how training is going.")
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                            .padding(.top, 24)
                    }
                    ForEach(conv.messages) { message in
                        line(message).id(message.id)
                    }
                    if case .listening(let partial) = model.inputState {
                        Text(partial.isEmpty ? "Listening…" : partial)
                            .font(.scaled("Inter-Regular", size: 16))
                            .foregroundStyle(Color.ink2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityIdentifier("voice-checkin-partial")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.stopSpeaking() }
            .onChange(of: conv.messages.last?.text) { _, _ in
                withAnimation(nil) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.inputState) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func line(_ message: CoachMessage) -> some View {
        Text(message.text.isEmpty && !message.isUser ? "…" : message.text)
            .font(.scaled("Inter-Regular", size: 16))
            .foregroundStyle(message.isUser ? Color.ink2 : Color.ink)
            .multilineTextAlignment(message.isUser ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
            .accessibilityLabel(message.isUser ? "You said: \(message.text)" : "Coach: \(message.text)")
    }

    private var micArea: some View {
        VStack(spacing: 12) {
            if let notice = model.notice {
                Text(notice)
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("voice-checkin-notice")
            }
            if model.replying {
                Button { model.stopSpeaking() } label: {
                    Label("Stop speaking", systemImage: "speaker.slash.fill")
                        .font(.scaled("Inter-Regular", size: 14).weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color.surface))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("voice-checkin-stop")
            }
            micButton
            Text(isListening ? "Release to send" : "Hold to talk")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var isListening: Bool {
        if case .listening = model.inputState { return true }
        return false
    }

    private var isUnavailable: Bool {
        if case .unavailable = model.inputState { return true }
        return false
    }

    private var micButton: some View {
        Image(systemName: isListening ? "mic.fill" : (isUnavailable ? "mic.slash" : "mic"))
            .scaledSystemFont(30, weight: .semibold, within: 80)
            .foregroundStyle(isListening ? Color.accentInk : Color.ink)
            .frame(width: 80, height: 80)
            .background(isListening ? Color.accent : Color.surface)
            .clipShape(Circle())
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in touchDown() }
                    .onEnded { _ in touchUp() }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Talk to coach")
            .accessibilityHint("Double tap to talk, double tap again to send")
            .accessibilityAddTraits(isListening ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { toggle() }
            .accessibilityIdentifier("voice-checkin-mic")
    }

    // Same tap-or-hold contract as `VoiceMicButton` on the log screen.
    private func touchDown() {
        guard pressStart == nil else { return }
        pressStart = Date()
        stopOnLift = isListening
        if !stopOnLift { Task { await model.pressDown() } }
    }

    private func touchUp() {
        defer { pressStart = nil }
        guard let start = pressStart else { return }
        if stopOnLift || Date().timeIntervalSince(start) > Self.holdSeconds {
            Task { await model.release() }
        }
    }

    private func toggle() {
        Task {
            if isListening { await model.release() } else { await model.pressDown() }
        }
    }
}
