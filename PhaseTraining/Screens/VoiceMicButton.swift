import SwiftUI
import UIKit

/// Push-to-talk button for the log header. A tap starts listening and a second
/// tap stops. A press held past `holdSeconds` listens until the finger lifts.
struct VoiceMicButton: View {
    @ObservedObject var model: VoiceLogModel
    @State private var pressStart: Date?
    @State private var stopOnLift = false

    private static let holdSeconds: TimeInterval = 0.35

    private var isListening: Bool {
        if case .listening = model.inputState { return true }
        return false
    }

    private var isUnavailable: Bool {
        if case .unavailable = model.inputState { return true }
        return false
    }

    private var symbol: String {
        if isListening { return "mic.fill" }
        return isUnavailable ? "mic.slash" : "mic"
    }

    var body: some View {
        Image(systemName: symbol)
            .scaledSystemFont(14, weight: .semibold, within: 28)
            .foregroundStyle(isListening ? Color.accentInk : Color.ink2)
            .frame(width: 28, height: 28)
            .background(isListening ? Color.accent : Color.surface)
            .clipShape(Circle())
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in touchDown() }
                    .onEnded { _ in touchUp() }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Voice log")
            .accessibilityHint("Double tap to talk, double tap again to stop")
            .accessibilityInputLabels(["Voice log", "Microphone", "Talk"])
            .accessibilityAddTraits(isListening ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { toggle() }
            .accessibilityIdentifier("log-voice-mic")
    }

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

    /// VoiceOver activation: no touch down and up, so it toggles.
    private func toggle() {
        Task {
            if isListening { await model.release() } else { await model.pressDown() }
        }
    }
}

/// Under the sticky header: the live partial while listening, else the card for the last command.
struct VoiceHeardOverlay: View {
    @ObservedObject var model: VoiceLogModel

    var body: some View {
        Group {
            if case .listening(let partial) = model.inputState {
                Text(partial.isEmpty ? "Listening…" : partial)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(cardBackground)
                    .accessibilityIdentifier("log-voice-listening")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            } else if let card = model.card {
                VoiceHeardCardView(model: model, card: card)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface)
    }
}

struct VoiceHeardCardView: View {
    @ObservedObject var model: VoiceLogModel
    let card: HeardCard

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if !card.heard.isEmpty {
                    Text("\u{201C}\(card.heard)\u{201D}")
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(2)
                }
                Text(card.message)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("log-voice-card")

            if card.undoable && model.cardIsLive(at: Date()) {
                Button { model.undo() } label: {
                    Text("Undo")
                        .font(.scaled("Inter-Regular", size: 13).weight(.bold))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.accentBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log-voice-undo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface))
        .task(id: card.shownAt) {
            UIAccessibility.post(notification: .announcement, argument: card.message)
            try? await Task.sleep(for: .seconds(VoiceLogModel.cardSeconds))
            guard !Task.isCancelled else { return }
            model.dismissCard(shownAt: card.shownAt)
        }
    }
}
