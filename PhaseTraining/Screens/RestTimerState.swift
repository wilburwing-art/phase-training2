// RestTimerState.swift — View-local rest-timer state + inline rest UI for LogScreen.
//
// Extracted from LogScreen.swift (Tier 3 split). The six formerly separate
// rest-timer `@State` fields collapse into one value type so starting and
// clearing a rest is a single coherent mutation. Lives as `rest`
// on ActiveWorkoutController (LogScreen forwards `rest` to it), intentionally non-persistent per spec.
//
// The rest countdown ticks via `TimelineView(.periodic(...))` inside
// `activeRestCard()`; the TimelineView stays in the same struct as the state
// it reads so re-renders keep driving `maybeFireRestExpiry`.

import SwiftUI
import UIKit
import AudioToolbox
import UserNotifications

/// Rest timer state (view-local, intentionally non-persistent per spec).
/// Initial duration is `ex.rest`; +15 increments `duration` so the countdown
/// extends. Skip clears all fields. Auto-clears when remaining hits 0 (UI just
/// hides; stale state is overwritten on next toggle).
struct RestTimerState: Equatable {
    /// Exercise index (into `session.exercises`) the active rest is anchored
    /// to. nil = no active rest.
    var exIdx: Int? = nil
    /// Set index (within `exIdx`) the active rest is anchored to.
    var setIdx: Int? = nil
    /// When the active rest started.
    var startedAt: Date? = nil
    /// Total countdown length in seconds. "+15" extends it in place.
    var duration: Int? = nil
    /// Date a rest timer was anchored at. Reset whenever a new rest starts so
    /// the expiry-alert fires once per rest instance. nil = no alert pending.
    var alertFiredFor: Date? = nil
    /// Rest start the 10 s spoken warning was handled for. Set whether or not
    /// it spoke, so the warning never fires late.
    var warningFiredFor: Date? = nil
    /// When set, the rest card renders in "expired" flash state. Cleared
    /// ~1.2s after expiry so the card transitions back to a normal hidden state.
    var expiredFlashUntil: Date? = nil

    /// Notification identifier for the backgrounded rest-expiry alert. One at a
    /// time — a new rest replaces the pending one.
    static let expiryNotificationId = "pt.rest_expiry"

    /// Begin a rest and schedule the background alert.
    ///
    /// The in-app alert (sound + haptic) fires from inside the TimelineView
    /// render tick, so it only happens while this screen is on-screen and the
    /// app is foregrounded. A lifter who locks the phone or switches apps
    /// during a 3-minute rest got NOTHING, and on return the sound fired late
    /// against a stale tick date. A local notification covers the backgrounded
    /// case; `maybeFireRestExpiry` still owns the foreground one.
    ///
    /// `cue` is the spoken rest-end line for a locked phone (nil when cues are
    /// off); see `scheduleExpiryNotification`.
    mutating func start(exIdx: Int, setIdx: Int, duration: Int, now: Date = Date(), cue: String? = nil) {
        self.exIdx = exIdx
        self.setIdx = setIdx
        self.startedAt = now
        self.duration = duration
        self.alertFiredFor = nil
        self.warningFiredFor = nil
        self.expiredFlashUntil = nil
        Self.scheduleExpiryNotification(after: duration, now: now, cue: cue)
    }

    mutating func clear() {
        exIdx = nil
        setIdx = nil
        startedAt = nil
        duration = nil
        alertFiredFor = nil
        warningFiredFor = nil
        expiredFlashUntil = nil
        Self.cancelExpiryNotification()
    }

    /// Last-known notification authorization. Lets the foreground expiry
    /// path decide whether the banner will carry the sound or whether it has
    /// to play one itself.
    static var notificationsAuthorized = false

    /// True while the log screen's rest tick is on screen, the only place the
    /// spoken rest-end cue fires. The foreground banner drops its chime only
    /// then; on any other screen the chime is the alert.
    static var restTickOnScreen = false

    /// How long the DONE card stays up after a rest expires. UI-test hook:
    /// `--ui-test-done-flash-seconds=N` holds it longer so a slow simulator
    /// query can still see it. No effect outside test runs.
    static let expiredFlashSeconds: Double = {
        let prefix = "--ui-test-done-flash-seconds="
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
              let seconds = Double(arg.dropFirst(prefix.count)) else { return 1.2 }
        return seconds
    }()

    /// Fire date of the last expiry request, `now + seconds` from the
    /// caller's clock. nil after a cancel. Lets tests check that an injected
    /// clock reaches the notification.
    private(set) static var lastRequestedFireAt: Date?

