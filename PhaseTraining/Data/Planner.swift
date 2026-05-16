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
        var qi = 0
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
            let kind = adjustedQueue[qi]
            qi += 1
            slots[i] = makeSlot(
                date: date, kind: kind, memory: memory,
                routines: routines, shapeDescription: shape.description, slotOffset: i
            )
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
            let r = routineId.flatMap { id in routines.first(where: { $0.id == id }) }
            return DayPlan(date: date, kind: .mobility,
                           title: r?.name ?? "Mobility",
                           routineId: r?.id,
                           protected: true,
                           generatedReason: "You set this day to mobility")

        case .lift(let routineId):
            let r = routineId.flatMap { id in routines.first(where: { $0.id == id }) }
                ?? pickRoutine(routines: routines, kind: .lift, memory: memory, slotOffset: 0)
            return DayPlan(date: date, kind: .lift,
                           title: r?.name ?? "Strength",
                           routineId: r?.id,
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
        routines: [Routine],
        shapeDescription: String,
        slotOffset: Int
    ) -> DayPlan {
        switch kind {
        case .lift, .mobility:
            let r = pickRoutine(routines: routines, kind: kind, memory: memory, slotOffset: slotOffset)
            return DayPlan(
                date: date,
                kind: kind,
                title: r?.name ?? defaultTitle(for: kind),
                routineId: r?.id,
                generatedReason: r != nil
                    ? "Picked from \(shapeDescription)"
                    : "No matching \(kind.label.lowercased()) routine — placeholder"
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

    /// Pick a routine matching kind + experience + duration. Falls through
    /// duration → difficulty → goal in order if no exact match exists.
    static func pickRoutine(
        routines: [Routine],
        kind: DayKind,
        memory: TrainingMemory,
        slotOffset: Int
    ) -> Routine? {
        guard let goals = goalsFor(kind), !goals.isEmpty else { return nil }
        let allowedDifficulties = difficultiesFor(memory.experience)

        // Pass 1: exact match (goal + difficulty + duration).
        let exact = routines.filter { r in
            goalMatches(r, goals: goals)
                && difficultyMatches(r, allowed: allowedDifficulties)
                && durationOK(r.durationMinutes, target: memory.sessionMinutes)
        }
        if let pick = deterministicPick(from: exact, offset: slotOffset, hash: memory.planInputsHash) {
            return pick
        }

        // Pass 2: relax duration.
        let relaxed = routines.filter { r in
            goalMatches(r, goals: goals)
                && difficultyMatches(r, allowed: allowedDifficulties)
        }
        if let pick = deterministicPick(from: relaxed, offset: slotOffset, hash: memory.planInputsHash) {
            return pick
        }

        // Pass 3: relax difficulty.
        let veryRelaxed = routines.filter { r in goalMatches(r, goals: goals) }
        return deterministicPick(from: veryRelaxed, offset: slotOffset, hash: memory.planInputsHash)
    }

    // MARK: - Filter helpers

    private static func goalsFor(_ kind: DayKind) -> Set<String>? {
        switch kind {
        case .lift:     return ["strength", "direct_strength", "power", "accessory", "conditioning"]
        case .mobility: return ["mobility", "warm_up", "recovery", "prehab"]
        default:        return nil
        }
    }

    private static func difficultiesFor(_ exp: ExperienceLevel) -> Set<String> {
        switch exp {
        case .beginner:     return ["beginner"]
        case .intermediate: return ["beginner", "intermediate"]
        case .advanced:     return ["beginner", "intermediate", "advanced", "elite"]
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
