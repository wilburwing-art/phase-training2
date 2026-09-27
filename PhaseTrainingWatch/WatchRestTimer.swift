// WatchRestTimer.swift — the rest countdown on the wrist (PLAN-watch.md, step 2).
//
// The same shape as the phone's RestTimerState: anchored to one set, a
// duration that "+15" extends in place, skip clears it. The expiry is a
// haptic, played once per rest from the countdown view's tick, which is
// enough here because the workout session keeps the app running through
// the rest.

import Foundation
import WatchKit

struct WatchRestTimer: Equatable {
    var exerciseId: String? = nil
    var setNum: Int? = nil
    var startedAt: Date? = nil
    var duration: Int? = nil
    /// The rest whose expiry haptic already played.
    var hapticPlayedFor: Date? = nil

    var isActive: Bool { startedAt != nil }

    mutating func start(exerciseId: String, setNum: Int, duration: Int, now: Date = Date()) {
        guard duration > 0 else { clear(); return }
        self.exerciseId = exerciseId
        self.setNum = setNum
        self.startedAt = now
        self.duration = duration
        self.hapticPlayedFor = nil
    }

    mutating func extend(by seconds: Int = 15) {
        guard isActive else { return }
        duration = (duration ?? 0) + seconds
        hapticPlayedFor = nil
    }

    mutating func clear() {
        self = WatchRestTimer()
    }

    func remaining(at date: Date) -> Int? {
        guard let startedAt, let duration else { return nil }
        let r = duration - Int(date.timeIntervalSince(startedAt))
        return r > 0 ? r : nil
    }

    /// Called from the countdown's tick. Plays the haptic once when the rest
    /// runs out, then clears the rest.
    mutating func tick(at date: Date) {
        guard let startedAt, remaining(at: date) == nil else { return }
        if hapticPlayedFor != startedAt {
            hapticPlayedFor = startedAt
            WKInterfaceDevice.current().play(.notification)
        }
        clear()
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