    /// Sound file name of the last expiry request. nil = `.default`, which
    /// every schedule starts with until a spoken cue render lands in time.
    private(set) static var lastRequestedSoundName: String?

    /// The spoken cue render in flight, if any. Tests await it.
    private(set) static var pendingRender: Task<Void, Never>?

    /// Bumped by every schedule and cancel, so a slow render for an older
    /// rest never replaces a newer request.
    private static var renderGeneration = 0

    /// A render that returns with less than this many seconds left keeps the
    /// `.default` sound rather than racing the trigger.
    static let cueLeadSeconds: Double = 2

    /// Renders a cue line to a `.caf` under `Library/Sounds`.
    static var renderCue: @MainActor (String) async throws -> URL = { line in
        try await VoiceCuePlayer.shared.render(line)
    }

    /// Where rendered cue files live. Notification sounds must sit in
    /// `Library/Sounds` of the app container.
    static var soundsDirectory: URL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Sounds", isDirectory: true)

    /// Fire-and-forget. Asks for notification permission the first time a
    /// rest starts (status .notDetermined) so the "Rest's up" banner works
    /// without the user first having to turn on weekly reminders.
    ///
    /// The request is armed with `.default` first. With a `cue` line, the
    /// line is rendered to a file and the request is replaced with that sound
    /// if the render returns at least `cueLeadSeconds` before the fire date;
    /// a late or failed render leaves the `.default` request standing. The
    /// lock-screen voice needs no `UIBackgroundModes`: the system plays the
    /// notification's own sound.
    static func scheduleExpiryNotification(after seconds: Int, now: Date, cue: String? = nil) {
        guard seconds > 0 else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [expiryNotificationId])
        let fireAt = now.addingTimeInterval(TimeInterval(seconds))
        lastRequestedFireAt = fireAt
        lastRequestedSoundName = nil
        renderGeneration += 1
        pendingRender?.cancel()
        pendingRender = nil
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationsAuthorized = true
                add(fireAt: fireAt, center: center, sound: nil)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    notificationsAuthorized = granted
                    if granted { add(fireAt: fireAt, center: center, sound: nil) }
                }
            default:
                notificationsAuthorized = false
            }
        }
        guard let cue, !cue.isEmpty else {
            deleteCueFiles(keeping: nil)
            return
        }
        let generation = renderGeneration
        let renderStarted = Date()
        pendingRender = Task { @MainActor in
            let url = try? await renderCue(cue)
            guard generation == renderGeneration else { return }
            let left = Double(seconds) - Date().timeIntervalSince(renderStarted)
            guard let url, left >= cueLeadSeconds else {
                deleteCueFiles(keeping: nil)
                return
            }
            let name = url.lastPathComponent
            lastRequestedSoundName = name
            deleteCueFiles(keeping: name)
            if notificationsAuthorized {
                add(fireAt: fireAt, center: center,
                    sound: UNNotificationSound(named: UNNotificationSoundName(name)))
            }
        }
    }

    private static func add(fireAt: Date, center: UNUserNotificationCenter, sound: UNNotificationSound?) {
        // Measure from the original request time so a slow permission prompt
        // doesn't push the alert late.
        let seconds = fireAt.timeIntervalSinceNow
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = "Time for your next set."
        content.sound = sound ?? .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        // Same identifier, so this replaces the `.default` request.
        center.add(UNNotificationRequest(identifier: expiryNotificationId,
                                         content: content,
                                         trigger: trigger))
    }

    /// Remove rendered cue files other than `keeping` (a file name).
    static func deleteCueFiles(keeping: String?) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: soundsDirectory.path) else { return }
        for name in names where name.hasPrefix("pt_speech_") && name.hasSuffix(".caf") && name != keeping {
            try? fm.removeItem(at: soundsDirectory.appendingPathComponent(name))
        }
    }

    /// Re-arm the pending notification after the countdown length changes
    /// in place (+15, or a preset pick). Without this the banner would still
    /// fire at the original expiry time. Re-renders `cue` against the new
    /// remaining time.
    func rescheduleExpiryNotification(now: Date = Date(), cue: String? = nil) {
        guard let remaining = remaining(at: now) else {
            Self.cancelExpiryNotification()
            return
        }
        Self.scheduleExpiryNotification(after: remaining, now: now, cue: cue)
    }

    static func cancelExpiryNotification() {
        lastRequestedFireAt = nil
        lastRequestedSoundName = nil
        renderGeneration += 1
        pendingRender?.cancel()
        pendingRender = nil
        deleteCueFiles(keeping: nil)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [expiryNotificationId])
    }

    func remaining(at date: Date) -> Int? {
        guard let started = startedAt, let duration = duration else { return nil }
        let elapsed = Int(date.timeIntervalSince(started))
        let r = duration - elapsed
        return r > 0 ? r : nil
    }
}

