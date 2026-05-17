// Planner.swift — pure rules-based week generator.
//
// Inputs: TrainingMemory (long-term truth) + WeekOverrides (per-week edits)
// + the routine catalog. Output: a WeekPlan whose inputsHash is the memory
// hash so PlanStore can detect drift.
//
// Algorithm (deterministic):
//   1. Resolve a WeeklyShape from (primarySport, season, focus).
//   2. Place WeekOverrides.events (sport sessions + races) — protected.
//   3. Force rest on weekdays in WeekOverrides.unavailableDays.
//   4. Fill remaining empty slots from the shape queue (skipping shape sport
//      slots already satisfied by event sport-sessions).
//   5. Apply the user's lift-days target.
//   6. For each .lift / .mobility slot, pick a coach.db routine matching
//      goal + difficulty + duration. Selection is deterministic via
//      inputsHash + slot offset.
//   7. Taper: for each .race event marked .hard intensity, the immediately
//      preceding lift slot is converted to .rest so the user isn't sore.

import Foundation

enum Planner {

    static func generate(
        memory: TrainingMemory,
        overrides: WeekOverrides? = nil,
        routines: [Routine],
        previousFeedback: [FeedbackEntry] = [],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> WeekPlan {
        let biased = applyFeedbackBias(memory: memory, feedback: previousFeedback, calendar: calendar)
        return generateUnbiased(
            memory: biased,
            overrides: overrides,
            routines: routines,
            today: today,
            calendar: calendar
        )
    }

    /// Inspect the most recent 7-day feedback window and nudge the memory
    /// before planning. Conservative — at most ±1 lift day per regen so
    /// repeated "too hard" weeks don't collapse to zero in one shot.
    static func applyFeedbackBias(
        memory: TrainingMemory,
        feedback: [FeedbackEntry],
        calendar: Calendar = .current
    ) -> TrainingMemory {
        guard !feedback.isEmpty else { return memory }
        let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        let recent = feedback.filter { $0.date >= cutoff }
        let tooHard = recent.filter { $0.difficulty == "too_hard" }.count
        let tooEasy = recent.filter { $0.difficulty == "too_easy" }.count

        var adjusted = memory
        if tooHard >= 2 && tooHard > tooEasy {
            adjusted.liftDaysPerWeek = max(0, adjusted.liftDaysPerWeek - 1)
        } else if tooEasy >= 2 && tooEasy > tooHard {
            // Planner's per-week loop already caps against actual empty slots.
            adjusted.liftDaysPerWeek = min(6, adjusted.liftDaysPerWeek + 1)
        }
        return adjusted
    }

    private static func generateUnbiased(
        memory: TrainingMemory,
        overrides: WeekOverrides?,
        routines: [Routine],
        today: Date,
        calendar: Calendar
    ) -> WeekPlan {
        let start = calendar.startOfDay(for: today)
        let dates: [Date] = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let shape = WeeklyShape.resolve(
            primarySport: memory.primarySport,
            season: memory.seasonForPlanner,
            focus: memory.primaryFocus
        )

        var slots: [DayPlan?] = Array(repeating: nil, count: 7)

        // Step 1 — events from the per-week overrides (sport sessions + races).
        if let overrides {
            for (i, date) in dates.enumerated() {
                guard let event = overrides.events(on: date, calendar: calendar).first else { continue }
                slots[i] = makeEventSlot(date: date, event: event)
            }
        }

        // Step 2 — force rest on overridden unavailable weekdays.
        if let overrides, !overrides.unavailableDays.isEmpty {
            for (i, date) in dates.enumerated() where slots[i] == nil {
                let weekday = Weekday.from(date: date, calendar: calendar)
                if overrides.unavailableDays.contains(weekday) {
                    slots[i] = DayPlan(
                        date: date,
                        kind: .rest,
                        title: "Rest",
                        generatedReason: "You marked \(weekday.short) as off this week"
                    )
                }
            }
        }

        // Step 3 — apply per-day kind overrides (Move-to-day swaps, force-kind).
        // These are protected so subsequent rules can't undo them.
        if let overrides {
            for (i, date) in dates.enumerated() where slots[i] == nil {
                guard let ov = overrides.override(on: date, calendar: calendar) else { continue }
                slots[i] = makeOverrideSlot(date: date, override: ov, memory: memory, routines: routines)
            }
        }

        // Step 4 — build remaining shape queue, accounting for shape sport slots
        // already satisfied by sport-session events (NOT race events; races
        // express something different and shouldn't consume a sport quota).
        let placedSportSessions = slots.compactMap { $0 }
            .filter { $0.kind == .sport }
            .count
        var queue: [DayKind] = []
        var sportsToSkip = placedSportSessions
        for kind in shape.kinds {
            if kind == .sport && sportsToSkip > 0 {
                sportsToSkip -= 1
                continue
            }
            queue.append(kind)
        }

        // Step 5 — apply user's lift-days target, accounting for lifts already
        // placed via dayOverrides. Shape's lift count is a default; the user
        // override wins. Demote excess lifts from the end (preserves the
        // shape's early-week emphasis); promote rest → lift biased to maximum
        // spacing from existing lifts when adding.
        let placedLifts = slots.compactMap { $0 }.filter { $0.kind == .lift }.count
        let emptyCount = slots.filter { $0 == nil }.count
        let usedQueue = Array(queue.prefix(emptyCount))
        let liftBudget = max(0, min(memory.liftDaysPerWeek - placedLifts, emptyCount))
        let adjustedQueue = adjustForLiftBudget(usedQueue, target: liftBudget)

        // Step 6 — walk adjusted queue, fill empty slots.
        // First pass: lay down the kinds. Lift indexing happens in the
        // second pass so we know totalLifts before generating workouts.
        var qi = 0
        var pendingKinds: [(idx: Int, date: Date, kind: DayKind)] = []
        for (i, date) in dates.enumerated() where slots[i] == nil {
            guard qi < adjustedQueue.count else {
                slots[i] = DayPlan(
                    date: date,
                    kind: .rest,
                    title: "Rest",
                    generatedReason: "No more shape slots"
                )
                continue
            }
            pendingKinds.append((i, date, adjustedQueue[qi]))
            qi += 1
        }

        // Generated-workout pass: compute total lifts in this regen,
        // then walk pendingKinds in date order assigning a lift index
        // so the workout generator can pick A/B/push/pull/legs/etc.
        let profile = DemographicProfile.from(memory)
        let totalLifts = pendingKinds.filter { $0.kind == .lift }.count
            + slots.compactMap { $0 }.filter { $0.kind == .lift }.count
        var liftCursor = 0
        for entry in pendingKinds {
            slots[entry.idx] = makeSlot(
                date: entry.date,
                kind: entry.kind,
                memory: memory,
                profile: profile,
                routines: routines,
                shapeDescription: shape.description,
                slotOffset: entry.idx,
                liftIndex: entry.kind == .lift ? liftCursor : 0,
                totalLifts: totalLifts
            )
            if entry.kind == .lift { liftCursor += 1 }
        }

        // Step 7 — best-practice rules. Each pass mutates only NON-protected slots.
        if let overrides {
            applyPreEventTaper(&slots, dates: dates, overrides: overrides, calendar: calendar)
            applyPostEventRecovery(&slots, dates: dates, overrides: overrides, calendar: calendar)
            applyPreSportBuffer(&slots, dates: dates, overrides: overrides, calendar: calendar)
        }

        let days = slots.compactMap { $0 }
        return WeekPlan(
            days: days,
            generatedAt: Date(),
            inputsHash: memory.planInputsHash
        )
    }

    // MARK: - Day-override slot

    private static func makeOverrideSlot(
        date: Date,
        override: DayKindOverride,
        memory: TrainingMemory,
        routines: [Routine]
    ) -> DayPlan {
        switch override {
        case .rest:
            return DayPlan(date: date, kind: .rest, title: "Rest",
                           protected: true,
                           generatedReason: "You set this day to rest")

        case .mobility(let routineId):
            // User picked a specific routine → honor it; else generate a
            // fresh mobility flow from the profile so the day isn't empty.
            if let id = routineId, let r = routines.first(where: { $0.id == id }) {
                return DayPlan(date: date, kind: .mobility,
                               title: r.name,
                               routineId: r.id,
                               protected: true,
                               generatedReason: "You picked this routine for this day")
            }
            let profile = DemographicProfile.from(memory)
            let workout = WorkoutGenerator.generateMobility(
                memory: memory,
                profile: profile,
                hashSeed: memory.planInputsHash + "-mob-override"
            )
            return DayPlan(date: date, kind: .mobility,
                           title: workout.title,
                           generatedWorkout: workout,
                           protected: true,
                           generatedReason: "You set this day to mobility")

        case .lift(let routineId):
            if let id = routineId, let r = routines.first(where: { $0.id == id }) {
                return DayPlan(date: date, kind: .lift,
                               title: r.name,
                               routineId: r.id,
                               protected: true,
                               generatedReason: "You picked this routine for this day")
            }
            let profile = DemographicProfile.from(memory)
            let workout = WorkoutGenerator.generateLift(
                liftIndex: 0,
                totalLifts: 1,
                memory: memory,
                profile: profile,
                hashSeed: memory.planInputsHash + "-lift-override"
            )
            return DayPlan(date: date, kind: .lift,
                           title: workout.title,
                           generatedWorkout: workout,
                           protected: true,
                           generatedReason: "You set this day to lift")

        case .sport(let slug):
            let sport = (slug ?? memory.primarySport?.slug).flatMap { s in
                Sport.catalog.first(where: { $0.slug == s })
            } ?? memory.primarySport
            return DayPlan(date: date, kind: .sport,
                           title: sport.map { "\($0.name) session" } ?? "Sport day",
                           sport: sport,
                           protected: true,
                           generatedReason: "You set this day to sport")
        }
    }

    // MARK: - Event slot

    private static func makeEventSlot(date: Date, event: WeekEvent) -> DayPlan {
        switch event.kind {
        case .sportSession:
            return DayPlan(
                date: date,
                kind: .sport,
                title: event.title.isEmpty
                    ? (event.sport.map { "\($0.name) session" } ?? "Sport session")
                    : event.title,
                sport: event.sport,
                protected: true,
                generatedReason: "You scheduled this for \(weekdayShort(date))"
            )
        case .race:
            return DayPlan(
                date: date,
                kind: .event,
                title: event.title.isEmpty ? "Event" : event.title,
                sport: event.sport,
                protected: true,
                generatedReason: "Event you scheduled (\(event.intensity.label.lowercased()) intensity)"
            )
        }
    }

    // MARK: - Slot construction

    private static func makeSlot(
        date: Date,
        kind: DayKind,
        memory: TrainingMemory,
        profile: DemographicProfile,
        routines: [Routine],
        shapeDescription: String,
        slotOffset: Int,
        liftIndex: Int,
        totalLifts: Int
    ) -> DayPlan {
        switch kind {
        case .lift:
            let workout = WorkoutGenerator.generateLift(
                liftIndex: liftIndex,
                totalLifts: totalLifts,
                memory: memory,
                profile: profile,
                hashSeed: memory.planInputsHash
            )
            return DayPlan(
                date: date,
                kind: .lift,
                title: workout.title,
                generatedWorkout: workout,
                generatedReason: workout.provenance
            )
        case .mobility:
            let workout = WorkoutGenerator.generateMobility(
                memory: memory,
                profile: profile,
                hashSeed: memory.planInputsHash + "-mob-\(slotOffset)"
            )
            return DayPlan(
                date: date,
                kind: .mobility,
                title: workout.title,
                generatedWorkout: workout,
                generatedReason: workout.provenance
            )
        case .sport:
            return DayPlan(
                date: date,
                kind: .sport,
                title: memory.primarySport.map { "\($0.name) session" } ?? "Sport day",
                sport: memory.primarySport,
                generatedReason: "Sport slot from \(shapeDescription)"
            )
        case .rest:
            return DayPlan(
                date: date,
                kind: .rest,
                title: "Rest",
                generatedReason: "Rest slot from \(shapeDescription)"
            )
        case .event:
            return DayPlan(
                date: date,
                kind: .event,
                title: "Event",
                generatedReason: "Event slot from \(shapeDescription)"
            )
        }
    }

    private static func defaultTitle(for kind: DayKind) -> String {
        switch kind {
        case .lift:     return "Strength"
        case .mobility: return "Mobility"
        case .sport:    return "Sport"
        case .rest:     return "Rest"
        case .event:    return "Event"
        }
    }

    // MARK: - Best-practice rule passes
    //
    // Each pass mutates only NON-protected slots. Protected slots are: events
    // (sport_session, race) and dayOverrides — both express explicit user intent
    // and shouldn't be auto-rewritten.

    /// Pre-event taper for races. Hard race → preceding day = rest, day -2 = mobility.
    /// Moderate race → preceding day = rest only. Light race → no taper.
    private static func applyPreEventTaper(
        _ slots: inout [DayPlan?],
        dates: [Date],
        overrides: WeekOverrides,
        calendar: Calendar
    ) {
        for event in overrides.events where event.kind == .race {
            guard event.intensity != .light else { continue }
            guard let eventIdx = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: event.date) }) else {
                continue
            }

