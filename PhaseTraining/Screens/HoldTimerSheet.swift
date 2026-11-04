// HoldTimerSheet.swift — counts a timed set: get ready, hang, rest, repeat.
//
// Opened from an exercise in Log whose prescription is timed
// (`HoldProtocol.parse(repsLabel)`): a hangboard max hang ("8s hold"), a
// repeater ("6 hangs (7s on / 3s off)"), a plank or a wall sit. Each phase
// change gets a sound and a haptic so the lifter can watch the edge, not the
// phone. The screen stays awake while it runs.

import AudioToolbox
import SwiftUI

struct HoldTimerTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

struct HoldTimerSheet: View {
    let exerciseName: String
    let hold: HoldProtocol
    /// Marks the exercise's next undone set done; nil when every set is done.
    let onMarkSetDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable { case ready, hang, rest, finished }

    @State private var phase: Phase = .ready
    @State private var hangIndex = 1
    @State private var phaseEnd = Date()
    @State private var now = Date()
    @State private var running = false

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private static let getReadySeconds = 3

    /// UI-test hook: --ui-test-hold-seconds=N runs every phase for N seconds.
    private static let uiTestSeconds: Int? = {
        let prefix = "--ui-test-hold-seconds="
        return ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
            .flatMap { Int($0.dropFirst(prefix.count)) }
    }()

    private func seconds(_ phase: Phase) -> Int {
        if let s = Self.uiTestSeconds { return s }
        switch phase {
        case .ready: return Self.getReadySeconds
        case .hang: return hold.onSeconds
        case .rest: return hold.offSeconds ?? Self.getReadySeconds
        case .finished: return 0
        }
    }

    private var remaining: Int { max(0, Int(phaseEnd.timeIntervalSince(now).rounded(.up))) }

    var body: some View {
        NavigationStack {
            ZStack {
                (phase == .hang ? Color.accentWash : Color.bg).ignoresSafeArea()
                VStack(spacing: 18) {
                    Text(phaseTitle)
                        .styled(.micro)
                        .foregroundStyle(phase == .hang ? Color.accent : Color.ink3)
                        .accessibilityIdentifier("hold-timer-phase")
                    Text(phase == .finished ? "Done" : "\(remaining)")
                        .font(.scaled("SpaceGrotesk-SemiBold", size: 96))
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                        .accessibilityIdentifier("hold-timer-count")
                    Text(progressLine)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink2)
                    Spacer().frame(height: 12)
                    controls
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onReceive(tick) { date in
            now = date
            if running, date >= phaseEnd { advance() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var controls: some View {
        if phase == .finished {
            if let onMarkSetDone {
                Button {
                    onMarkSetDone()
                    dismiss()
                } label: {
                    Text("Mark set done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .foregroundStyle(Color.accentInk)
                .accessibilityIdentifier("hold-timer-mark-done")
            }
            Button("Run it again") { start() }
                .foregroundStyle(Color.accent)
                .accessibilityIdentifier("hold-timer-again")
        } else if !running {
            Button {
                start()
            } label: {
                Text("Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .foregroundStyle(Color.accentInk)
            .accessibilityIdentifier("hold-timer-start")
        } else {
            Button("Stop") { stop() }
                .foregroundStyle(Color.ink2)
                .accessibilityIdentifier("hold-timer-stop")
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .ready: return running ? "GET READY" : "READY WHEN YOU ARE"
        case .hang: return "HOLD"
        case .rest: return "REST"
        case .finished: return "SET COMPLETE"
        }
    }

    private var progressLine: String {
        let total = hold.hangsPerSet
        var parts = ["\(hold.onSeconds)s on"]
        if let off = hold.offSeconds { parts.append("\(off)s off") }
        if total > 1 { parts.append("\(min(hangIndex, total)) of \(total)") }
        if hold.perSide { parts.append(hangIndex % 2 == 1 ? "first side" : "second side") }
        return parts.joined(separator: " · ")
    }

    private func start() {
        hangIndex = 1
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        enter(.ready)
    }

    private func stop() {
        running = false
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .ready
    }

    private func enter(_ next: Phase) {
        phase = next
        phaseEnd = Date().addingTimeInterval(TimeInterval(seconds(next)))
        now = Date()
        if next != .ready {
            AudioServicesPlaySystemSound(next == .hang ? 1057 : 1322)
            UINotificationFeedbackGenerator().notificationOccurred(next == .hang ? .warning : .success)
        }
    }

    private func advance() {
        switch phase {
        case .ready:
            enter(.hang)
        case .hang:
            if hangIndex >= hold.hangsPerSet {
                running = false
                UIApplication.shared.isIdleTimerDisabled = false
                enter(.finished)
            } else {
                enter(.rest)
            }
        case .rest:
            hangIndex += 1
            enter(.hang)
        case .finished:
            break
        }
    }
}