// MARK: - Inline rest UI

extension LogScreen {
    func restDivider(seconds: Int) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.lineSoft).frame(height: 0.5).frame(maxWidth: .infinity)
            Text(Self.fmtTime(seconds))
                .styled(.monoXS)
                .foregroundStyle(Color.accentDim)
            Rectangle().fill(Color.lineSoft).frame(height: 0.5).frame(maxWidth: .infinity)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    func activeRestCard() -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
            let remaining = rest.remaining(at: ctx.date)
            let isFlashing = rest.expiredFlashUntil.map { ctx.date < $0 } ?? false
            if let r = remaining, r > 0 {
                RestTimer(
                    remaining: r,
                    expired: false,
                    onAdd15: { workout.addRest(seconds: 15) },
                    // Shortening to nothing ends the rest rather than flashing DONE.
                    onSubtract15: { workout.addRest(seconds: -15) },
                    onSkip: { workout.skipRest() },
                    onSetDuration: { workout.setRestDuration($0) }
                )
                .padding(.vertical, 6)
                .transition(.opacity)
                // No parent accessibilityIdentifier — in iOS 26 that overrides
                // every child identifier (log-rest-add15, log-rest-skip,
                // log-rest-time, log-rest-preset-30, …) so the UI tests can't
                // find the chips inside.
                .onAppear { /* TimelineView re-renders trigger checkExpiry */ }
            } else if isFlashing {
                // Brief "DONE" flash after expiry — show 0:00 in the expired
                // style for ~1.2s, then disappear.
                RestTimer(
                    remaining: 0,
                    expired: true,
                    onAdd15: {},
                    onSkip: { rest.expiredFlashUntil = nil; rest.clear() },
                    onSetDuration: nil
                )
                .padding(.vertical, 6)
                .transition(.opacity)
            } else {
                Color.clear.frame(height: 0)
            }

            // Fire the expiry alert exactly once per rest instance. Side
            // effect lives inside the TimelineView render so it polls every
            // tick (1Hz) without an extra timer.
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: ctx.date) { _, now in
                    maybeFireRestWarning(at: now)
                    maybeFireRestExpiry(at: now)
                }
                .onAppear {
                    RestTimerState.restTickOnScreen = true
                    maybeFireRestWarning(at: ctx.date)
                    maybeFireRestExpiry(at: ctx.date)
                }
                .onDisappear { RestTimerState.restTickOnScreen = false }
        }
    }

    /// Speak the 10 s warning once per rest when the rest is at least 20 s long.
    private func maybeFireRestWarning(at date: Date) {
        guard let started = rest.startedAt,
              let duration = rest.duration,
              duration >= 20,
              rest.warningFiredFor != started else { return }
        let remaining = Double(duration) - date.timeIntervalSince(started)
        guard remaining > 0, remaining <= 10 else { return }
        rest.warningFiredFor = started
        VoiceCuePlayer.shared.restWarning(session: session, next: workout.nextUp())
    }

    /// Trigger sound + haptic + visual flash once when the active rest
    /// transitions to zero. Guarded by `rest.alertFiredFor` so consecutive
    /// TimelineView re-renders don't replay the alert.
    private func maybeFireRestExpiry(at date: Date) {
        guard let started = rest.startedAt,
              let duration = rest.duration,
              rest.alertFiredFor != started else { return }
        let elapsed = date.timeIntervalSince(started)
        guard elapsed >= Double(duration) else { return }

        rest.alertFiredFor = started
        rest.expiredFlashUntil = date.addingTimeInterval(RestTimerState.expiredFlashSeconds)
        // Leave the pending "Rest's up" notification alone: NotificationDelegate
        // presents it as a banner (with sound unless the cue speaks) even while
        // the app is open. Play our own sound only when neither the cue nor the
        // banner will make one.
        let spoke = VoiceCuePlayer.shared.restEnded(session: session, next: workout.nextUp())
        if !spoke && !RestTimerState.notificationsAuthorized {
            // System sound 1322 = "Begin recording" (short, attention-grabbing).
            AudioServicesPlaySystemSound(1322)
        }
        // Success haptic so the user notices even with the phone silenced
        // or laid screen-down on a bench.
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        // Lock Screen countdown flips to "Rest done" (no-op without a Live Activity).
        RestActivityCenter.shared.restExpired()
        // VoiceOver users hear the expiry; the flash and haptic are not spoken.
        AccessibilityNotification.Announcement("Rest done").post()
    }
}
