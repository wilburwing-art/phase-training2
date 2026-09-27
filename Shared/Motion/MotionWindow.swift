// MotionWindow.swift — one labeled set's motion (PLAN-watch.md, step 3).
//
// Compiled into both apps. The watch writes these while a workout runs from
// the wrist; the phone stores them. A window is the sensor stream between the
// previous set's done tap (or the end of its rest, whichever is later) and
// this set's done tap, labeled with what the set was. That is the training
// data 4c's classifier needs: every rep the lifter did, with the exercise it
// belongs to, collected without a single extra tap.
//
// File layout (`.ptmotion`): "PTM1", a UInt32 little-endian header length,
// the header as JSON, then `count * 6` Float32 little-endian samples in the
// order userAcceleration x y z, rotationRate x y z. Binary because a 40
// second set at 50 Hz is 48 KB this way and about ten times that as JSON.

import Foundation

struct MotionWindowHeader: Codable, Equatable {
    static let formatVersion = 1

    var formatVersion: Int = MotionWindowHeader.formatVersion
    /// `HealthWorkoutTag.sessionId(for:)` of the session.
    var sessionId: String
    var exerciseId: String
    var exerciseName: String
    var setNum: Int
    var plannedWeight: String
    var plannedReps: Int
    var loggedWeight: String
    var loggedReps: String
    var start: Date
    var end: Date
    var sampleRateHz: Double
    var sampleCount: Int
    /// `WKInterfaceDevice.current().model` plus the watchOS version.
    var device: String
}

struct MotionWindow: Equatable {
    var header: MotionWindowHeader
    /// `header.sampleCount * 6` floats: ax ay az gx gy gz per sample.
    var samples: [Float]

    var duration: TimeInterval { header.end.timeIntervalSince(header.start) }

    /// File name inside a session's directory, unique per set.
    var fileName: String {
        "\(header.exerciseId.replacingOccurrences(of: "/", with: "_"))-set\(header.setNum).ptmotion"
    }
}

enum MotionWindowCodec {
    static let magic = Data("PTM1".utf8)
    static let channels = 6

    enum CodecError: Error, Equatable {
        case badMagic
        case truncated
        case sampleCountMismatch
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func encode(_ window: MotionWindow) throws -> Data {
        guard window.samples.count == window.header.sampleCount * channels else {
            throw CodecError.sampleCountMismatch
        }
        let header = try encoder.encode(window.header)
        var data = Data()
        data.append(magic)
        var length = UInt32(header.count).littleEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(header)
        var floats = window.samples.map { $0.bitPattern.littleEndian }
        floats.withUnsafeMutableBytes { data.append(contentsOf: $0) }
        return data
    }

    static func decode(_ data: Data) throws -> MotionWindow {
        guard data.count >= magic.count + 4, data.prefix(magic.count) == magic else { throw CodecError.badMagic }
        var offset = magic.count
        let length = Int(UInt32(littleEndian: data.subdata(in: offset ..< offset + 4)
            .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
        offset += 4
        guard data.count >= offset + length else { throw CodecError.truncated }
        let header = try decoder.decode(MotionWindowHeader.self, from: data.subdata(in: offset ..< offset + length))
        offset += length
        let floatBytes = data.count - offset
        let expected = header.sampleCount * channels * MemoryLayout<UInt32>.size
        guard floatBytes == expected else { throw CodecError.sampleCountMismatch }
        let body = data.subdata(in: offset ..< data.count)
        var samples = [Float](repeating: 0, count: header.sampleCount * channels)
        body.withUnsafeBytes { raw in
            for i in samples.indices {
                let bits = raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                samples[i] = Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
        return MotionWindow(header: header, samples: samples)
    }

    /// The window a done tap closes: from the later of the previous tap and
    /// the end of the rest that followed it, to this tap. Nil when that is
    /// not a positive span, or shorter than three seconds (a mis-tap, or a
    /// "log all" sweep, carries no reps worth keeping).
    static func window(previousDoneAt: Date?, restEndedAt: Date?, doneAt: Date,
                       sessionStart: Date) -> (start: Date, end: Date)? {
        let candidates = [previousDoneAt, restEndedAt, sessionStart].compactMap { $0 }
        guard let start = candidates.max(), doneAt.timeIntervalSince(start) >= 3 else { return nil }
        return (start, doneAt)
    }
}
