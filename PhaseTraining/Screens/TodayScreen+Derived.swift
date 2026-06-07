// TodayScreen+Derived.swift — read-only derived state + stateless helpers.
//
// Pure extraction from TodayScreen.swift (architecture item 12): every member
// here is a side-effect-free computed property or pure function over the
// stores / today's plan. No presentation state, no mutations. Members the
// main file (body, pills, buttons) or the template editor reads are internal;
// helpers consumed only within this file stay private.

import SwiftUI

extension TodayScreen {

    // MARK: - Derived state

    var todayPlan: DayPlan? { planStore.plan?.today() }

    /// Effective DayKind for rendering. Active session forces a workout
    /// hero. Otherwise, follow today's plan; default to lift if no plan.
    var effectiveKind: DayKind {
        if store.active != nil { return .lift }
        return todayPlan?.kind ?? .lift
    }

    /// Template for the workout hero. nil on sport/rest/event days when
    /// there's no active session.
    var template: WorkoutTemplate? {
        if let active = store.active, !active.exercises.isEmpty {
            return WorkoutTemplate(
                id: active.templateId,
                name: active.name,
                category: active.category,
                exercises: active.exercises.map { ex in
                    ExerciseTemplate(
                        id: ex.id, name: ex.name, type: ex.type, unit: ex.unit,
                        targetSets: ex.targetSets, targetReps: ex.targetReps, rest: ex.rest
                    )
                }
            )
        }
        // Generated workout (the new default for lift / mobility days).
        // Uses GeneratedWorkout.stableTemplateId — same exercises → same id,
        // so SessionStore.getPreviousSession finds last week's same-shape
        // workout and pulls weight + reps forward into the autofill column.
        if let _ = todayPlan, let workout = todayPlan?.generatedWorkout {
            return workout.toWorkoutTemplate(id: workout.stableTemplateId)
        }
        // Day-override picked a specific routine (custom workout or library pick).
        if let routineId = todayPlan?.routineId {
            return loadTemplate(routineId: routineId)
        }
        // No plan yet → upper-1 fallback. Guarantees TodayScreen always has
        // a usable template before onboarding runs.
        if planStore.plan == nil {
            return WorkoutTemplate.upper1
        }
        return nil
    }

    private func loadTemplate(routineId: Int) -> WorkoutTemplate? {
        let routines = CoachDatabase.shared.listRoutines()
        guard let r = routines.first(where: { $0.id == routineId }) else { return nil }
        let exercises = CoachDatabase.shared.exercises(forRoutineId: routineId)
        return r.toWorkoutTemplate(with: exercises)
    }

    private var totalSets: Int {
        template?.exercises.reduce(0) { $0 + $1.targetSets } ?? 0
    }

