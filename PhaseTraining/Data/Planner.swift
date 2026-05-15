// Planner.swift — pure rules-based week generator.
//
// Inputs: TrainingMemory + the routine catalog (passed in, not loaded here so
// this stays unit-testable without coach.db). Outputs a WeekPlan whose
// inputsHash matches `memory.planInputsHash` (set on WeekPlan struct so PlanStore
// can detect drift).
//
// Algorithm (deterministic):
//   1. Resolve a WeeklyShape from (primarySport, season, focus).
//   2. Place fixed sport days (memory.fixedSportDays) — protected.
//   3. Force rest on weekdays not in memory.availableDays.
//   4. Fill remaining empty slots from the shape queue (skipping shape sport
//      slots already satisfied by fixed sports).
//   5. For each .lift / .mobility slot, pick a coach.db routine whose goal
//      matches the kind, difficulty ≤ user experience, duration ≈ target.
//      Selection within the candidate set is deterministic via inputsHash +
//      slot offset, so the same memory always produces the same plan.
//
// Phase 13 (LLM coach) will mutate plans via PlanEdit; this generator is
// untouched by that — it only re-runs on weekly check-in or onboarding.

import Foundation

enum Planner {

    static func generate(
        memory: TrainingMemory,
        routines: [Routine],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> WeekPlan {
        let start = calendar.startOfDay(for: today)
        let dates: [Date] = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let shape = WeeklyShape.resolve(
            primarySport: memory.primarySport,
            season: memory.season,
            focus: memory.primaryFocus
        )

        var slots: [DayPlan?] = Array(repeating: nil, count: 7)

        // Step 1 — fixed sport days (protected).
        for (i, date) in dates.enumerated() {
            let weekday = Weekday.from(date: date, calendar: calendar)
            if let sport = memory.fixedSportDays[weekday] {
                slots[i] = DayPlan(
                    date: date,
                    kind: .sport,
                    title: "\(sport.name) session",
                    sport: sport,
                    protected: true,
                    generatedReason: "Fixed: you said \(weekday.short) is for \(sport.name)"
                )
            }
        }

        // Step 2 — force rest on unavailable weekdays. Skip if user picked no days
        // (empty availableDays means "don't constrain"; otherwise we'd rest the
        // entire week).
        if !memory.availableDays.isEmpty {
            for (i, date) in dates.enumerated() where slots[i] == nil {
                let weekday = Weekday.from(date: date, calendar: calendar)
                if !memory.availableDays.contains(weekday) {
                    slots[i] = DayPlan(
                        date: date,
                        kind: .rest,
                        title: "Rest",
                        generatedReason: "\(weekday.short) isn't in your training days"
                    )
                }
            }
        }

        // Step 3 — build remaining shape queue, accounting for shape-allocated
        // sport slots already satisfied by fixed sports.
        let placedSportCount = slots.compactMap { $0 }.filter { $0.kind == .sport }.count
        var queue: [DayKind] = []
        var sportsToSkip = placedSportCount
        for kind in shape.kinds {
            if kind == .sport && sportsToSkip > 0 {
                sportsToSkip -= 1
                continue
            }
            queue.append(kind)
        }

        // Step 4 — walk queue, fill empty slots.
        var qi = 0
        for (i, date) in dates.enumerated() where slots[i] == nil {
            guard !queue.isEmpty else {
                slots[i] = DayPlan(
                    date: date,
                    kind: .rest,
                    title: "Rest",
                    generatedReason: "No more shape slots"
                )
                continue
            }
            let kind = queue[qi % queue.count]
            qi += 1
            slots[i] = makeSlot(
                date: date, kind: kind, memory: memory,
                routines: routines, shapeDescription: shape.description, slotOffset: i
            )
        }

        let days = slots.compactMap { $0 }
        return WeekPlan(
            days: days,
            generatedAt: Date(),
            inputsHash: memory.planInputsHash
        )
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
