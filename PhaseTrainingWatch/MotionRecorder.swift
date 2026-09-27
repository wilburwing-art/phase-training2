// MotionRecorder.swift — wrist motion while a workout runs (PLAN-watch.md, step 3).
//
// Device motion at 50 Hz from CoreMotion into a ring buffer, for as long as
// the HKWorkoutSession keeps the app alive. A done tap cuts the window that
// ends at the tap (`MotionWindowCodec.window`), labels it, writes it as a
// `.ptmotion` file and hands it to WatchConnectivity, which moves it to the
// phone when it can. Nothing stays on the watch once the transfer is queued.
//
// 50 Hz through CMMotionManager needs no special entitlement.
// CMBatchedSensorManager (watchOS 10) delivers far higher rates during a
// workout and is the upgrade once the hardware check in step 0 says what it
// really delivers; the file format carries `sampleRateHz`, so files from
// either are readable.

import Foundation
import CoreMotion
import OSLog
import WatchConnectivity
import WatchKit

@MainActor
final class MotionRecorder {

    static let sampleRateHz = 50.0
    /// Ten minutes of samples: longer than any rest plus set.
    private static let capacity = Int(sampleRateHz * 600)

    private struct Sample {
        let at: Date
        let values: (Float, Float, Float, Float, Float, Float)
    }

    private let manager = CMMotionManager()
    private var buffer: [Sample] = []
    private(set) var isRecording = false
    private static let log = Logger(subsystem: "com.phasetraining.app.watchkitapp", category: "motion")

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard !isRecording, manager.isDeviceMotionAvailable else { return }
        buffer.removeAll(keepingCapacity: true)
        manager.deviceMotionUpdateInterval = 1 / Self.sampleRateHz
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion else {
                if let error { Self.log.error("device motion: \(error.localizedDescription, privacy: .public)") }
                return
            }
            let a = motion.userAcceleration, g = motion.rotationRate
            self.buffer.append(Sample(at: Date(timeIntervalSince1970: motion.timestamp.bootRelativeToUnix),
                                      values: (Float(a.x), Float(a.y), Float(a.z), Float(g.x), Float(g.y), Float(g.z))))
            if self.buffer.count > Self.capacity { self.buffer.removeFirst(self.buffer.count - Self.capacity) }
        }
        isRecording = true
        Self.log.notice("recording at \(Self.sampleRateHz) Hz")
    }

    func stop() {
        guard isRecording else { return }
        manager.stopDeviceMotionUpdates()
        buffer.removeAll()
        isRecording = false
    }

    /// Cut, label and send the window for a set that was just marked done.
    /// Returns false when there was nothing to send (no recording, no
    /// samples in the span).
    @discardableResult
    func send(sessionStart: Date, exercise: LoggedExercise, set: LoggedSet, start: Date, end: Date) -> Bool {
        guard isRecording else { return false }
        let inWindow = buffer.filter { $0.at >= start && $0.at <= end }
        guard !inWindow.isEmpty else { return false }
        var samples: [Float] = []
        samples.reserveCapacity(inWindow.count * MotionWindowCodec.channels)
        for s in inWindow {
            samples.append(contentsOf: [s.values.0, s.values.1, s.values.2, s.values.3, s.values.4, s.values.5])
        }
        let device = "\(WKInterfaceDevice.current().model) watchOS \(WKInterfaceDevice.current().systemVersion)"
        let header = MotionWindowHeader(sessionId: HealthWorkoutTag.sessionId(for: sessionStart),
                                        exerciseId: exercise.id, exerciseName: exercise.name, setNum: set.num,
                                        plannedWeight: set.weight, plannedReps: exercise.targetReps,
                                        loggedWeight: set.weight, loggedReps: set.reps,
                                        start: start, end: end, sampleRateHz: Self.sampleRateHz,
                                        sampleCount: inWindow.count, device: device)
        let window = MotionWindow(header: header, samples: samples)
        do {
            let data = try MotionWindowCodec.encode(window)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(window.fileName)
            try data.write(to: url, options: .atomic)
            WCSession.default.transferFile(url, metadata: ["sessionId": header.sessionId, "fileName": window.fileName])
            Self.log.notice("window sent: \(window.fileName, privacy: .public), \(inWindow.count) samples, \(data.count) bytes")
            return true
        } catch {
            Self.log.error("window write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

private extension TimeInterval {
    /// CoreMotion timestamps are seconds since boot; the windowing rule works
    /// in wall-clock dates.
    var bootRelativeToUnix: TimeInterval {
        Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime + self
    }
}