    var previous: SavedSession? {
        guard let template else { return nil }
        return store.getPreviousSession(templateId: template.id)
    }

    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: Date()).uppercased()
    }

    var heroTitle: String {
        switch effectiveKind {
        case .lift:
            return template?.name.replacingOccurrences(of: " Day ", with: "\nDay ")
                ?? (todayPlan?.title ?? "Train")
        case .sport:
            return todayPlan?.sport.map { "\($0.name)\nday" } ?? "Sport day"
        case .rest:
            return "Rest day"
        case .event:
            return "Event day"
        }
    }

    /// True when the current plan's last day is within 2 days (or already past).
    /// Drives the "Plan next week" pill.
    var planEndingSoon: Bool {
        guard let last = planStore.plan?.days.last?.date else { return false }
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let lastDay = cal.startOfDay(for: last)
        let daysLeft = cal.dateComponents([.day], from: now, to: lastDay).day ?? 0
        return daysLeft <= 2
    }

    /// Phase 13e: coach-written observation when present, otherwise the static
    /// Phase-11 rules. Picks first matching source.
    private var insightCopy: String? {
        let cal = Calendar.current
        if let coach = memoryStore.memory.coachInsights.last(where: {
            $0.surface == "today" && cal.isDate($0.date, inSameDayAs: Date())
        }) {
            return coach.body
        }
        guard let plan = planStore.plan else { return nil }
        if let day = plan.today() {
            if day.protected {
                return "Today is protected. I won't shuffle it without asking."
            }
            if let mins = day.durationMinutes {
                return "Today's session is shortened to \(mins) min."
            }
        }
        return nil
    }

    private var heroSubtitle: String {
        switch effectiveKind {
        case .lift:
            return template?.category ?? ""
        case .sport:
            if let log = todaySportLog {
                return "Logged · \(log.durationMinutes) min · \(log.intensity.label.lowercased())"
            }
            return todayPlan?.sport != nil ? "Log it when you're done." : "Sport day."
        case .rest:
            return "Sleep, food, walk. The work is in recovery."
        case .event:
            return todayPlan?.title ?? "Today's event."
        }
    }

    /// Today's most recent sport log, if any. Drives the subtitle swap
    /// and the "edit log" sheet pre-fill. Only meaningful on .sport days
    /// but read defensively (anyone could tap a stale link).
    var todaySportLog: SportLogEntry? {
        sportLogStore.entry(on: Date())
    }

    /// True when memory has a soreness entry stamped today.
    var todaysSorenessLogged: Bool {
        let cal = Calendar.current
        return memoryStore.memory.soreness.contains { cal.isDate($0.date, inSameDayAs: Date()) }
    }

    /// Trailing eyebrow text — the periodization phase. This is the app's
    /// namesake context (off-/pre-/in-season, event prep, maintenance), which
    /// previously surfaced only in Profile and the season editor. Appends
    /// DELOAD when this week's tone is Recovery — the only honest deload
    /// signal available (it's user-picked on the Week tab; there's no
    /// auto-scheduled mesocycle deload to read).
    var phaseEyebrow: String {
        var s = memoryStore.memory.seasonForPlanner.compactLabel.uppercased()
        if planStore.overrides.weekTone == .recovery { s += " · DELOAD" }
        return s
    }

    /// Days until the event-prep peak, when a peak date is set and the
    /// athlete is in event prep. nil otherwise (nothing to count down to).
    private var daysToPeak: Int? {
        guard memoryStore.memory.seasonForPlanner == .eventPrep,
              let peak = memoryStore.memory.peakDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: peak)).day ?? 0
        return days >= 0 ? days : nil
    }

    /// Subtitle line. The EX·SETS summary moved here from the eyebrow (which
    /// now carries the phase); non-workout days keep their kind-specific copy.
    /// An event-prep peak countdown appends on any day kind.
    var headerSubtitle: String? {
        var parts: [String] = []
        if effectiveKind.isWorkout, let template {
            parts.append("\(template.exercises.count) ex · \(totalSets) sets")
        } else if !heroSubtitle.isEmpty {
            parts.append(heroSubtitle)
        }
        if let d = daysToPeak {
            parts.append(d == 0 ? "peak today" : "peak in \(d)d")
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    /// Single source of truth for the small caption rendered under the hero
    /// subtitle. Coach insight wins if present; otherwise we fall back to
    /// the planner's static generatedReason.
    var heroCaption: String? {
        insightCopy ?? todayPlan?.generatedReason
    }

    var daysAgoShort: String {
        guard let prev = previous else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: prev.startTime, to: Date()).day ?? 0
        return "\(days)d ago"
    }

    var lastSessionDetail: String {
        guard let prev = previous else { return "First time — weights will be empty" }
        let stats = computeStats(prev)
        return "\(formatDuration(prev.duration)) · \(stats.doneSets) sets · avg rpe \(stats.avgRpe)"
    }

    func parseRepsLeading(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    func parseRestSeconds(_ s: String?) -> Int? {
        guard let s else { return nil }
        let lower = s.lowercased()
        let digits = lower.prefix(while: { $0.isNumber })
        guard let n = Int(digits) else { return nil }
        if lower.contains("min") { return n * 60 }
        return n
    }

    // MARK: - Helpers

    private func computeStats(_ session: SavedSession) -> (doneSets: Int, avgRpe: String) {
        var doneSets = 0
        var totalRpe: Double = 0
        var rpeCount = 0
        for ex in session.exercises {
            for s in ex.sets where s.done {
                doneSets += 1
                if !s.rpe.isEmpty, let v = Double(s.rpe), !v.isNaN {
                    totalRpe += v
                    rpeCount += 1
                }
            }
        }
        let avgRpe = rpeCount > 0 ? String(format: "%.1f", totalRpe / Double(rpeCount)) : "—"
        return (doneSets, avgRpe)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
