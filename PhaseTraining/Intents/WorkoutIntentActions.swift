import Foundation

/// What each workout App Intent does to the live workout, and the line Siri
/// says back. Mirrors the spoken-command rules in `VoiceLogModel`.
@MainActor
enum WorkoutIntentActions {
    static let noWorkout = "No workout running"
    static let allLogged = "All sets are logged"
    static let noRest = "No rest running"

    /// Log the next-up set with these reps, and the weight when given. The
    /// weight is taken in the exercise's own unit; a bodyweight exercise
    /// ignores it.
    static func logSet(weight: Double?, reps: Int, in c: ActiveWorkoutController?) -> String {
        guard let c else { return noWorkout }
        guard let next = c.nextUp() else { return allLogged }
        guard reps >= 1 else { return "Reps must be at least 1" }
        let isBodyweight = c.session.exercises[next.exIdx].isBodyweight
        c.logSet(exIdx: next.exIdx, setIdx: next.setIdx,
                 weight: isBodyweight ? nil : weight.map(SpokenCue.format),
                 reps: String(reps), rpe: nil)
        return SpokenCue.readback(exercise: c.session.exercises[next.exIdx], setIdx: next.setIdx)
    }

    static func skipRest(in c: ActiveWorkoutController?, now: Date = Date()) -> String {
        guard let c else { return noWorkout }
        guard c.rest.remaining(at: now) != nil else { return noRest }
        c.skipRest()
        return "Rest skipped"
    }

    /// Extend (positive) or cut (negative) the running rest.
    static func addRest(seconds: Int, in c: ActiveWorkoutController?, now: Date = Date()) -> String {
        guard let c else { return noWorkout }
        guard c.rest.remaining(at: now) != nil else { return noRest }
        c.addRest(seconds: seconds)
        if c.rest.remaining(at: now) == nil { return "Rest ended" }
        return seconds < 0 ? "Cut \(abs(seconds)) seconds" : "Added \(seconds) seconds"
    }

    static func whatsNext(in c: ActiveWorkoutController?) -> String {
        guard let c else { return noWorkout }
        guard let next = c.nextUp() else { return allLogged }
        return SpokenCue.upNext(next: next, in: c.session) + "."
    }
}