            // Day -1: rest (always for moderate + hard).
            demote(
                &slots, at: eventIdx - 1,
                to: .rest, title: "Rest",
                reason: "Tapering before \(eventTitle(event))"
            )

            // Day -2: mobility (hard only).
            if event.intensity == .hard {
                demote(
                    &slots, at: eventIdx - 2,
                    to: .mobility, title: "Mobility",
                    reason: "Easing into \(eventTitle(event))"
                )
            }
        }
    }

    /// Post-event recovery. Day after a hard race OR hard sport session = rest
    /// (no heavy lift). Moderate / light events don't trigger recovery.
    private static func applyPostEventRecovery(
        _ slots: inout [DayPlan?],
        dates: [Date],
        overrides: WeekOverrides,
        calendar: Calendar
    ) {
        for event in overrides.events where event.intensity == .hard {
            guard let eventIdx = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: event.date) }) else {
                continue
            }
            demote(
                &slots, at: eventIdx + 1,
                to: .rest, title: "Rest",
                reason: "Recovering from \(eventTitle(event))"
            )
        }
    }

    /// Pre-sport buffer. Day before a hard SPORT SESSION (not race — races
    /// already get the pre-event taper) → no heavy lift, demoted to mobility.
    /// Lets the user show up fresh for hard climbing/grappling/etc.
    private static func applyPreSportBuffer(
        _ slots: inout [DayPlan?],
        dates: [Date],
        overrides: WeekOverrides,
        calendar: Calendar
    ) {
        for event in overrides.events
        where event.kind == .sportSession && event.intensity == .hard {
            guard let eventIdx = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: event.date) }) else {
                continue
            }
            // Only demote if the preceding slot is a lift (.mobility/.rest already fine).
            let priorIdx = eventIdx - 1
            guard priorIdx >= 0,
                  let prior = slots[priorIdx],
                  !prior.protected,
                  prior.kind == .lift else { continue }
            demote(
                &slots, at: priorIdx,
                to: .mobility, title: "Mobility",
                reason: "Going light before \(eventTitle(event))"
            )
        }
    }

    /// Convert slot at `idx` to `kind` if (a) idx is in range, (b) the slot is
    /// not protected, and (c) the existing kind isn't already at-or-below the
    /// target severity. Skips no-op cases (e.g., asking to demote a rest to a
    /// rest).
    private static func demote(
        _ slots: inout [DayPlan?],
        at idx: Int,
        to kind: DayKind,
        title: String,
        reason: String
    ) {
        guard slots.indices.contains(idx),
              let current = slots[idx],
              !current.protected else { return }
        // Demotion ranking: lift > sport > mobility > rest. Don't promote.
        guard severity(current.kind) > severity(kind) else { return }
        slots[idx] = DayPlan(
            date: current.date,
            kind: kind,
            title: title,
            generatedReason: reason
        )
    }

    private static func severity(_ kind: DayKind) -> Int {
        switch kind {
        case .lift:     return 4
        case .sport:    return 3
        case .event:    return 3
        case .mobility: return 2
        case .rest:     return 1
        }
    }

    private static func eventTitle(_ event: WeekEvent) -> String {
        event.title.isEmpty ? "your event" : event.title
    }

    private static func weekdayShort(_ date: Date, calendar: Calendar = .current) -> String {
        Weekday.from(date: date, calendar: calendar).short
    }

    // MARK: - Lift budget adjustment

    /// Shape kinds → adjusted to hit `target` lifts.
    ///
    /// Demotes extras from the end (preserves the shape's early-week emphasis).
    ///
    /// When PROMOTING (current < target), picks the rest position with the
    /// MAX distance from any existing lift — so a shape like
    /// `[lift, rest, lift, rest, rest, rest, rest]` with target 4 becomes
    /// `[lift, rest, lift, rest, lift, rest, lift]` (M-W-F-Sun spacing) rather
    /// than `[lift, lift, lift, lift, rest, rest, rest]` (front-clustered).
    static func adjustForLiftBudget(_ queue: [DayKind], target: Int) -> [DayKind] {
        var result = queue
        let current = result.filter { $0 == .lift }.count

        if current > target {
            var excess = current - target
            for i in result.indices.reversed() where excess > 0 {
                if result[i] == .lift {
                    result[i] = .rest
                    excess -= 1
                }
            }
            return result
        }

        if current < target {
            var needed = target - current

            // Promote rests one at a time, picking the rest with max distance
            // to any existing lift each round so additions spread evenly.
            while needed > 0 {
                let liftPositions = result.indices.filter { result[$0] == .lift }
                let restPositions = result.indices.filter { result[$0] == .rest }
                guard let bestRest = restPositions.max(by: { lhs, rhs in
                    minDistance(from: lhs, to: liftPositions) < minDistance(from: rhs, to: liftPositions)
                }) else { break }
                result[bestRest] = .lift
                needed -= 1
            }

            // If we still need more, promote mobility slots (front-first).
            for i in result.indices where needed > 0 {
                if result[i] == .mobility {
                    result[i] = .lift
                    needed -= 1
                }
            }
            // We never demote sports — fixed sports are protected, and shape sports
            // express the user's intent through their primary sport.
        }
        return result
    }

    private static func minDistance(from idx: Int, to positions: [Int]) -> Int {
        if positions.isEmpty { return Int.max }
        return positions.map { abs($0 - idx) }.min() ?? Int.max
    }

    // MARK: - Routine selection

    /// Pick a routine matching kind + demographics + duration. Falls through
    /// (duration → preferred-difficulty buckets → equipment → constraint
    /// keywords) so a tightly-constrained profile still gets *something*
    /// instead of an empty plan.
    ///
    /// Demographic-aware steps (Phase 14):
    ///   - `preferredDifficulties` is ordered. We try the first bucket alone
    ///     before falling back to the next, so an intermediate user actually
    ///     gets intermediate routines instead of accidentally landing on
    ///     beginner because both were "allowed".
    ///   - `allowedEnvironments` filters by `routines.environment`. Skipped
    ///     when empty (full-gym users see everything).
    ///   - `excludedNameKeywords` drops routines whose name brushes against
    ///     a user-declared injury / constraint.
    static func pickRoutine(
        routines: [Routine],
        kind: DayKind,
        memory: TrainingMemory,
        slotOffset: Int
    ) -> Routine? {
        let profile = DemographicProfile.from(memory)
        return pickRoutine(routines: routines, kind: kind,
                           memory: memory, profile: profile,
                           slotOffset: slotOffset)
    }

    /// Profile-injected variant — Planner.generate computes the profile once
    /// per regeneration and threads it through; tests can also pass a custom
    /// profile to exercise the matrix without rebuilding memory.
    static func pickRoutine(
        routines: [Routine],
        kind: DayKind,
        memory: TrainingMemory,
        profile: DemographicProfile,
        slotOffset: Int
    ) -> Routine? {
        guard let goals = goalsFor(kind), !goals.isEmpty else { return nil }

        // Equipment + constraints — applied to every pass below.
        let envAndConstraintAllowed: (Routine) -> Bool = { r in
            environmentAllowed(r, allowed: profile.allowedEnvironments)
            && !constraintConflict(r, keywords: profile.excludedNameKeywords)
        }

        // Walk preferredDifficulties in order. For each bucket: try exact
        // (goal + bucket + duration) first, then relax duration.
        for bucket in profile.preferredDifficulties {
            let bucketSet: Set<String> = [bucket]

            let exact = routines.filter { r in
                goalMatches(r, goals: goals)
                    && difficultyMatches(r, allowed: bucketSet)
                    && durationOK(r.durationMinutes, target: memory.sessionMinutes)
                    && envAndConstraintAllowed(r)
            }
            if let pick = deterministicPick(from: exact, offset: slotOffset, hash: memory.planInputsHash) {
                return pick
            }

            let durationRelaxed = routines.filter { r in
                goalMatches(r, goals: goals)
                    && difficultyMatches(r, allowed: bucketSet)
                    && envAndConstraintAllowed(r)
            }
            if let pick = deterministicPick(from: durationRelaxed, offset: slotOffset, hash: memory.planInputsHash) {
                return pick
            }
        }

        // Difficulty completely relaxed but still respect equipment + constraints.
        let envOnly = routines.filter { r in
            goalMatches(r, goals: goals) && envAndConstraintAllowed(r)
        }
        if let pick = deterministicPick(from: envOnly, offset: slotOffset, hash: memory.planInputsHash) {
            return pick
        }

        // Last resort within env filter — drop constraint exclusions (better
        // a flagged routine than no routine; user can swap via long-press).
        let envOnlyNoConstraints = routines.filter { r in
            goalMatches(r, goals: goals)
                && environmentAllowed(r, allowed: profile.allowedEnvironments)
        }
        if let pick = deterministicPick(from: envOnlyNoConstraints, offset: slotOffset, hash: memory.planInputsHash) {
            return pick
        }

        // If we got here with an active env filter, return nil. The user
        // explicitly told us their equipment — recommending a routine they
        // can't physically do (e.g. a gym routine for a bodyweight user) is
        // worse than a placeholder they can override. makeSlot handles the
        // nil case with a "no matching routine" reason string.
        if !profile.allowedEnvironments.isEmpty {
            return nil
        }

        // No env restriction (full gym) — fall back to goal-only so a catalog
        // missing env tags doesn't starve the user.
        let goalOnly = routines.filter { r in goalMatches(r, goals: goals) }
        return deterministicPick(from: goalOnly, offset: slotOffset, hash: memory.planInputsHash)
    }

    // MARK: - Filter helpers

    private static func goalsFor(_ kind: DayKind) -> Set<String>? {
        switch kind {
        case .lift:     return ["strength", "direct_strength", "power", "accessory", "conditioning"]
        case .mobility: return ["mobility", "warm_up", "recovery", "prehab"]
        default:        return nil
        }
    }

    private static func goalMatches(_ r: Routine, goals: Set<String>) -> Bool {
        guard let g = r.goal else { return false }
        return goals.contains(g)
    }

    private static func difficultyMatches(_ r: Routine, allowed: Set<String>) -> Bool {
        guard let d = r.difficulty else { return true }   // tolerate unset
        return allowed.contains(d)
    }

    private static func durationOK(_ duration: Int?, target: Int) -> Bool {
        guard let d = duration else { return true }       // unknown ⇒ acceptable
        return abs(d - target) <= 20
    }

    private static func environmentAllowed(_ r: Routine, allowed: Set<String>) -> Bool {
        guard !allowed.isEmpty else { return true }       // empty = no filter
        guard let env = r.environment, !env.isEmpty else { return true }
        return allowed.contains(env)
    }

    private static func constraintConflict(_ r: Routine, keywords: [String]) -> Bool {
        guard !keywords.isEmpty else { return false }
        let lowerName = r.name.lowercased()
        return keywords.contains { lowerName.contains($0) }
    }

    /// Stable offset-pick from a candidate array. Uses djb2 fold of (hash+offset)
    /// → modulo array size, so the same (memory, slot) always picks the same id.
    private static func deterministicPick<T>(from arr: [T], offset: Int, hash: String) -> T? {
        guard !arr.isEmpty else { return nil }
        var folded: UInt64 = 5381
        for byte in hash.utf8 { folded = (folded &* 33) &+ UInt64(byte) }
        folded = (folded &* 33) &+ UInt64(offset)
        return arr[Int(folded % UInt64(arr.count))]
    }
}
