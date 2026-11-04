// HoldTimerSheet.swift — counts a timed set: get ready, hang, rest, repeat.
//
// Opened from an exercise in Log whose prescription is timed
// (`HoldProtocol.parse(repsLabel)`): a hangboard max hang ("8s hold"), a
// repeater ("6 hangs (7s on / 3s off)"), a plank or a wall sit. Each phase
// change gets a sound and a haptic so the lifter can watch the edge, not the
// phone. The screen stays awake while it runs.
//
// Stopwatch mode (the ski readiness test's wall sit and balance) counts UP
// after the get-ready until Stop, or until an optional cap, and hands the
// whole seconds back through `onRecord`.

import AudioToolbox
import SwiftUI

struct HoldTimerTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

struct HoldTimerSheet: View {
    enum Mode {
        /// Count down a fixed protocol: hangs, rests, repeats.
        case timed(HoldProtocol)
        /// Count up until Stop or `capSeconds`, then record the seconds.
        case stopwatch(capSeconds: Int?, onRecord: (Int) -> Void)
    }

    let exerciseName: String
    let mode: Mode
    /// Marks the exercise's next undone set done; nil when every set is done.
    let onMarkSetDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(exerciseName: String, hold: HoldProtocol, onMarkSetDone: (() -> Void)?) {
        self.exerciseName = exerciseName
        self.mode = .timed(hold)
        self.onMarkSetDone = onMarkSetDone
    }

    init(exerciseName: String, capSeconds: Int?, onRecord: @escaping (Int) -> Void) {
        self.exerciseName = exerciseName
        self.mode = .stopwatch(capSeconds: capSeconds, onRecord: onRecord)
        self.onMarkSetDone = nil
    }

    /// The fixed protocol in timed mode; a single open-ended hold otherwise,
    /// so the shared phase machinery has something to read.
    private var hold: HoldProtocol {
        if case .timed(let h) = mode { return h }
        return HoldProtocol(onSeconds: 0)
    }

    private var isStopwatch: Bool {
        if case .stopwatch = mode { return true }
        return false
    }

    private var capSeconds: Int? {
        if case .stopwatch(let cap, _) = mode { return cap }
        return nil
    }

    /// Whole seconds a stopwatch run records: floored, never negative,
    /// clamped to the cap when there is one.
    static func recordedSeconds(elapsed: TimeInterval, cap: Int?) -> Int {
        let whole = max(0, Int(elapsed.rounded(.down)))
        return cap.map { min(whole, $0) } ?? whole
    }

    enum Phase: Equatable { case ready, hang, rest, finished }

    @State private var phase: Phase = .ready
    @State private var hangIndex = 1
    @State private var phaseEnd = Date()
    /// When the stopwatch's hold began; elapsed counts from here.
    @State private var phaseStart = Date()
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

    private var elapsed: Int { Self.recordedSeconds(elapsed: now.timeIntervalSince(phaseStart), cap: capSeconds) }

    /// The big number: elapsed while a stopwatch holds, else the countdown.
    private var displayCount: String {
        if phase == .finished { return "Done" }
        if isStopwatch && phase == .hang { return "\(elapsed)" }
        return "\(remaining)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                (phase == .hang ? Color.accentWash : Color.bg).ignoresSafeArea()
                VStack(spacing: 18) {
                    Text(phaseTitle)
                        .styled(.micro)
                        .foregroundStyle(phase == .hang ? Color.accent : Color.ink3)
                        .accessibilityIdentifier("hold-timer-phase")
                    Text(displayCount)
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
            guard running else { return }
            if isStopwatch && phase == .hang {
                if let cap = capSeconds, date.timeIntervalSince(phaseStart) >= TimeInterval(cap) { record() }
            } else if date >= phaseEnd {
                advance()
            }
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
        } else if isStopwatch && phase == .hang {
            Button {
                record()
            } label: {
                Text("Stop").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .foregroundStyle(Color.accentInk)
            .accessibilityIdentifier("hold-timer-stop")
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
        if isStopwatch {
            return capSeconds.map { "Stop when you're done · max \($0)s" } ?? "Stop when you're done"
        }
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

    /// Stopwatch: hand back the seconds held, then close.
    private func record() {
        guard case .stopwatch(let cap, let onRecord) = mode else { return }
        let seconds = Self.recordedSeconds(elapsed: Date().timeIntervalSince(phaseStart), cap: cap)
        running = false
        UIApplication.shared.isIdleTimerDisabled = false
        AudioServicesPlaySystemSound(1322)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onRecord(seconds)
        dismiss()
    }

    private func enter(_ next: Phase) {
        phase = next
        phaseStart = Date()
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
