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
        routines: [BundledRoutineRow],
        previousFeedback: [FeedbackEntry] = [],
        // Build 99: hybrid-athlete signal. When the user's already loading
        // the body with hard sport (climbing, skiing) and we're about to
        // schedule a full lifting week on top, trim one lift day. Defaulted
        // so existing callers (tests, previews) don't have to thread it.
        recentSportLogs: [SportLogEntry] = [],
        recentlyPicked: Set<Int> = [],
        today: Date = Date(),
        calendar: Calendar = .current,
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto
    ) -> WeekPlan {
        let biased = applyRecentSignalBias(
            memory: memory,
            feedback: previousFeedback,
            sportLogs: recentSportLogs,
            calendar: calendar,
            now: today
        )
        // Phase 2 readiness floor — when the user is clearly detrained
        // AND we have real data to say so, cap lift days at 3/wk
        // regardless of self-reported preference. Silent: the user's
        // declared `liftDaysPerWeek` is preserved in their profile; only
        // THIS planning pass uses the floor. Independent of (and stacks
        // with) the existing feedback / sport-log trim.
        let readinessCapped = applyReadinessLiftDayFloor(memory: biased, context: context)
        // Stacks with the readiness floor: whichever is stricter wins, since
        // each only ever lowers the count.
        let phaseCapped = applyPhaseSessionCap(memory: readinessCapped)
        return generateUnbiased(
            memory: phaseCapped,
            overrides: overrides,
            routines: routines,
            recentlyPicked: recentlyPicked,
            today: today,
            calendar: calendar,
            context: context,
            strategy: strategy
        )
    }

    /// Phase 2: when readinessScore < 0.3 AND we have real data, cap
    /// liftDaysPerWeek at 3 for this planning pass. Pure / testable —
    /// no side effects, no persistence. The brief explicitly anchors
    /// this as a SILENT rule; the user's self-reported value stays
    /// untouched in TrainingMemory.
    static func applyReadinessLiftDayFloor(
        memory: TrainingMemory,
        context: GeneratorContext
    ) -> TrainingMemory {
        guard context.hasReadinessData,
              context.readinessScore < 0.3,
              memory.liftDaysPerWeek > 3 else {
            return memory
        }
        var out = memory
        out.liftDaysPerWeek = 3
        return out
    }

    /// T2-7: enforce the phase rule's own `sessionsPerWeek` cap on the LIVE
    /// path.
    ///
    /// `PhaseRule.sessionsPerWeek` was only ever applied inside
    /// `SportSeasonGenerator.generateWeek`, which no app code calls — verified
    /// by grep: every caller is in SeasonFidelityTest. The live path is
    /// Planner → one `generateSession` per lift slot, sized by
    /// `memory.liftDaysPerWeek` + WeeklyShape. So the in-season ski rule's
    /// `2...2` cap was inert: a skier who set 5 lift days got 5 in-season
    /// sessions, defeating the phase's whole minimal-fatigue objective.
    ///
    /// Same shape as `applyReadinessLiftDayFloor` above — a silent clamp on a
    /// COPY; the user's self-reported value stays untouched in TrainingMemory.
    static func applyPhaseSessionCap(memory: TrainingMemory) -> TrainingMemory {
        guard let slug = memory.primarySport?.slug,
              SportSeasonGenerator.supports(slug) else { return memory }
        let rule = PhaseRule.resolve(
            sportSlug: slug,
            variant: SportSeasonGenerator.defaultVariant(forSport: slug),
            season: memory.seasonForPlanner)
        let cap = rule.sessionsPerWeek.upperBound
        guard memory.liftDaysPerWeek > cap else { return memory }
        var out = memory
        out.liftDaysPerWeek = cap
        return out
    }

    /// Inspect the most recent 7-day feedback + sport-log windows and nudge
    /// the memory before planning. Conservative — at most ±1 lift day per
    /// regen so repeated "too hard" weeks (or a heavy sport week) don't
    /// collapse the schedule to zero in one shot.
    ///
    /// Signals combine into a SINGLE nudge: trim wins over expand (we
    /// always err toward recovery), and the two trim triggers (feedback
    /// "too_hard" ≥2, OR hard sport days ≥3) don't double-stack.
    static func applyRecentSignalBias(
        memory: TrainingMemory,
        feedback: [FeedbackEntry],
        sportLogs: [SportLogEntry] = [],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> TrainingMemory {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? Date.distantPast

        let recentFb = feedback.filter { $0.date >= cutoff }
        let tooHard = recentFb.filter { $0.difficulty == "too_hard" }.count
        let tooEasy = recentFb.filter { $0.difficulty == "too_easy" }.count

        // Distinct calendar days with at least one HARD sport log. Mirrors
        // GeneratorContext.recentHardSportDays — we recompute here rather
        // than depend on context so this function stays pure / testable.
        let hardSportDays = Set(
            sportLogs
                .filter { $0.intensity == .hard && $0.date >= cutoff }
                .map { calendar.startOfDay(for: $0.date) }
        ).count

        let feedbackTrim = tooHard >= 2 && tooHard > tooEasy
        let sportTrim    = hardSportDays >= 3
        let feedbackExpand = tooEasy >= 2 && tooEasy > tooHard

        var adjusted = memory
        if feedbackTrim || sportTrim {
            adjusted.liftDaysPerWeek = max(0, adjusted.liftDaysPerWeek - 1)
        } else if feedbackExpand {
            // Planner's per-week loop already caps against actual empty slots.
            adjusted.liftDaysPerWeek = min(6, adjusted.liftDaysPerWeek + 1)
        }
        return adjusted
    }

    /// PR 5 (weekly-coach roadmap) — merge a `WeekTone` into the
    /// generator strategy. Composes orthogonally with whatever the LLM
    /// supplied: tone fills in defaults but never overwrites an
    /// explicitly-set strategy field. Returns the base strategy
    /// unchanged when tone is nil or `.typical`.
    static func applyWeekTone(
        base: GeneratorStrategy,
        tone: WeekTone?,
        sessionMinutes: Int
    ) -> GeneratorStrategy {
        guard let tone, tone != .typical else { return base }
        var out = base
        // intensityBias: only override when the caller didn't already pick
        // a non-normal bias. An explicit LLM "push" beats a tone-derived
        // "deload" — the LLM saw the user's specific request.
        if out.intensityBias == .normal {
            out.intensityBias = tone.asIntensityBias
        }
        // durationMinutes: only `.busy` actively compresses sessions, and
        // only when the caller didn't already set a duration. Clamp to
        // the same hard bound the rest of the pipeline respects.
        if out.durationMinutes == nil && tone.durationMultiplier != 1.0 {
            let compressed = Int(Double(sessionMinutes) * tone.durationMultiplier)
            let hard = TrainingConstraints.sessionMinutesHardRange
            out.durationMinutes = max(hard.lowerBound, min(hard.upperBound, compressed))
        }
        return out
    }

    /// Back-compat shim. Kept so any external caller / future test that
    /// asks for feedback bias in isolation still works. New code should
    /// call `applyRecentSignalBias` directly.
    static func applyFeedbackBias(
        memory: TrainingMemory,
        feedback: [FeedbackEntry],
        calendar: Calendar = .current
    ) -> TrainingMemory {
        applyRecentSignalBias(
            memory: memory,
            feedback: feedback,
            sportLogs: [],
            calendar: calendar
        )
    }

    private static func generateUnbiased(
        memory: TrainingMemory,
        overrides: WeekOverrides?,
        routines: [BundledRoutineRow],
        recentlyPicked: Set<Int>,
        today: Date,
        calendar: Calendar,
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto
    ) -> WeekPlan {
        // PR 5 (weekly-coach roadmap) — apply week-level intent dial.
        // `WeekTone` biases intensity and (for `.busy`) compresses session
        // duration. Composes with any incoming LLM strategy: LLM-set
        // fields win, tone fills in where the strategy is auto.
        let strategy = applyWeekTone(
            base: strategy,
            tone: overrides?.weekTone,
            sessionMinutes: memory.sessionMinutes
        )

        // Always Monday-of-this-week → Sunday. The Week tab shows the
        // prescription for the current calendar week, not a rolling 7-day
        // window starting today. Past days (e.g. Mon/Tue when today is Wed)
        // remain visible so the user can see what was prescribed; history of
        // what they actually did lives in HistoryScreen.
        var mondayCal = calendar
        mondayCal.firstWeekday = 2
        let start = today.startOfTrainingWeek(calendar: mondayCal)
        let dates: [Date] = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let shape = WeeklyShape.resolve(
            primarySport: memory.primarySport,
            season: memory.seasonForPlanner
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
            // Ordinal of each .lift override within the week, so pinned days get
            // DISTINCT sessions. makeOverrideSlot used to hardcode
            // liftIndex: 0, totalLifts: 1, and the season engine keys the whole
            // session off sessionIndex (= liftIndex) — so every user-pinned lift
            // day, and every day restored by PlanStore.adoptLastWeekShape (which
            // writes .lift overrides for all prior lift days), produced the
            // byte-identical workout. Pin Mon/Wed/Fri and you got the same three
            // exercises three times.
            let liftOverrideDates: [Date] = dates.enumerated().compactMap { i, date in
                guard slots[i] == nil,
                      let ov = overrides.override(on: date, calendar: calendar),
                      case .lift = ov else { return nil }
                return date
            }
            for (i, date) in dates.enumerated() where slots[i] == nil {
                guard let ov = overrides.override(on: date, calendar: calendar) else { continue }
                let liftIndex = liftOverrideDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) ?? 0
                slots[i] = makeOverrideSlot(date: date, override: ov, memory: memory, routines: routines, recentlyPicked: recentlyPicked, context: context, strategy: strategy,
                                            liftIndex: liftIndex, totalLifts: max(1, liftOverrideDates.count))
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
            // Sport slots are already placed; a lift slot defers to the sport
            // (lightens) when a sport day sits immediately before or after it.
            let adjacentSport =
                (entry.idx > 0 && slots[entry.idx - 1]?.kind == .sport) ||
                (entry.idx < slots.count - 1 && slots[entry.idx + 1]?.kind == .sport)
            slots[entry.idx] = makeSlot(
                date: entry.date,
                kind: entry.kind,
                memory: memory,
                profile: profile,
                routines: routines,
                recentlyPicked: recentlyPicked,
                shapeDescription: shape.description,
                slotOffset: entry.idx,
                liftIndex: entry.kind == .lift ? liftCursor : 0,
                totalLifts: totalLifts,
                adjacentSportDay: adjacentSport,
                context: context,
                strategy: strategy
            )
            if entry.kind == .lift { liftCursor += 1 }
        }

        // Step 6.5 — secondary-sport in-season promotion. For each non-primary
        // sport flagged .inSeason / .eventPrep in seasonsBySport, demote one
        // rest slot to a sport slot for that sport — UNLESS the user already
        // booked a WeekEvent for it. Without this, picking "skiing pre-season"
        // alongside primary climbing was dead data: only the primary's season
        // ever moved the shape. Capped to keep multi-sport users from getting
        // all-sport weeks.
        applySecondarySportPromotion(&slots, memory: memory, overrides: overrides, calendar: calendar)

        // Step 6.6 — primary/support de-confliction (PLAN-primary-support.md).
        // When the user has declared a SUPPORT sport's weekly pattern, stamp
        // those days and reflow the primary lift week AROUND them (buffer +
        // weekly-load lightening). Supersedes the crude promotion for that
        // sport (see the skip in applySecondarySportPromotion). Runs before the
        // buffer passes so they see the stamped support days.
        applySupportPattern(&slots, memory: memory, calendar: calendar)

        // Step 7 — best-practice rules. Each pass mutates only NON-protected slots.
        if let overrides {
            applyPreEventTaper(&slots, dates: dates, overrides: overrides, calendar: calendar)
            applyPostEventRecovery(&slots, dates: dates, overrides: overrides, calendar: calendar)
            applyPreSportBuffer(&slots, dates: dates, overrides: overrides, calendar: calendar)
        }

        // Step 7.5 — peak-date taper. If the user is in .eventPrep and their
        // peakDate lands in this week, apply the same taper as a hard race
        // event. Without this, .eventPrep was just a label that fell through to
        // .maintenance with no actual peak/taper behavior.
        applyPeakDateTaper(&slots, dates: dates, memory: memory, calendar: calendar)

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
        routines: [BundledRoutineRow],
        recentlyPicked: Set<Int>,
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto,
        /// Position of this day among the week's pinned lift days, and how many
        /// there are. Threaded so each pinned day generates a different session.
        liftIndex: Int = 0,
        totalLifts: Int = 1
    ) -> DayPlan {
        switch override {
        case .rest:
            return DayPlan(date: date, kind: .rest, title: "Rest",
                           protected: true,
                           generatedReason: "You set this day to rest")

        case .lift(let routineId, let focus):
            if let id = routineId, let r = routines.first(where: { $0.id == id }) {
                // User-picked routine wins over focus — a routine is a
                // specific recipe; focus is a category. If the user wanted
                // both they'd pick a routine whose focus matches.
                return DayPlan(date: date, kind: .lift,
                               title: r.name,
                               routineId: r.id,
                               protected: true,
                               generatedReason: "You picked this workout for this day")
            }
            // PR 5: when the override carries a focus, fold it into the
            // strategy so the generator picks a push/pull/legs/etc. shape
            // matching the user's intent. focus overrides anything the
            // tone-merged strategy already had — the focus is a more
            // specific directive than the week-level tone.
            var liftStrategy = strategy
            if let focus { liftStrategy.focus = focus.asWorkoutFocus }
            let profile = DemographicProfile.from(memory)
            let workout = WorkoutGenerator.generateLift(
                liftIndex: liftIndex,
                totalLifts: totalLifts,
                memory: memory,
                profile: profile,
                hashSeed: memory.planInputsHash + "-lift-override-\(liftIndex)",
                recentlyPicked: recentlyPicked,
                context: context,
                strategy: liftStrategy
            )
            let reason = focus.map { "You set this day as \($0.label.lowercased())" }
                ?? "You set this day to lift"
            return DayPlan(date: date, kind: .lift,
                           title: workout.title,
                           generatedWorkout: workout,
                           protected: true,
                           generatedReason: reason)

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
        case .outOfTown:
            // PR 5 — travel day. Generate a bodyweight `.lift` template
            // the user can run anywhere. The exercise picks are
            // hand-curated against the bundled catalog (Push-Up, Bird
            // Dog, Glute Bridge, Plank, Mountain Climber) rather than
            // routed through WorkoutGenerator because the generator
            // doesn't currently filter by equipment availability.
            // Replacing this with a generator-driven bodyweight path is
            // a planned follow-up.
            let title = event.title.isEmpty ? "Travel — bodyweight flow" : event.title
            return DayPlan(
                date: date,
                kind: .lift,
                title: title,
                generatedWorkout: bodyweightTravelWorkout(title: title, date: date),
                protected: true,
                generatedReason: "You marked this day as out of town — bodyweight flow you can do anywhere"
            )
        }
    }

    /// Hand-built bodyweight template for `.outOfTown` event days. Five
    /// exercises drawn from the bundled catalog by stable id, so the
    /// resulting DayPlan renders correctly in LogScreen + carries real
    /// exerciseId values for the substitution / detail flows. Sets/reps
    /// are conservative defaults — the user can modify in-workout.
    private static func bodyweightTravelWorkout(title: String, date: Date) -> GeneratedWorkout {
        // (catalog id, name, pattern hint) — IDs stable in coach.db
        let template: [(id: Int, name: String, pattern: String)] = [
            (13,   "Push-Up",          "horizontal-push"),
            (1020, "Glute Bridge",     "hip-hinge"),
            (110,  "Bird Dog",         "anti-rotation"),
            (1058, "Plank",            "anti-extension"),
            (1053, "Mountain Climber", "locomotion"),
        ]
        let dateKey = Int(date.timeIntervalSince1970)
        let exercises = template.enumerated().map { (idx, ex) -> GeneratedExercise in
            GeneratedExercise(
                id: "travel-\(dateKey)-\(idx)-\(ex.id)",
                exerciseId: ex.id,
                name: ex.name,
                pattern: ex.pattern,
                isCompound: false,
                sets: 3,
                reps: ex.id == 1058 ? "30s hold" : "10-15",
                restSeconds: 60,
                notes: nil,
                rpe: "7-8",
                tempo: nil,
                source: .recipe
            )
        }
        return GeneratedWorkout(
            title: title,
            summary: "5 movements · ~20 min · bodyweight",
            exercises: exercises,
            estimatedMinutes: 20,
            provenance: "Travel-friendly bodyweight flow"
        )
    }

    // MARK: - Slot construction

    private static func makeSlot(
        date: Date,
        kind: DayKind,
        memory: TrainingMemory,
        profile: DemographicProfile,
        routines: [BundledRoutineRow],
        recentlyPicked: Set<Int>,
        shapeDescription: String,
        slotOffset: Int,
        liftIndex: Int,
        totalLifts: Int,
        adjacentSportDay: Bool = false,
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto
    ) -> DayPlan {
        switch kind {
        case .lift:
            // generateLift dispatches to the season engine for ski/climb;
            // adjacentSportDay lets in-season days defer to the sport.
            let workout = WorkoutGenerator.generateLift(
                liftIndex: liftIndex,
                totalLifts: totalLifts,
                memory: memory,
                profile: profile,
                hashSeed: memory.planInputsHash,
                recentlyPicked: recentlyPicked,
                context: context,
                strategy: strategy,
                adjacentSportDay: adjacentSportDay
            )
            return DayPlan(
                date: date,
                kind: .lift,
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
        case .lift:  return "Strength"
        case .sport: return "Sport"
        case .rest:  return "Rest"
        case .event: return "Event"
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

            // Day -2: extra rest (hard only). Pre-cleanup this was a mobility
            // slot; with the mobility catalog gone, easing in just means rest.
            if event.intensity == .hard {
                demote(
                    &slots, at: eventIdx - 2,
                    to: .rest, title: "Rest",
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
    /// already get the pre-event taper) → no heavy lift, demoted to rest.
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
            // Only demote if the preceding slot is a lift (.rest already fine).
            let priorIdx = eventIdx - 1
            guard priorIdx >= 0,
                  let prior = slots[priorIdx],
                  !prior.protected,
                  prior.kind == .lift else { continue }
            demote(
                &slots, at: priorIdx,
                to: .rest, title: "Rest",
                reason: "Going light before \(eventTitle(event))"
            )
        }
    }

    /// Peak-date taper for .eventPrep seasons. Build 78: .eventPrep used to
    /// fall through to .maintenance with no tangible behavior. When the user's
    /// peakDate lands inside this week AND their primary season is .eventPrep:
    ///   day-1 → rest, day-2 → mobility, peak day itself → light event slot.
    /// Matches the hard-race taper from applyPreEventTaper. Skipped if the user
    /// already placed a race event for that date (no double-taper).
    static func applyPeakDateTaper(
        _ slots: inout [DayPlan?],
        dates: [Date],
        memory: TrainingMemory,
        calendar: Calendar
    ) {
        guard memory.seasonForPlanner == .eventPrep,
              let peak = memory.peakDate else { return }
        guard let peakIdx = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: peak) }) else {
            return
        }
        // If the user already protected this date with an event, the
        // applyPreEventTaper pass owned the taper — don't double-write.
        if let current = slots[peakIdx], current.protected { return }

        // Convert the peak slot itself into a protected .event placeholder so
        // the user lands on a clear "this is your peak" entry.
        slots[peakIdx] = DayPlan(
            date: dates[peakIdx],
            kind: .event,
            title: "Peak day",
            protected: true,
            generatedReason: "Your event-prep peak date"
        )
        demote(&slots, at: peakIdx - 1, to: .rest, title: "Rest",
               reason: "Tapering before peak day")
        demote(&slots, at: peakIdx - 2, to: .rest, title: "Rest",
               reason: "Easing into peak day")
    }

    /// Secondary-sport promotion. Build 78: per-sport seasons used to be a
    /// no-op for non-primary sports — the picker stored data the planner
    /// ignored. This pass takes one rest slot per secondary sport flagged
    /// .inSeason or .eventPrep and converts it into a .sport day for that
    /// sport. Skipped when the user already placed a WeekEvent for that sport
    /// this week (no double-booking). Capped at 2 promotions per week so
    /// six-sport profiles don't blow up into all-sport weeks.
    static func applySecondarySportPromotion(
        _ slots: inout [DayPlan?],
        memory: TrainingMemory,
        overrides: WeekOverrides?,
        calendar: Calendar
    ) {
        let primarySlug = memory.primarySport?.slug
        // The support sport (if declared) is placed by applySupportPattern with
        // explicit weekdays + magnitude — skip it here so it isn't double-placed.
        let supportSlug = memory.supportPattern?.sportSlug
        // Deterministic order: sport slug. seasonsBySport is a dict.
        // Only sports the user still has selected. seasonsBySport was iterated
        // with no membership check, so a sport deselected in SportsEditorSheet
        // while marked .inSeason kept getting a placeholder day booked into the
        // week forever, with no UI able to reach the orphaned entry
        // (SeasonsEditorSheet only iterates memory.sports). The editor now
        // clears it on deselect; this makes stale data from older installs
        // inert too.
        let selected = Set(memory.sports.map(\.slug))
        let candidates = memory.seasonsBySport
            .filter { selected.contains($0.key.slug) }
            .filter { $0.key.slug != primarySlug && $0.key.slug != supportSlug }
            .filter { $0.value == .inSeason || $0.value == .eventPrep }
            .sorted { $0.key.slug < $1.key.slug }
            .prefix(2)

        // Sports the user already booked an explicit event for this week —
        // don't double-book. Compares on slug because Sport equality is slug.
        let alreadyBooked: Set<String> = Set(
            (overrides?.events ?? [])
                .compactMap { $0.sport?.slug }
        )

        for (sport, _) in candidates {
            if alreadyBooked.contains(sport.slug) { continue }
            // Find the first unprotected rest slot we can demote.
            guard let idx = slots.indices.first(where: { i in
                if let s = slots[i] {
                    return !s.protected && s.kind == .rest
                }
                return false
            }), let current = slots[idx] else { continue }
            slots[idx] = DayPlan(
                date: current.date,
                kind: .sport,
                title: "\(sport.name) session",
                sport: sport,
                generatedReason: "\(sport.name) is in-season — added a placeholder day"
            )
        }
    }

    /// Primary/support de-confliction (PLAN-primary-support.md). Two passes,
    /// both respecting protected / event / override slots:
    ///   1. Stamp each declared support day onto its weekday's slot when that
    ///      slot is an unprotected REST (the common case — the user rests from
    ///      lifting on their climb days). Lift/protected slots are left intact.
    ///   2. Reflow the primary lift week via SupportScheduler.deconflictInPlace
    ///      (fixed weekdays, lighten-only): drop volume from lift days inside a
    ///      support recovery buffer or over the combined weekly budget, and
    ///      record a human-readable reason on the day.
    static func applySupportPattern(
        _ slots: inout [DayPlan?],
        memory: TrainingMemory,
        calendar: Calendar
    ) {
        guard let pattern = memory.supportPattern, !pattern.isEmpty else { return }
        // The interference table is authored for a ski/board primary paired with
        // a support sport, and ProfileScreen only offered the editor for that
        // pairing — but this ran on ANY primary. Switch primary from ski to
        // Running and the planner kept stamping support days onto rest slots
        // and lightening lift days via the deconflict pass. ProfileScreen now
        // also keeps the row reachable whenever a pattern exists, so the user
        // can clear it; this stops it applying where it was never authored.
        guard PhaseRule.skiSlugs.contains(memory.primarySport?.slug ?? "") else { return }
        let primaryVariant = SportSeasonGenerator.defaultVariant(forSport: memory.primarySport?.slug)
        let supportSport = Sport.catalog.first { $0.slug == pattern.sportSlug }
        let verb = pattern.sportSlug == "climbing" ? "climb" : "train \(supportSport?.name ?? pattern.sportSlug)"

        // 1. Stamp support days onto matching unprotected rest slots.
        for sd in pattern.days {
            guard let idx = slots.indices.first(where: { i in
                guard let s = slots[i] else { return false }
                return Weekday.from(date: s.date, calendar: calendar) == sd.weekday
            }), let cur = slots[idx] else { continue }
            // Couldn't place it — the slot is protected, or the planner already
            // put a lift there. The day used to just VANISH from the week: the
            // user declared "I climb Tuesday" and Tuesday showed only a lift,
            // with at most a lightening note and no indication their declared
            // day had been dropped. Say so on the day itself.
            guard !cur.protected, cur.kind == .rest else {
                if !cur.protected, cur.kind == .lift {
                    slots[idx] = DayPlan(
                        date: cur.date, kind: cur.kind, title: cur.title,
                        routineId: cur.routineId, generatedWorkout: cur.generatedWorkout,
                        sport: cur.sport, protected: cur.protected,
                        generatedReason: (cur.generatedReason.map { $0 + " · " } ?? "")
                            + "Couldn't fit your \(sd.weekday.short) \(supportSport?.name ?? pattern.sportSlug) day here"
                    )
                }
                continue
            }
            slots[idx] = DayPlan(
                date: cur.date,
                kind: .sport,
                // Bare sport name — the Week tab's SupportBadge carries the
                // magnitude, and the reason line keeps it for other surfaces.
                title: supportSport?.name ?? "Support day",
                sport: supportSport,
                generatedReason: "You \(verb) on \(sd.weekday.short) (\(sd.magnitude.label.lowercased()))"
            )
        }

        // 2. Lighten colliding lift days (fixed weekdays → downgrade, not move).
        let liftEntries: [(idx: Int, weekday: Weekday, workout: GeneratedWorkout)] =
            slots.indices.compactMap { i in
                guard let s = slots[i], !s.protected, s.kind == .lift,
                      let w = s.generatedWorkout else { return nil }
                return (i, Weekday.from(date: s.date, calendar: calendar), w)
            }
        guard !liftEntries.isEmpty else { return }
        let deconflicted = SupportScheduler.deconflictInPlace(
            lifts: liftEntries.map { ($0.weekday, $0.workout) },
            pattern: pattern,
            primaryVariant: primaryVariant
        )
        for (entry, result) in zip(liftEntries, deconflicted) where !result.adjustments.isEmpty {
            guard var day = slots[entry.idx] else { continue }
            day.generatedWorkout = result.workout
            let note = result.adjustments.joined(separator: "; ")
            day.generatedReason = [day.generatedReason, note]
                .compactMap { $0 }.joined(separator: " · ")
            slots[entry.idx] = day
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
        case .lift:  return 4
        case .sport: return 3
        case .event: return 3
        case .rest:  return 1
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

            // We never demote sports — fixed sports are protected, and shape sports
            // express the user's intent through their primary sport.
        }
        return result
    }

    private static func minDistance(from idx: Int, to positions: [Int]) -> Int {
        if positions.isEmpty { return Int.max }
        return positions.map { abs($0 - idx) }.min() ?? Int.max
    }

    // MARK: - BundledRoutineRow selection

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
        routines: [BundledRoutineRow],
        kind: DayKind,
        memory: TrainingMemory,
        slotOffset: Int
    ) -> BundledRoutineRow? {
        let profile = DemographicProfile.from(memory)
        return pickRoutine(routines: routines, kind: kind,
                           memory: memory, profile: profile,
                           slotOffset: slotOffset)
    }

    /// Profile-injected variant — Planner.generate computes the profile once
    /// per regeneration and threads it through; tests can also pass a custom
    /// profile to exercise the matrix without rebuilding memory.
    static func pickRoutine(
        routines: [BundledRoutineRow],
        kind: DayKind,
        memory: TrainingMemory,
        profile: DemographicProfile,
        slotOffset: Int
    ) -> BundledRoutineRow? {
        guard let goals = goalsFor(kind), !goals.isEmpty else { return nil }

        // Equipment + constraints — applied to every pass below.
        //
        // Equipment is two filters now: the existing routines.environment
        // whitelist (where) AND a per-routine required-equipment check
        // that joins exercise_equipment for every exercise the routine
        // contains. Build 103 — pre-fix, a bodyweight user could land on a
        // "home" routine whose exercises required barbells. The new check
        // rejects the routine when its required-equipment union isn't a
        // subset of the user's allow-list. Empty allow-list = no filter
        // (fullGym user).
        let envAndConstraintAllowed: (BundledRoutineRow) -> Bool = { r in
            environmentAllowed(r, allowed: profile.allowedEnvironments)
            && equipmentAllowed(r, allowed: profile.allowedEquipmentSlugs)
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
        // Equipment check is NOT dropped: shipping a routine the user
        // physically can't do is worse than shipping a name-keyword brush.
        let envOnlyNoConstraints = routines.filter { r in
            goalMatches(r, goals: goals)
                && environmentAllowed(r, allowed: profile.allowedEnvironments)
                && equipmentAllowed(r, allowed: profile.allowedEquipmentSlugs)
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
        case .lift: return ["strength", "direct_strength", "power", "accessory", "conditioning"]
        default:    return nil
        }
    }

    private static func goalMatches(_ r: BundledRoutineRow, goals: Set<String>) -> Bool {
        guard let g = r.goal else { return false }
        return goals.contains(g)
    }

    private static func difficultyMatches(_ r: BundledRoutineRow, allowed: Set<String>) -> Bool {
        guard let d = r.difficulty else { return true }   // tolerate unset
        return allowed.contains(d)
    }

    private static func durationOK(_ duration: Int?, target: Int) -> Bool {
        guard let d = duration else { return true }       // unknown ⇒ acceptable
        return abs(d - target) <= 20
    }

    private static func environmentAllowed(_ r: BundledRoutineRow, allowed: Set<String>) -> Bool {
        guard !allowed.isEmpty else { return true }       // empty = no filter
        guard let env = r.environment, !env.isEmpty else { return true }
        return allowed.contains(env)
    }

    /// Routine passes iff every required equipment slug across its exercises
    /// lies inside the user's allow-list. Empty allow-list = no filter
    /// (fullGym user). A routine with no required equipment (pure bodyweight
    /// pool with no junction rows) always passes.
    private static func equipmentAllowed(_ r: BundledRoutineRow, allowed: Set<String>) -> Bool {
        guard !allowed.isEmpty else { return true }
        let required = CoachDatabase.shared.requiredEquipmentSlugs(forRoutineId: r.id)
        return required.isSubset(of: allowed)
    }

    private static func constraintConflict(_ r: BundledRoutineRow, keywords: [String]) -> Bool {
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
