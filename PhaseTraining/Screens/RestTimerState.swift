// RestTimerState.swift — View-local rest-timer state + inline rest UI for LogScreen.
//
// Extracted from LogScreen.swift (Tier 3 split). The six formerly separate
// rest-timer `@State` fields collapse into one value type so starting and
// clearing a rest is a single coherent mutation. Lives as `@State var rest`
// on LogScreen — view-local, intentionally non-persistent per spec.
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
struct RestTimerState {
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
    mutating func start(exIdx: Int, setIdx: Int, duration: Int, now: Date = Date()) {
        self.exIdx = exIdx
        self.setIdx = setIdx
        self.startedAt = now
        self.duration = duration
        self.alertFiredFor = nil
        self.expiredFlashUntil = nil
        Self.scheduleExpiryNotification(after: duration)
    }

    mutating func clear() {
        exIdx = nil
        setIdx = nil
        startedAt = nil
        duration = nil
        alertFiredFor = nil
        expiredFlashUntil = nil
        Self.cancelExpiryNotification()
    }

    /// Fire-and-forget: request authorization opportunistically, and schedule
    /// only if it's already granted. Rest alerts are not worth a cold permission
    /// prompt mid-workout — WeeklyReminderScheduler already owns the ask.
    static func scheduleExpiryNotification(after seconds: Int) {
        guard seconds > 0 else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [expiryNotificationId])
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest's up"
            content.body = "Time for your next set."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(seconds), repeats: false)
            center.add(UNNotificationRequest(identifier: expiryNotificationId,
                                             content: content,
                                             trigger: trigger))
        }
    }

    /// Re-arm the pending notification after the countdown length changes
    /// in place (+15, or a preset pick). Without this the banner would still
    /// fire at the original expiry time.
    func rescheduleExpiryNotification(now: Date = Date()) {
        guard let remaining = remaining(at: now) else {
            Self.cancelExpiryNotification()
            return
        }
        Self.scheduleExpiryNotification(after: remaining)
    }

    static func cancelExpiryNotification() {
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
                    onAdd15: {
                        rest.duration = (rest.duration ?? 0) + 15
                        rest.rescheduleExpiryNotification()
                    },
                    onSkip: { rest.clear() },
                    onSetDuration: { newDuration in
                        // Reset start time so the new duration runs from now.
                        // Otherwise a shorter pick would have us already expired.
                        rest.duration = newDuration
                        rest.startedAt = Date()
                        rest.alertFiredFor = rest.startedAt
                        rest.rescheduleExpiryNotification()
                    }
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
                    maybeFireRestExpiry(at: now)
                }
                .onAppear { maybeFireRestExpiry(at: ctx.date) }
        }
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
        rest.expiredFlashUntil = date.addingTimeInterval(1.2)
        // We're foregrounded and just played the in-app alert, so drop the
        // pending background banner rather than double-notifying.
        RestTimerState.cancelExpiryNotification()

        // System sound 1322 = "Begin recording" (short, attention-grabbing).
        // Pair with success haptic so the user notices even with the phone
        // silenced or laid screen-down on a bench.
        AudioServicesPlaySystemSound(1322)
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}
